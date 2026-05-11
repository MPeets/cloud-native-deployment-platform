# Terraform Infrastructure

This folder contains two Terraform roots plus shared child modules:

- `bootstrap/`: creates the S3 bucket used by Terraform remote state. This root uses local state and is only needed when the backend bucket does not exist yet.
- `./`: main root configures the S3 backend in `backend.tf` (with S3-native state locking via `use_lockfile`). Environment-specific backend and variable inputs live under `envs/`.

Child modules invoked from the main root ([`modules/`](./modules/)):

- `network`: VPC, subnets, NAT, route tables
- `alb`: public ALB, target group, and ALB security group. It uses HTTP `:80` when `alb_certificate_arn` is unset, which is the demo default. When `alb_certificate_arn` is set, it adds HTTPS `:443` and redirects HTTP to HTTPS on 80.
- `ecs_cluster`: ECS tasks and VPC-endpoint security groups, interface VPC endpoints (`ecr.api`, `ecr.dkr`, `logs`), S3 gateway endpoint, ECS cluster, CloudWatch log group, and task execution role. The root attaches a `GetSecretValue` policy on the execution role for database and optional OTLP header secrets (see `ecs.tf`).
- `rds`: PostgreSQL RDS, with a `DATABASE_URL` secret when managed in-cluster.
- `ecs_service`: Fargate task definition and ECS service. The API uses `load_balancer`; the worker skips it.

Keeping backend bootstrap resources out of the main root avoids Terraform trying to manage the same bucket from the state stored in that bucket.

## Current status (what this stack does today)

> Warning: this demo runs HTTP-only by default to avoid ACM and Route53 setup. Set `alb_certificate_arn` to enable TLS.

- Primary runtime: ECS on Fargate is the default (`enable_ecs = true`). API and worker tasks run in private subnets without public IPs by default (`ecs_assign_public_ip = false`). Traffic enters through an Application Load Balancer in public subnets, HTTP port 80 unless you set `alb_certificate_arn` for HTTPS and redirect, and only targets the API service.
- Database: PostgreSQL RDS is enabled by default (`enable_rds = true`) using the small `db.t4g.micro` instance class, private subnets, encrypted storage, and a generated `DATABASE_URL` secret for ECS.
- Networking: a dedicated VPC with two public and two private subnets, defaults in `variables.tf`, one NAT gateway, and interface/gateway VPC endpoints for ECR, CloudWatch Logs, and S3 when ECS is enabled.
- Remote state: the main root uses the S3 backend defined in [`backend.tf`](./backend.tf), with environment-specific backend keys in `envs/dev/backend.hcl` and `envs/prod/backend.hcl`. If you fork the repo or use another AWS account, align `bootstrap/variables.tf`, or your bootstrap inputs, `backend.tf`, the files under `envs/`, and any CI variables with your bucket and region.
- GitHub Actions and AWS: besides the usual deploy role documented at the repo root, Terraform can create a least-privilege OIDC IAM role that only allows CloudWatch Logs filter calls against the ECS service log group. That supports the Incident log report workflow (`.github/workflows/incident-log-report.yml`). It is on by default (`enable_github_incident_logs_reader_role = true`) when ECS is enabled. The role name includes `environment`; each Terraform environment gets its own ARN, so `AWS_INCIDENT_LOGS_READER_ROLE_ARN` should match whichever env runs the workflow. You can also duplicate the workflow with distinct variables. After apply, set `AWS_INCIDENT_LOGS_READER_ROLE_ARN` to the Terraform output `github_actions_incident_logs_reader_role_arn`. If you use a different GitHub repo, set `github_actions_oidc_repository` in `terraform.tfvars`; see below.
- Operational alerting: with ECS or RDS enabled, Terraform creates an SNS topic and CloudWatch alarms for ALB target 5xx, ECS API task count vs desired, and RDS free storage/CPU. Details and the `ops_alerts_sns_topic_arn` output are in [Operational alerting](#operational-alerting-cloudwatch--sns) below.
- Automation elsewhere in the repo: Terraform plan/apply/destroy and drift reporting run from GitHub Actions. Drift uses [`scripts/terraform_drift_report.py`](../scripts/terraform_drift_report.py) against this directory. Set the repo variable `TF_INFRA_ENVIRONMENT` to `dev` or `prod` so workflows match `envs/<name>/`; when unset in CI scripts, `dev` is used (`${TF_INFRA_ENVIRONMENT:-dev}`).

## Local config (`terraform.tfvars`)

This repo includes `terraform.tfvars.example` as a template. Create your local `terraform.tfvars` from it. Do not commit that file; it may hold account-specific overrides you prefer not to track.

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and set:

- `enable_ecs = true` for the ECS/Fargate runtime. This is already the default in `variables.tf`.
- `enable_rds = true` to create the private PostgreSQL database; set `false` only when using an external database
- `database_url_secret_arn` only when bringing your own database secret instead of the managed RDS database
- `rds_instance_class`, `rds_allocated_storage`, `rds_backup_retention_days`, and `rds_deletion_protection` if the sample defaults need to change
- `ecs_assign_public_ip = false` so ECS tasks run without public IPs in private subnets
- `vpc_cidr`, `public_subnet_cidrs`, and `private_subnet_cidrs` if the default network ranges overlap with an existing environment
- `enable_github_incident_logs_reader_role`: leave `true` to create the read-only CloudWatch role for incident reports; set `false` if you do not want that role
- `github_actions_oidc_repository`: defaults to this template's repo slug; change it when you fork so OIDC `sub` claims match your `owner/name` on GitHub
- `alb_certificate_arn`: optional. When set, the ALB adds TLS on 443 and redirects HTTP to HTTPS. The ARN must be a validated ACM certificate in the ALB's AWS region. Issuing one is typically `aws_acm_certificate` plus DNS validation, often Route 53. Leave unset for HTTP-only.
- **OpenTelemetry (Grafana Cloud):** optional. Set `otel_exporter_otlp_endpoint` (e.g. `https://otlp-gateway-prod-eu-north-0.grafana.net/otlp`) and `otel_exporter_otlp_headers_secret_arn` to the ARN of a Secrets Manager secret whose **plaintext** is exactly the `OTEL_EXPORTER_OTLP_HEADERS` value Grafana gives you (`Authorization=Basic%20...`). The API ECS task then gets non-secret OTLP env vars from Terraform and the header from Secrets Manager. Optional: `otel_exporter_otlp_protocol`, `otel_service_name`, `otel_resource_attributes`. The worker task is unchanged. Outbound HTTPS uses the NAT gateway (private tasks).

Image pins are intentionally not stored in tracked `tfvars` files. For local plans/applies, export immutable image refs in the shell:

```bash
export TF_VAR_docker_image="YOUR_DOCKERHUB_USER/devops-api:<git-sha>"
export TF_VAR_worker_image="YOUR_DOCKERHUB_USER/devops-worker:<git-sha>"
```

Required values without usable defaults:

- `docker_image`: API container image the ECS API task runs
- `worker_image`: worker container image the ECS worker task runs; when omitted, Terraform derives the matching `devops-worker` tag from `docker_image`

## GitHub Actions deploy image selection

The Terraform workflows resolve ECS image pins at run time and pass them as `TF_VAR_docker_image` and `TF_VAR_worker_image`. The default is still the latest successful `CI - Build & Push Docker Images` run on `main`, which keeps the normal mainline deploy path hands-off.

For rollback or preview work, run `.github/workflows/ci.yml` for the commit you want to deploy, then copy the full commit SHA from the workflow summary. The Docker tags are immutable and use that SHA:

```bash
DOCKERHUB_USERNAME/devops-api:<git-sha>
DOCKERHUB_USERNAME/devops-worker:<git-sha>
```

Manual Terraform runs accept:

- `image_sha`: optional full 40-character commit SHA for the Docker image tags; leave blank to use the latest successful Docker CI run on `main`
- `infra_environment`: optional `envs/<name>` directory to plan/apply; leave blank to use the `TF_INFRA_ENVIRONMENT` repository variable or `dev`

Rollback production by running `Terraform Apply` on `main`, setting `confirm_apply` to `apply`, `infra_environment` to `prod`, and `image_sha` to the last known good commit SHA. Preview a feature branch by first running or waiting for Docker CI on that branch, then running `Terraform Plan` or `Terraform Apply` with the branch commit SHA and the target non-production environment.

Manual `Terraform Plan` runs do not chain into automatic apply. Automatic apply remains limited to successful push-triggered plans on `main`.

## Terraform workflow boundaries

Terraform uses three GitHub Actions workflows instead of one parameterized workflow:

- `Terraform Plan`: runs for pull requests, infrastructure pushes to `main`, and manual checks. It validates, tests, scans, and renders a plan without mutating infrastructure.
- `Terraform Apply`: runs only from `main`, either after a successful push-triggered plan or through a manual dispatch that requires `confirm_apply = apply`. The job uses the GitHub Actions environment named `production`, so GitHub environment protection rules can pause the deployment before credentials are used.
- `Terraform Destroy`: is manual-only, requires `confirm_destroy = destroy`, and also uses the GitHub Actions environment named `production`. Keeping teardown separate makes the destructive path visible and harder to confuse with routine apply.

The GitHub Actions environment name is not the same thing as the Terraform environment. `production` is the GitHub approval/protection wrapper on the job. The actual Terraform target comes from `infra_environment`, then `TF_INFRA_ENVIRONMENT`, and finally defaults to `dev`; that value selects files under `infra/envs/<name>/`, such as `envs/dev` or `envs/prod`.

This repo intentionally does not use Terraform Cloud or Atlantis. Both are valid choices when a team wants remote runs, policy checks, richer approvals, or PR-comment driven workflows, but they add another service and onboarding path that would distract from the GitHub Actions and AWS OIDC baseline. A single workflow with `workflow_dispatch` inputs would reduce duplication, but it would combine planning, mutation, and destruction behind the same action entry point. Separate workflows make permissions, approvals, audit trails, and operator intent easier to explain.

## First-Time Bootstrap (No Existing Backend Bucket)

1. Create the remote state bucket from the bootstrap root:

```bash
cd bootstrap
terraform init
terraform apply
```

2. Go up to `infra/` and initialize one environment, such as `dev` or `prod`, using that env's backend partial config plus tfvars under [`envs/`](./envs/).

```bash
cd ..
ENV_NAME=dev # or prod
terraform init -backend-config=envs/${ENV_NAME}/backend.hcl -reconfigure
terraform plan -var-file=envs/${ENV_NAME}/terraform.tfvars
terraform apply -var-file=envs/${ENV_NAME}/terraform.tfvars
```

If you previously used local state and are moving onto the remote backend, migrate into that env key explicitly:

```bash
ENV_NAME=dev # env that should own your existing resources
terraform init \
  -backend-config=envs/${ENV_NAME}/backend.hcl \
  -migrate-state
```

Then continue with normal `terraform plan -var-file=...` / `apply` runs for `ENV_NAME`.

3. Sanity-check remote connectivity:

```bash
terraform state list
```

Isolation is primarily distinct state keys; see [`envs/`](./envs/). Workspaces are unchanged from Terraform's defaults.

## Normal Workflow (After Backend Bootstrap)

Once the backend is bootstrapped, initialize the environment you want to work on from the main `infra` root:

```bash
terraform init -backend-config=envs/dev/backend.hcl -reconfigure
terraform plan -var-file=envs/dev/terraform.tfvars
terraform apply -var-file=envs/dev/terraform.tfvars
```

Use the matching files under `envs/prod/` for production. Each environment keeps its own remote state key and variable values while reusing the same Terraform root.

## Drift Reporting

The repository includes a small drift reporter that runs Terraform from the repo root, parses `terraform plan -detailed-exitcode -json`, and prints a human-readable summary of managed resources that differ from the desired state.

Run `terraform init -backend-config=envs/<env>/backend.hcl -reconfigure` from `infra` first. To match CI, pass the same tfvars as extra plan arguments from the repo root shell, for example:

```bash
export TF_CLI_ARGS_plan=-var-file=envs/dev/terraform.tfvars # or envs/prod/terraform.tfvars
python scripts/terraform_drift_report.py --terraform-dir infra
```

Exit codes are designed for CI:

- `0`: no drift detected
- `1`: script, Terraform, or JSON parsing error
- `2`: drift detected

For deterministic local checks, you can also pipe Terraform JSON into the parser without running Terraform:

```bash
cd infra
terraform plan -detailed-exitcode -json -var-file=envs/dev/terraform.tfvars \
  | python ../scripts/terraform_drift_report.py --plan-json -
```

GitHub Actions also runs this on a weekday schedule in `.github/workflows/terraform-drift-report.yml`; the workflow writes the report to the job summary and uploads it as an artifact.

## ECS Fargate (cloud-native runtime)

This stack contains an ECS Fargate baseline running two services: the public API service from `docker_image` and a private background worker service from `worker_image`.

ECS resources are enabled when `enable_ecs = true` (the default in `variables.tf`).

This stage fronts ECS tasks with an Application Load Balancer:

- Public traffic enters via ALB, using HTTP port 80 or HTTPS 443 plus 80-to-HTTPS redirect when `alb_certificate_arn` is set, and routes only to the API service.
- The ALB runs in the custom public subnets.
- API and worker ECS tasks run in the custom private subnets without public IPs.
- API and worker tasks receive `DATABASE_URL` from Secrets Manager. By default Terraform creates this secret from the managed RDS endpoint; `database_url_secret_arn` overrides it for external databases.
- PostgreSQL RDS runs in the private subnets and only accepts port 5432 from the ECS task security group.
- Private ECS tasks use VPC endpoints for ECR, S3, and CloudWatch Logs traffic.
- NAT egress remains available for other outbound internet access.
- Task security group allows app traffic only from the ALB security group; the worker has no load balancer attachment.
- Service endpoint is available in Terraform output `alb_dns_name`.
- ALB health-check path is configurable via `alb_health_check_path` (default `/`).
- ECS deployment health tuning uses `deployment_minimum_healthy_percent = 100`, `deployment_maximum_percent = 200`, and `ecs_health_check_grace_period_seconds` (default `60`).
- Worker service capacity is configurable via `ecs_worker_desired_count` (default `1`).
- ECS task size is configurable via `ecs_task_cpu` (default `256`) and `ecs_task_memory` (default `512`).
- ECS log retention is configurable via `ecs_log_retention_days` (default `7`).
- RDS defaults favor the smallest demo footprint: `db.t4g.micro`, 20 GiB encrypted storage, no automated backup retention, and deletion protection off.

## Operational alerting (CloudWatch + SNS)

When `enable_ecs` or `enable_rds` is true, Terraform provisions an SNS topic (`${name_prefix}-ops-alerts`) for operational notifications. After apply, use the Terraform output `ops_alerts_sns_topic_arn` when wiring subscriptions or chat integrations. No subscriptions are created by default; email, Slack, and similar targets need a one-time confirmation in AWS or an extra Terraform resource.

CloudWatch alarms publish to that topic when the related resources exist. ALB/ECS alarms require `enable_ecs = true`; RDS alarms require `enable_rds = true`.

| Alarm (resource name suffix) | What it detects |
|-------------------------------|-----------------|
| `alb-target-5xx` | Application Load Balancer `HTTPCode_Target_5XX_Count` sum over 5 minutes above a small threshold. |
| `ecs-api-task-shortfall` | ECS API service running task count below desired, using metric math, for two consecutive 1-minute evaluations. |
| `rds-free-storage-low` | RDS `FreeStorageSpace` average over 5 minutes below 2 GiB. |
| `rds-cpu-high` | RDS `CPUUtilization` average over 5 minutes above 80% for two consecutive periods. |

Tune thresholds and evaluation windows in the Terraform files `cloudwatch_alarm_*.tf` if your environment needs quieter or tighter alerting.

## Network baseline

This stack now creates a small custom network foundation:

- VPC with DNS support enabled.
- Two public subnets across available Availability Zones.
- Two private subnets across available Availability Zones.
- Internet gateway and public route table for the public subnet tier.
- Single NAT gateway and private route table for private subnet outbound access.
- VPC endpoints for ECR API, ECR Docker, CloudWatch Logs, and S3.

ECS tasks use the private subnets behind the public ALB. For higher availability, a future iteration can add one NAT gateway per Availability Zone.

## Notable Terraform outputs

After a successful apply (with ECS enabled), these are the outputs people and automation most often need:

| Output | Meaning |
|--------|---------|
| `alb_dns_name` | Public DNS name of the load balancer. HTTP `:80` is the default entry point; HTTPS `:443` is used when `alb_certificate_arn` is set. |
| `rds_endpoint`, `database_url_secret_arn` | Managed PostgreSQL endpoint and the Secrets Manager ARN injected into ECS tasks. |
| `github_actions_incident_logs_reader_role_arn` | ARN to paste into GitHub as `AWS_INCIDENT_LOGS_READER_ROLE_ARN` when the incident-logs role is created. |
| `ops_alerts_sns_topic_arn` | SNS topic for operational alarms (subscribe for email/chat/PagerDuty); null when both ECS and RDS are disabled. |
| `vpc_id`, `public_subnet_ids`, `private_subnet_ids` | Network identifiers for extensions or troubleshooting. |
| `nat_gateway_id`, `vpc_endpoint_ids` | NAT and VPC endpoint resources when ECS is on. |

## Notes

- Run these commands from the `infra` directory.
- Run bootstrap commands from `infra/bootstrap`.
- `envs/<env>/terraform.tfvars` files in Git are template defaults only: VPC layout and booleans. Keep secrets and personal data out of tracked files where possible. Prefer GitHub `TF_*` / `TF_VAR_*` for anything sensitive so CI overrides values without committing them; only `/terraform.tfvars`, copied beside `backend.tf`, is gitignored locally.
- If the bootstrap `state_bucket_name` changes, update the bucket name in `backend.tf` to match.
- The managed RDS password and generated `DATABASE_URL` secret value are represented in Terraform state; keep the S3 backend private, encrypted, and access-controlled.
