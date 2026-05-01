# Terraform Infrastructure

This folder contains two Terraform roots:

- `bootstrap/`: creates the S3 bucket used by Terraform remote state. This root uses local state and is only needed when the backend bucket does not exist yet.
- `./`: deploys the application infrastructure and configures Terraform to use the S3 backend in `backend.tf` (with S3-native state locking via `use_lockfile`).

Keeping backend bootstrap resources out of the main root avoids Terraform trying to manage the same bucket from the state stored in that bucket.

## Current status (what this stack does today)

- **Primary runtime:** **ECS on Fargate** is the default (`enable_ecs = true`). API and worker tasks run in **private subnets** without public IPs by default (`ecs_assign_public_ip = false`). Traffic enters through an **Application Load Balancer** in public subnets (HTTP port 80) and only targets the API service.
- **Legacy runtime:** **EC2 + Docker + systemd** is opt-in only (`enable_ec2 = false` by default) for debugging; it is not the main deployment path.
- **Networking:** A dedicated **VPC** with two public and two **private** subnets (defaults in `variables.tf`), one **NAT gateway**, and **interface/gateway VPC endpoints** for ECR, CloudWatch Logs, and S3 when ECS is enabled.
- **Remote state:** The main root uses the **S3 backend** defined in [`backend.tf`](./backend.tf) (bucket name, state key, region, encryption, and locking). If you fork the repo or use another AWS account, align `bootstrap/variables.tf` (or your bootstrap inputs), `backend.tf`, and any CI variables with **your** bucket and region.
- **GitHub Actions + AWS:** Besides the usual deploy role (documented at the repo root), Terraform can create a **least-privilege OIDC IAM role** that only allows **CloudWatch Logs filter** calls against the **ECS service log group**. That supports the **Incident log report** workflow (`.github/workflows/incident-log-report.yml`). It is on by default (`enable_github_incident_logs_reader_role = true`) when ECS is enabled. After apply, set the repository variable **`AWS_INCIDENT_LOGS_READER_ROLE_ARN`** to the Terraform output **`github_actions_incident_logs_reader_role_arn`**. If you use a different GitHub repo, set **`github_actions_oidc_repository`** in `terraform.tfvars` (see below).
- **Automation elsewhere in the repo:** **Terraform plan/apply/destroy** and **drift reporting** run from GitHub Actions; drift uses [`scripts/terraform_drift_report.py`](../scripts/terraform_drift_report.py) against this directory.

## Local config (`terraform.tfvars`)

This repo includes `terraform.tfvars.example` as a template. Create your local `terraform.tfvars` from it (do not commit it; it can contain personal IPs).

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and set:

- `ssh_allowed_cidrs` to your public IPv4 `/32` (needed when `enable_ec2` is true for SSH; ECS-only path does not rely on this for the ALB)
- `enable_ecs = true` for the ECS/Fargate runtime (already the default in `variables.tf`)
- `enable_ec2 = false` unless you need the legacy EC2 Docker/systemd runtime for debugging
- `ecs_assign_public_ip = false` so ECS tasks run without public IPs in private subnets
- `vpc_cidr`, `public_subnet_cidrs`, and `private_subnet_cidrs` if the default network ranges overlap with an existing environment
- `enable_github_incident_logs_reader_role` — leave `true` to create the read-only CloudWatch role for incident reports; set `false` if you do not want that role
- `github_actions_oidc_repository` — defaults to this template’s repo slug; **change it when you fork** so OIDC `sub` claims match your `owner/name` on GitHub

Required values without usable defaults (see [`terraform.tfvars.example`](./terraform.tfvars.example)):

- `docker_image` — API container image the ECS task (or EC2 host) runs
- `worker_image` — worker container image the ECS worker task runs; when omitted, Terraform derives the matching `devops-worker` tag from `docker_image`
- `ami_id` — must be present in `terraform.tfvars` (see example); **used only** when `enable_ec2` is true

## First-Time Bootstrap (No Existing Backend Bucket)

1. Create the remote state bucket from the bootstrap root:

```bash
cd bootstrap
terraform init
terraform apply
```

2. Return to the main infrastructure root:

```bash
cd ..
terraform init
```

For a brand-new environment, you can now continue with `terraform plan` and `terraform apply`.

If you already have local state from before enabling the S3 backend, migrate it instead:

```bash
terraform init -migrate-state
```

3. Verify state now points to the remote backend:

```bash
terraform state list
```

## Normal Workflow (After Backend Bootstrap)

Once the backend is bootstrapped, use normal Terraform commands:

```bash
terraform plan
terraform apply
```

## Drift Reporting

The repository includes a small drift reporter that runs Terraform from the repo root, parses `terraform plan -detailed-exitcode -json`, and prints a human-readable summary of managed resources that differ from the desired state:

```bash
python scripts/terraform_drift_report.py --terraform-dir infra
```

Exit codes are designed for CI:

- `0`: no drift detected
- `1`: script, Terraform, or JSON parsing error
- `2`: drift detected

For deterministic local checks, you can also pipe Terraform JSON into the parser without running Terraform:

```bash
terraform plan -detailed-exitcode -json | python ../scripts/terraform_drift_report.py --plan-json -
```

GitHub Actions also runs this on a weekday schedule in `.github/workflows/terraform-drift-report.yml`; the workflow writes the report to the job summary and uploads it as an artifact.

## ECS Fargate (cloud-native runtime)

This stack contains an ECS Fargate baseline running two services: the public API service from `docker_image` and a private background worker service from `worker_image`.

To enable ECS resources, set `enable_ecs = true` in your local `terraform.tfvars`.
The legacy EC2 Docker/systemd runtime is disabled by default. To enable it for debugging, set `enable_ec2 = true`; it runs in a custom public subnet with a public IP.

This stage fronts ECS tasks with an Application Load Balancer:

- Public traffic enters via ALB (HTTP port 80) and routes only to the API service.
- The ALB runs in the custom public subnets.
- API and worker ECS tasks run in the custom private subnets without public IPs.
- Private ECS tasks use VPC endpoints for ECR, S3, and CloudWatch Logs traffic.
- NAT egress remains available for other outbound internet access.
- Task security group allows app traffic only from the ALB security group; the worker has no load balancer attachment.
- Service endpoint is available in Terraform output `alb_dns_name`.
- ALB health-check path is configurable via `alb_health_check_path` (default `/`).
- ECS deployment health tuning:
  - `deployment_minimum_healthy_percent = 100`
  - `deployment_maximum_percent = 200`
  - `ecs_health_check_grace_period_seconds` (default `60`)
- Worker service capacity is configurable via `ecs_worker_desired_count` (default `1`).
- ECS task size is configurable via `ecs_task_cpu` (default `256`) and `ecs_task_memory` (default `512`).
- ECS log retention is configurable via `ecs_log_retention_days` (default `7`).

## Network baseline

This stack now creates a small custom network foundation:

- VPC with DNS support enabled.
- Two public subnets across available Availability Zones.
- Two private subnets across available Availability Zones.
- Internet gateway and public route table for the public subnet tier.
- Single NAT gateway and private route table for private subnet outbound access.
- VPC endpoints for ECR API, ECR Docker, CloudWatch Logs, and S3.

ECS now uses the custom private subnets behind the public ALB. The legacy EC2 debug runtime uses the custom public subnet path. For higher availability, a future iteration can add one NAT gateway per Availability Zone.

## Notable Terraform outputs

After a successful apply (with ECS enabled), these are the outputs people and automation most often need:

| Output | Meaning |
|--------|---------|
| `alb_dns_name` | Public DNS name of the load balancer (main HTTP entry point for the API). |
| `github_actions_incident_logs_reader_role_arn` | ARN to paste into GitHub as `AWS_INCIDENT_LOGS_READER_ROLE_ARN` when the incident-logs role is created. |
| `vpc_id`, `public_subnet_ids`, `private_subnet_ids` | Network identifiers for extensions or troubleshooting. |
| `nat_gateway_id`, `vpc_endpoint_ids` | NAT and VPC endpoint resources when ECS is on. |
| `public_ip` | Set only when `enable_ec2` is true (legacy VM). |

## Notes

- Run these commands from the `infra` directory.
- Run bootstrap commands from `infra/bootstrap`.
- If the bootstrap `state_bucket_name` changes, update the bucket name in `backend.tf` to match.
