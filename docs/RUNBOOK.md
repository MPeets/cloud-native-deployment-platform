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
| **CloudWatch** | ECS task logs, metrics, **alarms** |
| **SNS** | Alarm destination (`ops_alerts_sns_topic_arn` from Terraform) |
| **Terraform** | `infra/` with per-env state under `infra/envs/<env>/` |

Optional: **EC2 + Docker** (`enable_ec2`) and **Kubernetes** packaging (`k8s/helm/devops-api`, API only—Postgres and **`DATABASE_URL`** via chart **`databaseUrl`** or your own Secret; see [`k8s/README.md`](../k8s/README.md)) are not part of the default AWS topology.

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

**Logs:** ECS services log to CloudWatch (log group pattern documented with `health_check.py` / workflows). For a bounded window export suitable for notes or issues, use **`scripts/incident_log_report.py`** or **`.github/workflows/incident-log-report.yml`**.

---

## Deployments

- **Typical path:** push to **`main`** → **CI** builds and pushes **`devops-api:<git-sha>`** and **`devops-worker:<git-sha>`** → **Deploy** workflow runs **`terraform apply`** with those immutable tags (not `:latest`).
- **Infra / variables:** `terraform init -backend-config=envs/<env>/backend.hcl` then `plan` / `apply` with `envs/<env>/terraform.tfvars` from `infra/`. Match **`<env>`** to **`TF_INFRA_ENVIRONMENT`** in CI when comparing behavior.

**Rollback (application):** Re-deploy a **known-good commit** so CI produces images tagged with that SHA and the deploy job applies them, or temporarily pin **`TF_VAR_docker_image` / `TF_VAR_worker_image`** to specific tags in your automation if you document that as an allowed break-glass step.

---

## Database migrations

Migrations live in **`migrations/`** and are applied by **`scripts/run_migrations.py`** (see [`scripts/README.md`](../scripts/README.md)). **Docker Compose** runs a one-off **migrate** service before API and worker.

For AWS, decide explicitly how you run migrations in your own process (e.g. one-off Fargate task, pipeline step with `DATABASE_URL`, or manual)—this repo demonstrates the script and local/CI usage; it does not enforce a single production hook.

---

## Drift and teardown

- **Drift:** [`scripts/terraform_drift_report.py`](../scripts/terraform_drift_report.py) and **`.github/workflows/terraform-drift-report.yml`** (exit code **2** means drift). See [`infra/README.md`](../infra/README.md).
- **Destroy:** **`.github/workflows/terraform-destroy.yml`**—treat as destructive; read `infra/README.md` bootstrap and state bucket notes first.

---

## Local reproduction

**Docker Compose** under **`docker/`** runs Postgres, migrate, API (**`:3000`**), and worker on one network—useful to validate behavior without AWS. See [`docker/README.md`](../docker/README.md).

**Kubernetes (optional):** The Helm chart deploys the API workload only. Run Postgres in-cluster or elsewhere, then pass **`databaseUrl.url`** (chart creates a Secret and **`envFrom`**) or **`databaseUrl.existingSecret`**. Details: [`k8s/README.md`](../k8s/README.md).

---

## Reference outputs (Terraform)

Common outputs after apply (exact names in **`infra/outputs.tf`**): **`alb_dns_name`**, **`rds_endpoint`**, **`database_url_secret_arn`**, **`ops_alerts_sns_topic_arn`**, **`github_actions_incident_logs_reader_role_arn`**, **`vpc_id`**, subnet IDs.
