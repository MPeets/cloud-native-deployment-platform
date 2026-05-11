# Scripts (`scripts/`)

Small Python 3 utilities used by CI, local Docker Compose, and operators. They share dependencies declared in [`requirements.txt`](./requirements.txt): `boto3`, `requests`, `psycopg2-binary`, `python-dateutil`, and the pinned versions there.

Install once when running them locally:

```bash
pip install -r scripts/requirements.txt
```

The workflow [`.github/workflows/scripts-lint.yml`](../.github/workflows/scripts-lint.yml) runs unit tests for `test_*.py`, runs Pylint on this directory, and exercises `run_migrations.py` against a CI database service.

Run the script unit tests locally from the repo root:

```bash
python -m unittest discover -s scripts -p "test_*.py"
```

---

## `terraform_drift_report.py`

What it does: runs `terraform plan -detailed-exitcode -json` in a chosen directory, defaulting to `infra`, or reads plan JSON from a file or stdin. It parses Terraform's output, ignores no-op/read noise, and prints a short list of managed resources that would create, update, replace, or delete. Optional `-o` writes that report to a file.

Why it matters: drift means live cloud state no longer matches what Terraform expects. That can come from manual changes, partial applies, or outdated state. Catching it early avoids surprises and guides a corrective `plan` or `apply`. Exit codes are meant for automation: `0` for no drift, `1` for an error, and `2` for drift detected. They are used by [`.github/workflows/terraform-drift-report.yml`](../.github/workflows/terraform-drift-report.yml) and documented in [`infra/README.md`](../infra/README.md).

---

## `run_migrations.py`

What it does: connects to PostgreSQL using `DATABASE_URL`, or a sensible local default, ensures a `schema_migrations` bookkeeping table exists, then applies every file in the migrations directory matching `NN_description.sql` in numeric order. Versions already recorded are skipped. Each migration runs in a transaction; failures roll back and the script exits non-zero.

Why it matters: application schema must stay in sync with the running API and worker. Ordered, tracked migrations give repeatable database setup in dev, CI, and Compose. [`docker/docker-compose.yml`](../docker/docker-compose.yml) mounts this script and the [`../migrations/`](../migrations/) folder so the `migrate` service finishes before `api` and `worker` start. CI runs the same script to verify migration behavior.

---

## `health_check.py`

What it does: after a deploy, or anytime, checks that the stack looks healthy:

1. ALB liveness: HTTP `GET /` expects `200`, with retries/backoff.
2. ALB health: `GET /health` expects `200` and JSON `{"status":"ok"}`.
3. ECS service, unless `--skip-aws` or `SKIP_AWS` is set: `describe_services` confirms running task count matches desired count, with notes on pending tasks or active deployments. When that check fails it also surfaces recent service events, deployment rollout state, and stopped-task reasons such as `CannotPullContainerError` or exit codes.
4. CloudWatch, behind the same AWS gate: `filter_log_events` scans a recent window and counts messages that look like errors: `ERROR`, `error`, `Exception`, or `FATAL`.

Prints a compact pass/fail report. It exits `0` only if every enabled check passes. `--demo` prints sample output without calling AWS or HTTP.

Why it matters: post-deploy smoke tests reduce "Terraform succeeded but users see 502" incidents. [`.github/workflows/terraform-apply.yml`](../.github/workflows/terraform-apply.yml) sets `ALB_DNS`, passes `TF_INFRA_ENVIRONMENT`, and uses AWS credentials after apply. ECS and logging defaults derive the `devops-api-<env>` cluster, `<prefix>-api` service, and `/ecs/<prefix>` log group, using `dev` when unset, to match `infra/envs/*/terraform.tfvars`. Override `ECS_CLUSTER`, `ECS_SERVICE`, `LOG_GROUP`, or `TF_STACK_PREFIX_BASE` when needed. [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs a subset with `--alb-dns localhost:3000 --skip-aws`.

---

## `incident_log_report.py`

What it does: for post-incident or on-demand review, pulls CloudWatch Logs from a group over a time window. Use `--since 30m`-style durations, or `--from` / `--to` ISO timestamps. It paginates `filter_log_events`, optionally caps volume with `--max-events`, classifies each line heuristically as `ERROR`, `WARN`, `INFO`, or `UNKNOWN`, and emits JSON or Markdown to stdout or `-o`. `--dry-run` only validates the window and prints epoch milliseconds, with no AWS calls.

Why it matters: `health_check.py` answers "is it healthy right now?" This script answers "what did the service log in the last N minutes?" in a form you can paste into tickets, runbooks, or PRs. [`.github/workflows/incident-log-report.yml`](../.github/workflows/incident-log-report.yml) assumes OIDC into the least-privilege `logs:FilterLogEvents` role from Terraform ([`infra/README.md`](../infra/README.md)) and uploads the Markdown report as a job summary and artifact.
