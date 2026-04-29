"""Deployment health checks against ALB, ECS, and CloudWatch."""

from __future__ import annotations

import json
import sys
import time
from dataclasses import dataclass
from typing import Optional

import requests


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
        cluster="devops-api",
        service="devops-api",
        results=all_pass,
    )
    print()
    print_report(
        target_url="http://devops-api-alb-xxxx.eu-north-1.elb.amazonaws.com",
        region="eu-north-1",
        cluster="devops-api",
        service="devops-api",
        results=partial_fail,
    )


if __name__ == "__main__":
    _demo_report()
