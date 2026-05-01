# Scripts (`scripts/`)

Small **Python 3** utilities used by **CI**, **local Docker Compose**, and operators. They share dependencies declared in [`requirements.txt`](./requirements.txt) (`boto3`, `requests`, `psycopg2-binary`, `python-dateutil`, and versions pinned there).

Install once when running them locally:

```bash
pip install -r scripts/requirements.txt
```

The workflow [`.github/workflows/scripts-lint.yml`](../.github/workflows/scripts-lint.yml) runs **Pylint** on this directory and exercises **`run_migrations.py`** against a CI database service.

---

## `terraform_drift_report.py`

**What it does:** Runs **`terraform plan -detailed-exitcode -json`** in a chosen directory (default `infra`), or reads plan JSON from a file or stdin. It parses Terraform’s output, ignores no-op/read noise, and prints a **short human-readable list** of managed resources that would create, update, replace, or delete. Optional **`-o`** writes that report to a file.

**Why it matters:** “Drift” means **live cloud state no longer matches what Terraform expects** (manual changes, partial applies, or outdated state). Catching that early avoids surprises and guides corrective **`plan` / `apply`**. Exit codes are meant for automation: **`0`** no drift, **`1`** error, **`2`** drift detected—used by [`.github/workflows/terraform-drift-report.yml`](../.github/workflows/terraform-drift-report.yml) and documented in [`infra/README.md`](../infra/README.md).

---

## `run_migrations.py`

**What it does:** Connects to **PostgreSQL** using **`DATABASE_URL`** (or a sensible local default), ensures a **`schema_migrations`** bookkeeping table exists, then applies every file in the migrations directory matching **`NN_description.sql`** in numeric order—**skipping** versions already recorded. Each migration runs in a **transaction**; failures roll back and the script exits non-zero.

**Why it matters:** Application schema must stay in sync with the running API and worker. Ordered, tracked migrations give **repeatable** database setup in **dev**, **CI**, and **Compose**. [ **`docker/docker-compose.yml`**](../docker/docker-compose.yml) mounts this script and the [`../migrations/`](../migrations/) folder so the **`migrate`** service finishes **before** **`api`** and **`worker`** start; CI runs the same script to verify migration behavior.

---

## `health_check.py`

**What it does:** After a deploy (or anytime), checks that the stack looks healthy:

1. **ALB liveness** — HTTP **GET /** expects **200** (with retries/backoff).
2. **ALB health** — **GET /health** expects **200** and JSON **`{"status":"ok"}`**.
3. **ECS service** (unless **`--skip-aws`** or **`SKIP_AWS`**) — **`describe_services`** to confirm **running** task count matches **desired** count, with notes on pending tasks or active deployments.
4. **CloudWatch** (same AWS gate)— **`filter_log_events`** over a recent window and counts messages that look like errors (**ERROR**, **error**, **Exception**, **FATAL**).

Prints a compact **pass/fail** report; exits **`0`** only if every enabled check passes. **`--demo`** prints sample output without calling AWS or HTTP.

**Why it matters:** Post-deploy smoke tests reduce **“Terraform succeeded but users see 502”** incidents. [`.github/workflows/terraform-apply.yml`](../.github/workflows/terraform-apply.yml) uses it with **`ALB_DNS`** (and AWS credentials) after apply; [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs a **subset** (`--alb-dns localhost:3000 --skip-aws`) to validate the script path without needing ECS. Operators can run the same CLI locally with **`--alb-dns`**, **`--region`**, **`--cluster`**, **`--service`**, and **`--log-group`**.

---

## `incident_log_report.py`

**What it does:** For **post-incident** or **on-demand** review, pulls **CloudWatch Logs** from a group over a time window (**`--since 30m`**-style durations, or **`--from` / `--to`** ISO timestamps). Paginates **`filter_log_events`**, optionally caps volume with **`--max-events`**, classifies each line heuristically as **ERROR / WARN / INFO / UNKNOWN**, and emits a structured report as **JSON** or **Markdown** (stdout or **`-o`**). **`--dry-run`** only validates the window and prints epoch ms (no AWS calls).

**Why it matters:** **`health_check.py`** answers “is it healthy *right now*?”; this script answers **“what did the service log in the last N minutes?”** in a form you can paste into tickets, runbooks, or PRs. [`.github/workflows/incident-log-report.yml`](../.github/workflows/incident-log-report.yml) assumes **OIDC** into the least-privilege **`logs:FilterLogEvents`** role from Terraform ([`infra/README.md`](../infra/README.md)) and uploads the Markdown report as a job summary and artifact.
