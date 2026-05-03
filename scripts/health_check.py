"""Deployment health checks against ALB, ECS, and CloudWatch."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from typing import Optional

import boto3
import requests
from botocore.exceptions import ClientError


def _configure_stdio_utf8() -> None:
    """Avoid UnicodeEncodeError on Windows consoles when printing ✓/✗."""
    for stream in (sys.stdout, sys.stderr):
        try:
            if hasattr(stream, "reconfigure"):
                stream.reconfigure(encoding="utf-8")
        except (OSError, ValueError):
            pass


@dataclass
class CheckResult:
    """Outcome of a single health check."""

    name: str
    passed: bool
    message: str
    duration_ms: Optional[float] = None


@dataclass(frozen=True)
class RunChecksParams:  # pylint: disable=too-many-instance-attributes
    """Inputs for run_checks (single bundle keeps call sites and pylint happy)."""

    alb_dns: str
    region: str
    cluster: str
    service_name: str
    log_group: str
    log_lookback_minutes: int
    timeout: float
    retries: int
    skip_aws: bool


def print_report(
    *,
    target_url: str,
    region: str,
    cluster: str,
    service: str,
    results: list[CheckResult],
) -> None:
    """Print the deployment health report to stdout."""
    _configure_stdio_utf8()
    print("=== Deployment Health Check ===")
    print(f"Target: {target_url}")
    print(f"Region: {region} | Cluster: {cluster} | Service: {service}")
    for r in results:
        mark = "✓" if r.passed else "✗"
        timing = ""
        if r.duration_ms is not None:
            timing = f" ({r.duration_ms:.0f}ms)"
        print(f"  [{mark}] {r.name:<14} {r.message}{timing}")
    total = len(results)
    failed = sum(1 for r in results if not r.passed)
    if failed == 0:
        print(f"All checks passed. ({total}/{total})")
    else:
        print(f"{failed} check(s) failed. ({failed}/{total})")


def _http_base_url(alb_dns: str) -> str:
    """Normalize ALB host or host:port to an HTTP base URL without trailing slash."""
    host = alb_dns.strip()
    if host.startswith(("http://", "https://")):
        return host.rstrip("/")
    return f"http://{host}".rstrip("/")


def check_alb_liveness(
    alb_dns: str,
    *,
    timeout: float = 10.0,
    retries: int = 3,
    backoff_seconds: float = 2.0,
) -> CheckResult:
    """GET / — expect HTTP 200; retry on transient failures."""
    base = _http_base_url(alb_dns)
    url = f"{base}/"
    last_detail = ""

    for attempt in range(1, retries + 1):
        try:
            t0 = time.perf_counter()
            resp = requests.get(url, timeout=timeout)
            elapsed_ms = (time.perf_counter() - t0) * 1000
            if resp.status_code == 200:
                return CheckResult(
                    name="ALB liveness",
                    passed=True,
                    message=f"GET / {resp.status_code} OK",
                    duration_ms=elapsed_ms,
                )
            last_detail = f"HTTP {resp.status_code}"
        except requests.RequestException as exc:
            last_detail = str(exc)

        if attempt < retries:
            time.sleep(backoff_seconds)

    return CheckResult(
        name="ALB liveness",
        passed=False,
        message=f"GET / failed after {retries} attempt(s): {last_detail}",
        duration_ms=None,
    )


def check_alb_health(
    alb_dns: str,
    *,
    timeout: float = 10.0,
    retries: int = 3,
    backoff_seconds: float = 2.0,
) -> CheckResult:
    """GET /health — expect HTTP 200 and JSON {\"status\": \"ok\"}."""
    base = _http_base_url(alb_dns)
    url = f"{base}/health"
    last_detail = ""

    for attempt in range(1, retries + 1):
        try:
            t0 = time.perf_counter()
            resp = requests.get(url, timeout=timeout)
            elapsed_ms = (time.perf_counter() - t0) * 1000

            if resp.status_code != 200:
                last_detail = f"HTTP {resp.status_code}"
            else:
                try:
                    body = resp.json()
                except json.JSONDecodeError:
                    last_detail = "response is not valid JSON"
                else:
                    if isinstance(body, dict) and body.get("status") == "ok":
                        snippet = json.dumps({"status": body.get("status")}, separators=(",", ":"))
                        return CheckResult(
                            name="ALB health",
                            passed=True,
                            message=f'GET /health {resp.status_code} {snippet}',
                            duration_ms=elapsed_ms,
                        )
                    last_detail = f'body status is not "ok": {body!r}'
        except requests.RequestException as exc:
            last_detail = str(exc)

        if attempt < retries:
            time.sleep(backoff_seconds)

    return CheckResult(
        name="ALB health",
        passed=False,
        message=f"GET /health failed after {retries} attempt(s): {last_detail}",
        duration_ms=None,
    )


def check_ecs_service(
    *,
    cluster: str,
    service_name: str,
    region: str,
) -> CheckResult:
    """Ensure ECS runningCount matches desiredCount; note pending and rollout state."""
    ecs = boto3.client("ecs", region_name=region)
    try:
        resp = ecs.describe_services(cluster=cluster, services=[service_name])
    except ClientError as exc:
        return CheckResult(
            name="ECS service",
            passed=False,
            message=f"describe_services failed: {exc}",
            duration_ms=None,
        )

    failures = resp.get("failures") or []
    if failures:
        detail = failures[0].get("reason", failures[0])
        return CheckResult(
            name="ECS service",
            passed=False,
            message=f"ECS API failure: {detail}",
            duration_ms=None,
        )

    services = resp.get("services") or []
    if not services:
        return CheckResult(
            name="ECS service",
            passed=False,
            message=f"service {service_name!r} not found in cluster {cluster!r}",
            duration_ms=None,
        )

    return _ecs_service_counts_result(services[0])


def _ecs_service_counts_result(svc: dict) -> CheckResult:
    """Build ECS task-count CheckResult from describe_services service dict."""
    running = svc.get("runningCount", 0)
    desired = svc.get("desiredCount", 0)
    pending = svc.get("pendingCount", 0)
    deployments = svc.get("deployments") or []

    msg = f"{running}/{desired} tasks running, {pending} pending"
    extras: list[str] = []
    if pending > 0 and running == desired:
        extras.append("pending tasks (deployment may still be converging)")
    if len(deployments) > 1:
        extras.append("multiple deployments active (rollout in progress)")
    if extras:
        msg = f"{msg} — note: {'; '.join(extras)}"

    passed = running == desired
    return CheckResult(
        name="ECS service",
        passed=passed,
        message=msg,
        duration_ms=None,
    )


def _log_message_indicates_error(message: str) -> bool:
    """Match log lines containing ERROR, error, Exception, or FATAL (per project spec)."""
    if "ERROR" in message or "error" in message:
        return True
    if "Exception" in message:
        return True
    if "FATAL" in message:
        return True
    return False


def check_cloudwatch_errors(
    *,
    log_group: str,
    region: str,
    log_lookback_minutes: int,
) -> CheckResult:
    """Scan recent log events for error-like substrings."""
    logs = boto3.client("logs", region_name=region)
    end_ms = int(time.time() * 1000)
    start_ms = end_ms - log_lookback_minutes * 60 * 1000

    count, cw_err = _cloudwatch_error_like_event_count(
        logs,
        log_group=log_group,
        start_ms=start_ms,
        end_ms=end_ms,
    )
    if cw_err is not None:
        return CheckResult(
            name="CloudWatch",
            passed=False,
            message=f"filter_log_events failed: {cw_err}",
            duration_ms=None,
        )

    window = f"last {log_lookback_minutes} min"
    if count == 0:
        msg = f"0 errors in {window}"
    else:
        msg = f"{count} error events in {window}"

    return CheckResult(
        name="CloudWatch",
        passed=(count == 0),
        message=msg,
        duration_ms=None,
    )


def _cloudwatch_error_like_event_count(
    logs,
    *,
    log_group: str,
    start_ms: int,
    end_ms: int,
) -> tuple[int, Optional[ClientError]]:
    """Paginate filter_log_events and count messages matching error patterns."""
    error_count = 0
    next_token: Optional[str] = None
    try:
        while True:
            kwargs: dict = {
                "logGroupName": log_group,
                "startTime": start_ms,
                "endTime": end_ms,
            }
            if next_token:
                kwargs["nextToken"] = next_token
            resp = logs.filter_log_events(**kwargs)
            for ev in resp.get("events", ()):
                if _log_message_indicates_error(ev.get("message", "")):
                    error_count += 1
            next_token = resp.get("nextToken")
            if not next_token:
                break
    except ClientError as exc:
        return 0, exc
    return error_count, None


def run_checks(params: RunChecksParams) -> list[CheckResult]:
    """Run all enabled checks in order."""
    backoff_seconds = 2.0
    results: list[CheckResult] = [
        check_alb_liveness(
            params.alb_dns,
            timeout=params.timeout,
            retries=params.retries,
            backoff_seconds=backoff_seconds,
        ),
        check_alb_health(
            params.alb_dns,
            timeout=params.timeout,
            retries=params.retries,
            backoff_seconds=backoff_seconds,
        ),
    ]
    if not params.skip_aws:
        results.append(
            check_ecs_service(
                cluster=params.cluster,
                service_name=params.service_name,
                region=params.region,
            )
        )
        results.append(
            check_cloudwatch_errors(
                log_group=params.log_group,
                region=params.region,
                log_lookback_minutes=params.log_lookback_minutes,
            )
        )
    return results


def _env_truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes")


def _effective_infra_environment() -> str:
    """Match infra/envs naming: terraform `environment` and CI `${TF_INFRA_ENVIRONMENT:-prod}`."""
    raw = (
        os.environ.get("TF_INFRA_ENVIRONMENT")
        or os.environ.get("TF_ENV")
        or ""
    ).strip().lower()
    return raw if raw else "prod"


def _default_name_prefix() -> str:
    """
    ECS cluster_name and log-group prefix mirror Terraform locals:
    name_prefix = \"${base}-${var.environment}\" (default base devops-api).
    """
    base = (
        os.environ.get("TF_STACK_PREFIX_BASE")
        or os.environ.get("ECS_NAME_PREFIX")
        or "devops-api"
    ).strip()
    if not base:
        base = "devops-api"
    return f"{base}-{_effective_infra_environment()}"


def _default_ecs_cluster() -> str:
    override = os.environ.get("ECS_CLUSTER", "").strip()
    if override:
        return override
    return _default_name_prefix()


def _default_ecs_service() -> str:
    override = os.environ.get("ECS_SERVICE", "").strip()
    if override:
        return override
    return f"{_default_name_prefix()}-api"


def _default_log_group() -> str:
    override = os.environ.get("LOG_GROUP", "").strip()
    if override:
        return override
    return f"/ecs/{_default_name_prefix()}"


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    defaults_region = (
        os.environ.get("AWS_REGION")
        or os.environ.get("AWS_DEFAULT_REGION")
        or "eu-north-1"
    )
    parser = argparse.ArgumentParser(
        description="Verify deployment health (ALB HTTP, ECS, CloudWatch logs).",
    )
    parser.add_argument(
        "--alb-dns",
        default=os.environ.get("ALB_DNS"),
        help="ALB DNS name or host:port (default: env ALB_DNS)",
    )
    parser.add_argument(
        "--region",
        default=defaults_region,
        help="AWS region (default: AWS_REGION / AWS_DEFAULT_REGION or eu-north-1)",
    )
    parser.add_argument(
        "--cluster",
        default=_default_ecs_cluster(),
        help=(
            "ECS cluster (default: ECS_CLUSTER or devops-api-<TF_INFRA_ENVIRONMENT>, "
            "prod if unset; matches Terraform cluster name_prefix)"
        ),
    )
    parser.add_argument(
        "--service",
        default=_default_ecs_service(),
        help=(
            "ECS service (default: ECS_SERVICE else <prefix>-api; "
            "prefix from TF_INFRA_ENVIRONMENT)"
        ),
    )
    parser.add_argument(
        "--log-group",
        default=_default_log_group(),
        help=(
            "CloudWatch log group (default: LOG_GROUP else /ecs/<prefix>; "
            "prefix from TF_INFRA_ENVIRONMENT)"
        ),
    )
    parser.add_argument(
        "--log-lookback",
        type=int,
        default=int(os.environ.get("LOG_LOOKBACK_MINUTES", "5")),
        metavar="MINUTES",
        help="Minutes of logs to scan (default: env LOG_LOOKBACK_MINUTES or 5)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("HEALTH_CHECK_TIMEOUT", "10")),
        help="HTTP timeout in seconds (default: env HEALTH_CHECK_TIMEOUT or 10)",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=int(os.environ.get("HEALTH_CHECK_RETRIES", "3")),
        help="HTTP retry attempts (default: env HEALTH_CHECK_RETRIES or 3)",
    )
    parser.add_argument(
        "--skip-aws",
        action="store_true",
        help="Skip ECS and CloudWatch checks (no AWS API calls)",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Print sample reports only and exit successfully",
    )
    args = parser.parse_args(argv)
    if _env_truthy("SKIP_AWS"):
        args.skip_aws = True
    return args


def main(argv: Optional[list[str]] = None) -> int:
    """Parse CLI arguments, run checks, print report; return 0 if all pass."""
    args = _parse_args(argv)
    if args.demo:
        _demo_report()
        return 0

    alb_dns = args.alb_dns
    if not alb_dns:
        print("error: provide --alb-dns or set ALB_DNS", file=sys.stderr)
        return 1

    results = run_checks(
        RunChecksParams(
            alb_dns=alb_dns,
            region=args.region,
            cluster=args.cluster,
            service_name=args.service,
            log_group=args.log_group,
            log_lookback_minutes=args.log_lookback,
            timeout=args.timeout,
            retries=args.retries,
            skip_aws=args.skip_aws,
        )
    )
    target_url = _http_base_url(alb_dns)
    print_report(
        target_url=target_url,
        region=args.region,
        cluster=args.cluster,
        service=args.service,
        results=results,
    )
    if any(not r.passed for r in results):
        return 1
    return 0


def _demo_report() -> None:
    """Sample output for manual verification of formatting."""
    all_pass = [
        CheckResult(
            name="ALB liveness",
            passed=True,
            message="GET / 200 OK",
            duration_ms=47,
        ),
        CheckResult(
            name="ALB health",
            passed=True,
            message='GET /health 200 {"status":"ok"}',
            duration_ms=43,
        ),
        CheckResult(
            name="ECS service",
            passed=True,
            message="1/1 tasks running, 0 pending",
            duration_ms=None,
        ),
        CheckResult(
            name="CloudWatch",
            passed=True,
            message="0 errors in last 5 min",
            duration_ms=None,
        ),
    ]
    partial_fail = [
        all_pass[0],
        all_pass[1],
        CheckResult(
            name="ECS service",
            passed=False,
            message="0/1 tasks running, 1 pending",
            duration_ms=None,
        ),
        CheckResult(
            name="CloudWatch",
            passed=False,
            message="3 error events in last 5 min",
            duration_ms=None,
        ),
    ]
    print_report(
        target_url="http://devops-api-alb-xxxx.eu-north-1.elb.amazonaws.com",
        region="eu-north-1",
        cluster="devops-api-prod",
        service="devops-api-prod-api",
        results=all_pass,
    )
    print()
    print_report(
        target_url="http://devops-api-alb-xxxx.eu-north-1.elb.amazonaws.com",
        region="eu-north-1",
        cluster="devops-api-prod",
        service="devops-api-prod-api",
        results=partial_fail,
    )


if __name__ == "__main__":
    raise SystemExit(main())
