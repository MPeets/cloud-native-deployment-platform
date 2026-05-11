#!/usr/bin/env python3
"""Unit tests for Terraform drift report parsing and formatting."""

# pylint: disable=protected-access,wrong-import-position

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import terraform_drift_report as drift


class TerraformDriftReportTests(unittest.TestCase):
    """Coverage for drift extraction and human-readable report rendering."""

    def test_extract_drift_changes_filters_noise_and_normalizes_actions(self) -> None:
        """Managed no-op/read changes and data resources are ignored."""
        plan = {
            "resource_changes": [
                {
                    "address": "aws_ecs_service.api",
                    "mode": "managed",
                    "type": "aws_ecs_service",
                    "provider_name": "registry.terraform.io/hashicorp/aws",
                    "change": {"actions": ["update"]},
                },
                {
                    "address": "aws_lb_target_group.api",
                    "mode": "managed",
                    "type": "aws_lb_target_group",
                    "provider_name": "registry.terraform.io/hashicorp/aws",
                    "change": {"actions": ["delete", "create"]},
                },
                {
                    "address": "aws_cloudwatch_log_group.api",
                    "mode": "managed",
                    "type": "aws_cloudwatch_log_group",
                    "provider_name": "registry.terraform.io/hashicorp/aws",
                    "change": {"actions": ["no-op"]},
                },
                {
                    "address": "data.aws_region.current",
                    "mode": "data",
                    "type": "aws_region",
                    "provider_name": "registry.terraform.io/hashicorp/aws",
                    "change": {"actions": ["read"]},
                },
            ]
        }

        changes = drift.extract_drift_changes(plan)

        self.assertEqual(
            changes,
            [
                drift.DriftChange(
                    address="aws_ecs_service.api",
                    action="update",
                    resource_type="aws_ecs_service",
                    provider_name="registry.terraform.io/hashicorp/aws",
                ),
                drift.DriftChange(
                    address="aws_lb_target_group.api",
                    action="replace",
                    resource_type="aws_lb_target_group",
                    provider_name="registry.terraform.io/hashicorp/aws",
                ),
            ],
        )

    def test_parse_plan_json_text_accepts_line_delimited_ui_events(self) -> None:
        """Terraform plan -json UI events are converted into resource_changes."""
        events = "\n".join(
            [
                json.dumps({"type": "version", "terraform": "1.13.0"}),
                json.dumps(
                    {
                        "type": "planned_change",
                        "change": {
                            "action": "replace",
                            "resource": {
                                "addr": "aws_ecs_task_definition.api",
                                "resource_type": "aws_ecs_task_definition",
                                "provider_name": "registry.terraform.io/hashicorp/aws",
                            },
                        },
                    }
                ),
            ]
        )

        plan = drift._parse_plan_json_text(events)

        self.assertEqual(
            plan,
            {
                "resource_changes": [
                    {
                        "address": "aws_ecs_task_definition.api",
                        "mode": "managed",
                        "type": "aws_ecs_task_definition",
                        "provider_name": "registry.terraform.io/hashicorp/aws",
                        "change": {"actions": ["delete", "create"]},
                    }
                ]
            },
        )

    def test_parse_plan_json_text_rejects_invalid_event_stream_lines(self) -> None:
        """Bad JSON lines return a clear parser error instead of silent success."""
        with self.assertRaisesRegex(ValueError, "line 2 is invalid"):
            drift._parse_plan_json_text('{"type":"version"}\nnot-json\n')

    def test_format_drift_report_sorts_resources_and_summarizes_actions(self) -> None:
        """Report output is stable enough for CI summaries and artifacts."""
        report = drift.format_drift_report(
            [
                drift.DriftChange(
                    address="aws_sns_topic.ops",
                    action="create",
                    resource_type="aws_sns_topic",
                    provider_name="registry.terraform.io/hashicorp/aws",
                ),
                drift.DriftChange(
                    address="aws_ecs_service.api",
                    action="update",
                    resource_type="aws_ecs_service",
                    provider_name="registry.terraform.io/hashicorp/aws",
                ),
            ]
        )

        self.assertIn("Infrastructure drift detected.", report)
        self.assertIn("Changed managed resources: 2", report)
        self.assertLess(report.index("- create: 1"), report.index("- update: 1"))
        self.assertLess(report.index("aws_ecs_service.api"), report.index("aws_sns_topic.ops"))

    def test_format_drift_report_handles_empty_changes(self) -> None:
        """Empty changes produce the no-drift message used by automation."""
        self.assertEqual(drift.format_drift_report([]), "No infrastructure drift detected.\n")


if __name__ == "__main__":
    unittest.main()
