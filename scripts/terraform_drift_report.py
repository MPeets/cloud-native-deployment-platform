#!/usr/bin/env python3
"""Summarize Terraform plan JSON as an infrastructure drift report."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

EXIT_NO_DRIFT = 0
EXIT_ERROR = 1
EXIT_DRIFT_DETECTED = 2

_IGNORED_ACTIONS = (("no-op",), ("read",))


@dataclass(frozen=True)
class DriftChange:
    """One managed resource change from a Terraform plan."""

    address: str
    action: str
    resource_type: str
    provider_name: str


def _normalize_action(actions: list[str]) -> str:
    """Collapse Terraform action arrays into concise report labels."""
    if actions == ["create"]:
        return "create"
    if actions == ["update"]:
        return "update"
    if actions == ["delete"]:
        return "delete"
    if actions == ["delete", "create"]:
        return "replace"
    if actions == ["create", "delete"]:
        return "replace"
    return "+".join(actions) if actions else "unknown"


def extract_drift_changes(plan: dict[str, Any]) -> list[DriftChange]:
    """Return managed resource changes that represent drift from desired state."""
    changes: list[DriftChange] = []
    for raw_change in plan.get("resource_changes", []):
        if raw_change.get("mode") != "managed":
            continue
        change = raw_change.get("change", {})
        actions = change.get("actions", [])
        if not isinstance(actions, list):
            continue
        action_tuple = tuple(str(action) for action in actions)
        if action_tuple in _IGNORED_ACTIONS:
            continue
        changes.append(
            DriftChange(
                address=str(raw_change.get("address", "(unknown)")),
                action=_normalize_action(list(action_tuple)),
                resource_type=str(raw_change.get("type", "(unknown)")),
                provider_name=str(raw_change.get("provider_name", "(unknown)")),
            )
        )
    return changes


def format_drift_report(changes: list[DriftChange]) -> str:
    """Render a compact human-readable drift summary."""
    if not changes:
        return "No infrastructure drift detected.\n"

    counts = Counter(change.action for change in changes)
    lines = [
        "Infrastructure drift detected.",
        "",
        f"Changed managed resources: {len(changes)}",
        "",
        "Summary by action:",
    ]
    for action, count in sorted(counts.items()):
        lines.append(f"- {action}: {count}")

    lines.extend(["", "Changed resources:"])
    for change in sorted(changes, key=lambda item: item.address):
        lines.append(
            f"- {change.address}: {change.action} "
            f"({change.resource_type}, {change.provider_name})"
        )
    return "\n".join(lines) + "\n"


def _load_plan_json(path: Optional[Path]) -> dict[str, Any]:
    """Load Terraform plan JSON from a path or stdin."""
    try:
        raw = path.read_text(encoding="utf-8") if path else sys.stdin.read()
        parsed = json.loads(raw)
    except OSError as exc:
        source = str(path) if path else "stdin"
        raise ValueError(f"could not read {source}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"input is not valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Terraform plan JSON must be an object")
    return parsed


def _write_report(body: str, output_path: Optional[Path]) -> None:
    """Write report text to a path or stdout."""
    if output_path is not None:
        output_path.write_text(body, encoding="utf-8", newline="\n")
    else:
        print(body, end="")


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Parse Terraform plan JSON and report managed resource drift. "
            "Exits 0 when no drift is found and 2 when drift is detected."
        )
    )
    parser.add_argument(
        "--plan-json",
        metavar="PATH",
        help="Path to Terraform plan JSON. Reads stdin when omitted.",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="PATH",
        help="Write the drift report to this path instead of stdout.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    """CLI entry point for Terraform drift reporting."""
    args = _parse_args(argv)
    plan_path = Path(args.plan_json) if args.plan_json else None
    output_path = Path(args.output) if args.output else None

    try:
        plan = _load_plan_json(plan_path)
        changes = extract_drift_changes(plan)
        _write_report(format_drift_report(changes), output_path)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_ERROR
    except OSError as exc:
        target = args.output or "stdout"
        print(f"error: could not write {target}: {exc}", file=sys.stderr)
        return EXIT_ERROR

    return EXIT_DRIFT_DETECTED if changes else EXIT_NO_DRIFT


if __name__ == "__main__":
    raise SystemExit(main())
