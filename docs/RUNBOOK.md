# Operations runbook

Portfolio sample: small HTTP API and background worker on **AWS** (ECS Fargate, ALB, RDS PostgreSQL), **Terraform** for infrastructure, **GitHub Actions** for CI/CD via **OIDC** (no long-lived AWS keys in GitHub). For architecture diagrams and repo layout, see the root [README](../README.md).

---

## Scope

This document covers **how to verify the stack**, **what alerts mean**, **where to look**, and **how changes roll out**. It does not define a production on-call roster or external escalation - wire those to your own SNS subscriptions and processes.

---

## Components

| Piece | Role |
|--------|------|
| **ALB** | Public HTTP **:80** (and **HTTPS :443** when `alb_certificate_arn` is set in Terraform) → API target group only |
| **ECS Fargate** | API service (behind ALB) + private **worker** service |
| **RDS PostgreSQL** | Private DB; tasks read **`DATABASE_URL`** from **Secrets Manager** |
| **CloudWatch** | ECS task logs (**JSON** from the app and worker), platform metrics, **alarms** |
| **Metrics (API)** | Prometheus text at **`GET /metrics`** (request total, latency histogram, in-flight gauge) |
| **SNS** | Alarm destination (`ops_alerts_sns_topic_arn` from Terraform) |
| **Terraform** | `infra/` with per-env state under `infra/envs/<env>/` |

---

## Preconditions (operator)

- **AWS access** consistent with the same account/region as Terraform.
- **GitHub**: repository **variables** and **secrets** as described in the root README (e.g. `AWS_ROLE_TO_ASSUME`, `TF_INFRA_ENVIRONMENT`, `TF_AWS_REGION`, `DOCKERHUB_*`, optional `TF_DATABASE_URL_SECRET_ARN`).
- After apply: note **`alb_dns_name`** and, for alerting, **`ops_alerts_sns_topic_arn`**.
- **SNS**: Terraform creates the topic and alarm actions but **does not create subscriptions**. Subscribe the topic (email, chat webhook, mobile push, etc.) and confirm receivers; otherwise alarms fire into an empty audience.

Optional: **`AWS_INCIDENT_LOGS_READER_ROLE_ARN`** matches the **`github_actions_incident_logs_reader_role_arn`** output for the same environment when using the incident log workflow.

---

## Health checks

1. **HTTP** (replace host with Terraform output **`alb_dns_name`**):
   - `GET /` → **200**
   - `GET /health` → **200** and JSON `{"status":"ok"}`
   - With **`alb_certificate_arn`** set in Terraform, the same paths work over **HTTPS** (**port 443**); **HTTP** redirects to HTTPS.
2. **`scripts/health_check.py`**: checks ALB endpoints, optionally ECS running vs desired and recent log lines that look like errors. See [`scripts/README.md`](../scripts/README.md) for flags (`--skip-aws`, env overrides for cluster/service/log group).

---

## Observability

### Structured logs → CloudWatch

The **API** and **worker** write **Pino JSON** to stdout. ECS forwards those lines to **CloudWatch Logs** (log group naming follows the ECS cluster and service from Terraform).

- Tune verbosity with **`LOG_LEVEL`** on the task (default **`info`**).
- Typical fields include **`level`**, **`time`**, **`msg`**, and on errors **`err`** (message and stack). Worker entries include **`service":"deployment-worker"`** so you can split API vs worker in **Logs Insights**.

Example **Logs Insights** query (substitute the API log group name from the ECS console or `health_check.py` docs):

```sql
fields @timestamp, level, msg, err.message
| filter level = 50 or msg = "unhandled error"
| sort @timestamp desc
| limit 50
```

### Prometheus metrics → `GET /metrics`

Only the **API** task exposes metrics; the worker has no HTTP listener. The process serves **Prometheus text exposition** on the **same port as the REST API** (container port **3000** on the target group), path **`/metrics`**.

**Quick check** (use Terraform output **`alb_dns_name`** as the host; switch to **`https://`** when **`alb_certificate_arn`** is set):

```bash
curl -sS "http://ALB_DNS/metrics" | head -n 40
```

Generate a little traffic (`GET /health`, `GET /deployments`, etc.), then run **`curl` again**. Counters and histogram buckets should move, for example:

- **`http_requests_total`** — labels **`method`**, **`route`**, **`status_code`**
- **`http_request_duration_seconds`** — end-to-end request latency
- **`http_requests_in_flight`** — concurrent requests (may show brief non‑zero values under load)

**Production scraping:** Use any Prometheus-compatible scraper against **`http(s)://<alb>/metrics`**, or add an internal collector later if you do not want application metrics on the public listener. Until you scrape, **AWS-native** visibility is still **ALB** and **ECS** metrics in CloudWatch; **`/metrics`** is extra **application RED-style** detail.

**Evidence for audits or tickets:** After load, keep a **screenshot** of either (1) terminal output from **`curl …/metrics`** showing those three metric families with non‑default values, or (2) a **Grafana Explore** / **Prometheus** panel where **`rate(http_requests_total[5m])`** or histogram quantiles react to requests. Store the image next to this runbook in your wiki or attach it to the incident.

### Traces (optional, Grafana Cloud / OTLP)

When Terraform sets **`otel_exporter_otlp_endpoint`** and **`otel_exporter_otlp_headers_secret_arn`**, the API ships **OpenTelemetry** traces to your OTLP gateway (e.g. Grafana Cloud). **`OTEL_EXPORTER_OTLP_HEADERS`** is read from **Secrets Manager** by the ECS **task execution** role; remaining OTLP-related variables are non-secret task env vars from Terraform (see [`infra/README.md`](../infra/README.md)).

**Sanity check:** In Grafana (**Explore** / Tempo or **Application Observability**), find the service name you set with **`OTEL_SERVICE_NAME`** (default **`devops-api`**) and confirm traces after requests through the ALB. If the stream is empty: validate the secret plaintext matches Grafana’s header line, **`GetSecretValue`** on the execution role covers that secret ARN, and **NAT** allows **HTTPS** from private subnets to the OTLP host.

---

## Alerting (CloudWatch → SNS)

Alarms exist when ECS and/or RDS are enabled (see `infra/cloudwatch_alarm_*.tf` for tunable thresholds).

| Alarm suffix | What it detects |
|----------------|-----------------|
| `alb-target-5xx` | ALB **HTTPCode_Target_5XX_Count** sum over **5 minutes** above threshold (sample: **> 5**). |
| `ecs-api-task-shortfall` | API service **running** task count below **desired** (**metric math**), **two** consecutive **1-minute** evaluations. |
| `rds-free-storage-low` | **FreeStorageSpace** average over **5 minutes** below **~2 GiB**. |
| `rds-cpu-high` | **CPUUtilization** average over **5 minutes** above **80%** for **two** consecutive periods. |

---

## Triage by alarm or symptom

| Signal | Check next |
|--------|-------------|
| **ALB 5xx** | Target group health; ECS **stopped tasks** and **service events**; API logs in CloudWatch; DB reachability / connection errors in logs |
| **ECS task shortfall** | Recent **deployments**, image pull errors, task definition / secrets IAM, CPU/memory limits, container exit reasons |
| **RDS storage** | Disk growth; increase allocated storage via Terraform/tfvars if needed |
| **RDS CPU** | Query load vs instance class (`db.t4g.micro` in sample); correlate with traffic and slow queries if you enable logging |
| **502/503 at ALB** | Unhealthy targets, zero running tasks, security group or listener misconfiguration |

**Logs:** ECS services log to CloudWatch (log group pattern documented with `health_check.py` / workflows). For a bounded window export suitable for notes or issues, use **`scripts/incident_log_report.py`** or **`.github/workflows/incident-log-report.yml`**. See **[Observability](#observability)** for JSON log fields and **Logs Insights** examples.

**Traces (optional):** Configure Terraform OTLP variables and Grafana as described under **[Observability](#observability)**; if spans are missing, verify the OTLP **Secrets Manager** value, **IAM**, and **NAT egress**.

---

## Deployments

- **Typical path:** push to **`main`** → **CI** builds and pushes **`devops-api`**, **`devops-worker`**, and **`devops-migrate`** tags **`:<git-sha>`** → **Deploy** workflow runs **`terraform apply`** with those immutable pins (not `:latest`).
- **Infra / variables:** `terraform init -backend-config=envs/<env>/backend.hcl` then `plan` / `apply` with `envs/<env>/terraform.tfvars` from `infra/`. Match **`<env>`** to **`TF_INFRA_ENVIRONMENT`** in CI when comparing behavior.

**Rollback (application):** Re-deploy a **known-good commit** so CI produces images tagged with that SHA and the deploy job applies them, or temporarily pin **`TF_VAR_docker_image` / `TF_VAR_worker_image` / `TF_VAR_migrate_image`** to specific tags in your automation if you document that as an allowed break-glass step.

---

## Database migrations

- **ECS (default):** Each API and worker task runs a **`migrate`** init container first (`devops-migrate:<git-sha>` from CI). It uses the same **`DATABASE_URL`** secret as the main container and executes `scripts/run_migrations.py` (with a Postgres advisory lock so concurrent task starts do not race). Terraform toggles: **`ecs_run_db_migrations`** (default `true`) and **`migrate_image`** (defaults from `docker_image` by swapping `devops-api` → `devops-migrate`).
- **Docker Compose:** **`docker/`** runs a one-off **migrate** service before API and worker. See [`docker/README.md`](../docker/README.md).
- **Script:** Migrations live in **`migrations/`** and are applied by **`scripts/run_migrations.py`** (see [`scripts/README.md`](../scripts/README.md)).

If you disable ECS init migrations (`ecs_run_db_migrations = false`), run the script yourself (e.g. bastion or pipeline) with **`DATABASE_URL`** from Secrets Manager.

---

## Drift and teardown

- **Drift:** [`scripts/terraform_drift_report.py`](../scripts/terraform_drift_report.py) and **`.github/workflows/terraform-drift-report.yml`** (exit code **2** means drift). See [`infra/README.md`](../infra/README.md).
- **Destroy:** **`.github/workflows/terraform-destroy.yml`**—treat as destructive; read `infra/README.md` bootstrap and state bucket notes first.

---

## Local reproduction

**Docker Compose** under **`docker/`** runs Postgres, migrate, API (**`:3000`**), and worker on one network—useful to validate behavior without AWS. See [`docker/README.md`](../docker/README.md).

---

## Reference outputs (Terraform)

Common outputs after apply (exact names in **`infra/outputs.tf`**): **`alb_dns_name`**, **`rds_endpoint`**, **`database_url_secret_arn`**, **`ops_alerts_sns_topic_arn`**, **`github_actions_incident_logs_reader_role_arn`**, **`vpc_id`**, subnet IDs.
