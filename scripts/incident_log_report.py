#!/usr/bin/env python3
"""Fetch CloudWatch Logs for an incident window and emit structured output.

Companion to ``health_check.py`` (live checks); this supports post-incident review.
Pulls paginated events, classifies each line by log level, and prints JSON or Markdown.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import boto3
from botocore.exceptions import ClientError
from dateutil import parser as date_parser

_SINCE_RE = re.compile(r"^(\d+)([smhd])$", re.IGNORECASE)
_JSON_LEVEL_ERROR = re.compile(r'"level"\s*:\s*"error"', re.IGNORECASE)
_JSON_LEVEL_WARN = re.compile(r'"level"\s*:\s*"warn', re.IGNORECASE)
_JSON_LEVEL_INFO = re.compile(r'"level"\s*:\s*"info"', re.IGNORECASE)
_TEXT_LEVEL_ERROR = re.compile(r"\bERROR\b", re.IGNORECASE)
_TEXT_LEVEL_WARN = re.compile(r"\bWARN(?:ING)?\b", re.IGNORECASE)
_TEXT_LEVEL_INFO = re.compile(r"\bINFO\b", re.IGNORECASE)

_LEVEL_KEYS = ("ERROR", "WARN", "INFO", "UNKNOWN")


@dataclass(frozen=True)
class TimeWindowMs:
    """Inclusive start and exclusive-ish end as CloudWatch expects (epoch milliseconds, UTC)."""

    start_ms: int
    end_ms: int


@dataclass(frozen=True)
class RawLogEvent:
    """One row from ``filter_log_events`` (message body + metadata for the report)."""

    timestamp_ms: int
    message: str
    log_stream: str


def fetch_log_events(
    logs,
    *,
    log_group: str,
    window: TimeWindowMs,
    max_events: Optional[int],
) -> tuple[list[RawLogEvent], Optional[ClientError]]:
    """Paginate ``filter_log_events`` until the window is exhausted or ``max_events`` is reached."""
    collected: list[RawLogEvent] = []
    next_token: Optional[str] = None
    try:
        while True:
            kwargs: dict[str, Any] = {
                "logGroupName": log_group,
                "startTime": window.start_ms,
                "endTime": window.end_ms,
            }
            if next_token:
                kwargs["nextToken"] = next_token
            resp = logs.filter_log_events(**kwargs)
            for ev in resp.get("events", ()):
                collected.append(
                    RawLogEvent(
                        timestamp_ms=int(ev["timestamp"]),
                        message=str(ev.get("message", "")),
                        log_stream=str(ev.get("logStreamName", "")),
                    )
                )
                if max_events is not None and len(collected) >= max_events:
                    return collected, None
            next_token = resp.get("nextToken")
            if not next_token:
                break
    except ClientError as exc:
        return [], exc
    return collected, None


def _classify_log_level(message: str) -> str:
    """Best-effort level from JSON log fields or plain-text tokens (order: ERROR → WARN → INFO)."""
    patterns: tuple[tuple[re.Pattern[str], str], ...] = (
        (_JSON_LEVEL_ERROR, "ERROR"),
        (_JSON_LEVEL_WARN, "WARN"),
        (_JSON_LEVEL_INFO, "INFO"),
        (_TEXT_LEVEL_ERROR, "ERROR"),
        (_TEXT_LEVEL_WARN, "WARN"),
        (_TEXT_LEVEL_INFO, "INFO"),
    )
    for pattern, label in patterns:
        if pattern.search(message):
            return label
    return "UNKNOWN"


def _format_ts_utc(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


@dataclass(frozen=True)
class IncidentReportInput:
    """Inputs for ``build_incident_report`` (keeps the builder signature small for pylint)."""

    log_group: str
    region: str
    window: TimeWindowMs
    events: list[RawLogEvent]
    truncated: bool
    generated_at: Optional[datetime] = None


def build_incident_report(inp: IncidentReportInput) -> dict[str, Any]:
    """Group events by classified level for JSON or Markdown rendering."""
    gen = (inp.generated_at or datetime.now(timezone.utc)).astimezone(timezone.utc)
    by_level: dict[str, list[dict[str, Any]]] = {k: [] for k in _LEVEL_KEYS}
    for ev in inp.events:
        level = _classify_log_level(ev.message)
        by_level[level].append(
            {
                "timestamp_ms": ev.timestamp_ms,
                "timestamp_utc": _format_ts_utc(ev.timestamp_ms),
                "log_stream": ev.log_stream,
                "message": ev.message,
            }
        )
    summary = {lvl: len(by_level[lvl]) for lvl in _LEVEL_KEYS}
    return {
        "incident_report_version": 1,
        "generated_at": gen.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "log_group": inp.log_group,
        "region": inp.region,
        "start_ms": inp.window.start_ms,
        "end_ms": inp.window.end_ms,
        "truncated": inp.truncated,
        "summary": summary,
        "by_level": by_level,
    }


def format_report_markdown(report: dict[str, Any]) -> str:
    """Render a short incident-ready Markdown document from ``build_incident_report`` output."""
    lines: list[str] = [
        "# Incident log report",
        "",
        f"- **Generated**: {report['generated_at']}",
        f"- **Log group**: `{report['log_group']}`",
        f"- **Region**: `{report['region']}`",
        f"- **Window (epoch ms)**: `{report['start_ms']}` → `{report['end_ms']}`",
        f"- **Truncated (cap hit)**: {report['truncated']}",
        "",
        "## Summary",
        "",
    ]
    for lvl in _LEVEL_KEYS:
        lines.append(f"- **{lvl}**: {report['summary'][lvl]}")
    lines.append("")

    for lvl in _LEVEL_KEYS:
        items = report["by_level"][lvl]
        if not items:
            continue
        lines.append(f"## {lvl} ({len(items)})")
        lines.append("")
        for item in items:
            stream = item["log_stream"] or "(default)"
            lines.append(f"### {item['timestamp_utc']} — `{stream}`")
            lines.append("")
            lines.append("```")
            lines.append(str(item["message"]))
            lines.append("```")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _parse_since(since: str, *, now: Optional[datetime] = None) -> tuple[datetime, datetime]:
    """Parse ``--since`` values like ``30m``, ``2h``, ``1d`` (end = now UTC)."""
    match = _SINCE_RE.match(since.strip())
    if not match:
        raise ValueError(
            f"invalid --since {since!r}: expected e.g. 30m, 2h, 1d (number + s|m|h|d)"
        )
    amount = int(match.group(1))
    unit = match.group(2).lower()
    delta = {
        "s": timedelta(seconds=amount),
        "m": timedelta(minutes=amount),
        "h": timedelta(hours=amount),
        "d": timedelta(days=amount),
    }[unit]
    end = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    start = end - delta
    return start, end


def _parse_instant(field_name: str, raw: str) -> datetime:
    """Parse a timestamp string to aware UTC (``dateutil`` + naive → UTC)."""
    try:
        dt = date_parser.parse(raw.strip())
    except (ValueError, TypeError, OverflowError) as exc:
        raise ValueError(f"invalid {field_name} timestamp {raw!r}: {exc}") from exc
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def resolve_time_window_ms(
    *,
    since: Optional[str],
    time_from: Optional[str],
    time_to: Optional[str],
    now: Optional[datetime] = None,
) -> TimeWindowMs:
    """Return epoch milliseconds for CloudWatch ``startTime`` / ``endTime``."""
    if since:
        if time_from or time_to:
            raise ValueError("use either --since or --from/--to, not both")
        start, end = _parse_since(since, now=now)
    elif time_from and time_to:
        start = _parse_instant("from", time_from)
        end = _parse_instant("to", time_to)
        if start >= end:
            raise ValueError("--from must be strictly before --to")
    else:
        raise ValueError("provide --since DURATION or both --from and --to")

    start_ms = int(start.timestamp() * 1000)
    end_ms = int(end.timestamp() * 1000)
    return TimeWindowMs(start_ms=start_ms, end_ms=end_ms)


def _default_region() -> str:
    return (
        os.environ.get("AWS_REGION")
        or os.environ.get("AWS_DEFAULT_REGION")
        or "eu-north-1"
    )


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Pull logs from a CloudWatch log group over a time window. "
            "Groups lines by level (ERROR / WARN / INFO) and prints JSON or Markdown."
        ),
    )
    parser.add_argument(
        "--log-group",
        default=os.environ.get("LOG_GROUP", "/ecs/devops-api"),
        help="CloudWatch Logs group name (default: $LOG_GROUP or /ecs/devops-api)",
    )
    parser.add_argument(
        "--region",
        default=_default_region(),
        help=(
            "AWS region for the Logs API "
            "(default: $AWS_REGION / $AWS_DEFAULT_REGION or eu-north-1)"
        ),
    )
    parser.add_argument(
        "--since",
        metavar="DURATION",
        help="Relative window ending now, e.g. 30m, 2h, 1d",
    )
    parser.add_argument(
        "--from",
        dest="time_from",
        metavar="TIMESTAMP",
        help="Window start (ISO-8601); use with --to",
    )
    parser.add_argument(
        "--to",
        dest="time_to",
        metavar="TIMESTAMP",
        help="Window end (ISO-8601); use with --from",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only validate the time window and print epoch ms; no AWS calls",
    )
    parser.add_argument(
        "--max-events",
        type=int,
        default=100_000,
        metavar="N",
        help="Stop after N events (0 = no cap; default 100000)",
    )
    parser.add_argument(
        "--format",
        choices=("json", "markdown"),
        default="json",
        help="Incident report output format (default json)",
    )
    args = parser.parse_args(argv)
    modes = int(bool(args.since)) + int(bool(args.time_from or args.time_to))
    if modes == 0:
        parser.error("provide --since DURATION or both --from and --to")
    if args.since and (args.time_from or args.time_to):
        parser.error("use either --since or --from/--to")
    if args.time_from and not args.time_to:
        parser.error("--from requires --to")
    if args.time_to and not args.time_from:
        parser.error("--to requires --from")
    return args


def main(argv: Optional[list[str]] = None) -> int:
    """Entry point: fetch logs, classify by level, print JSON or Markdown."""
    args = _parse_args(argv)
    try:
        window = resolve_time_window_ms(
            since=args.since,
            time_from=args.time_from,
            time_to=args.time_to,
        )
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.dry_run:
        print(f"log_group={args.log_group!r} region={args.region!r}")
        print(f"start_ms={window.start_ms} end_ms={window.end_ms}")
        return 0

    cap: Optional[int] = None if args.max_events == 0 else args.max_events
    logs = boto3.client("logs", region_name=args.region)
    events, err = fetch_log_events(
        logs,
        log_group=args.log_group,
        window=window,
        max_events=cap,
    )
    if err is not None:
        print(f"error: filter_log_events failed: {err}", file=sys.stderr)
        return 1

    truncated = cap is not None and len(events) >= cap
    report = build_incident_report(
        IncidentReportInput(
            log_group=args.log_group,
            region=args.region,
            window=window,
            events=events,
            truncated=truncated,
        )
    )
    if args.format == "markdown":
        print(format_report_markdown(report), end="")
    else:
        print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
