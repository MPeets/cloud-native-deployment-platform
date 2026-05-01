#!/usr/bin/env python3
"""Summarize Terraform plan JSON as an infrastructure drift report."""

from __future__ import annotations

import argparse
import json
import subprocess
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


@dataclass(frozen=True)
class TerraformPlanResult:
    """Result of a Terraform plan run plus JSON details when changes exist."""

    exit_code: int
    plan: Optional[dict[str, Any]]


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
        raw = path.read_text(encoding="utf-8") if path and str(path) != "-" else sys.stdin.read()
        parsed = json.loads(raw)
    except OSError as exc:
        source = str(path) if path else "stdin"
        raise ValueError(f"could not read {source}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"input is not valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Terraform plan JSON must be an object")
    return parsed


def _run_checked_json_command(cmd: list[str], *, cwd: Path) -> dict[str, Any]:
    """Run a command that emits a single JSON object on stdout."""
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise ValueError(f"could not run {' '.join(cmd)}: {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise ValueError(f"{' '.join(cmd)} failed with exit {proc.returncode}: {detail}")
    try:
        parsed = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{' '.join(cmd)} did not return valid JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{' '.join(cmd)} JSON output must be an object")
    return parsed


def run_terraform_plan(
    *,
    terraform_dir: Path,
    terraform_bin: str,
    plan_out: Path,
) -> TerraformPlanResult:
    """Run Terraform plan and return detailed JSON when Terraform reports changes."""
    plan_cmd = [
        terraform_bin,
        "plan",
        "-detailed-exitcode",
        "-lock-timeout=10m",
        f"-out={plan_out}",
    ]
    try:
        proc = subprocess.run(
            plan_cmd,
            cwd=terraform_dir,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise ValueError(f"could not run terraform plan in {terraform_dir}: {exc}") from exc
    if proc.returncode == EXIT_NO_DRIFT:
        return TerraformPlanResult(exit_code=EXIT_NO_DRIFT, plan=None)
    if proc.returncode != EXIT_DRIFT_DETECTED:
        detail = proc.stderr.strip() or proc.stdout.strip()
        raise ValueError(f"terraform plan failed with exit {proc.returncode}: {detail}")

    show_cmd = [terraform_bin, "show", "-json", str(plan_out)]
    plan = _run_checked_json_command(show_cmd, cwd=terraform_dir)
    return TerraformPlanResult(exit_code=EXIT_DRIFT_DETECTED, plan=plan)


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
        help="Path to Terraform plan JSON, or '-' for stdin. When omitted, Terraform is run.",
    )
    parser.add_argument(
        "--terraform-dir",
        default="infra",
        metavar="PATH",
        help="Terraform working directory (default: infra).",
    )
    parser.add_argument(
        "--terraform-bin",
        default="terraform",
        metavar="PATH",
        help="Terraform executable to run (default: terraform).",
    )
    parser.add_argument(
        "--plan-out",
        default=".terraform-drift-report.tfplan",
        metavar="PATH",
        help="Plan file path, relative to --terraform-dir unless absolute.",
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
    terraform_dir = Path(args.terraform_dir)
    plan_out = Path(args.plan_out)

    try:
        if plan_path is not None:
            plan = _load_plan_json(plan_path)
        else:
            result = run_terraform_plan(
                terraform_dir=terraform_dir,
                terraform_bin=args.terraform_bin,
                plan_out=plan_out,
            )
            if result.plan is None:
                _write_report(format_drift_report([]), output_path)
                return EXIT_NO_DRIFT
            plan = result.plan
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
