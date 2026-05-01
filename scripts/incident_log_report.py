#!/usr/bin/env python3
"""Fetch CloudWatch Logs for an incident window and emit a grouped incident report.

The companion to ``health_check.py``: that script answers live deployment health;
this one supports post-incident review by pulling log events over a chosen time range.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

from dateutil import parser as date_parser

_SINCE_RE = re.compile(r"^(\d+)([smhd])$", re.IGNORECASE)


@dataclass(frozen=True)
class TimeWindowMs:
    """Inclusive start and exclusive-ish end as CloudWatch expects (epoch milliseconds, UTC)."""

    start_ms: int
    end_ms: int


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
            "Pull logs from a CloudWatch log group over a time window and "
            "emit a grouped incident report (ERROR / WARN / INFO)."
        ),
    )
    parser.add_argument(
        "--log-group",
        default=os.environ.get("LOG_GROUP", "/ecs/devops-api"),
        help="CloudWatch log group (default: env LOG_GROUP or /ecs/devops-api)",
    )
    parser.add_argument(
        "--region",
        default=_default_region(),
        help="AWS region (default: AWS_REGION / AWS_DEFAULT_REGION or eu-north-1)",
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
    """Entry point: parse window, optionally dry-run; later emits the incident report."""
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

    print("error: log fetch not implemented yet (use --dry-run)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
