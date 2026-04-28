# Terraform Infrastructure

This folder contains two Terraform roots:

- `bootstrap/`: creates the S3 bucket used by Terraform remote state. This root uses local state and is only needed when the backend bucket does not exist yet.
- `./`: deploys the application infrastructure and configures Terraform to use the S3 backend in `backend.tf` (with S3 lockfile locking).

Keeping backend bootstrap resources out of the main root avoids Terraform trying to manage the same bucket from the state stored in that bucket.

## Local config (`terraform.tfvars`)

This repo includes `terraform.tfvars.example` as a template. Create your local `terraform.tfvars` from it (do not commit it; it can contain personal IPs).

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and set:

- `ssh_allowed_cidrs` to your public IPv4 `/32`
- `enable_ecs = true` for the ECS/Fargate runtime
- `enable_ec2 = false` unless you need the legacy EC2 Docker/systemd runtime for debugging
- `ecs_assign_public_ip = false` so ECS tasks run without public IPs in private subnets
- `vpc_cidr`, `public_subnet_cidrs`, and `private_subnet_cidrs` if the default network ranges overlap with an existing environment

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

## ECS Fargate (cloud-native runtime)

This stack contains an ECS Fargate baseline (cluster + task definition + service) running the `docker_image`.

To enable ECS resources, set `enable_ecs = true` in your local `terraform.tfvars`.
The legacy EC2 Docker/systemd runtime is disabled by default. To enable it for debugging, set `enable_ec2 = true`.

This stage fronts ECS tasks with an Application Load Balancer:

- Public traffic enters via ALB (HTTP port 80).
- The ALB runs in the custom public subnets.
- ECS tasks run in the custom private subnets without public IPs.
- Private ECS tasks use NAT egress to pull images and write logs to ECR and CloudWatch Logs.
- Task security group allows app traffic only from the ALB security group.
- Service endpoint is available in Terraform output `alb_dns_name`.
- ALB health-check path is configurable via `alb_health_check_path` (default `/`).
- ECS deployment health tuning:
  - `deployment_minimum_healthy_percent = 100`
  - `deployment_maximum_percent = 200`
  - `ecs_health_check_grace_period_seconds` (default `60`)
- ECS task size is configurable via `ecs_task_cpu` (default `256`) and `ecs_task_memory` (default `512`).
- ECS log retention is configurable via `ecs_log_retention_days` (default `7`).

## Network baseline

This stack now creates a small custom network foundation:

- VPC with DNS support enabled.
- Two public subnets across available Availability Zones.
- Two private subnets across available Availability Zones.
- Internet gateway and public route table for the public subnet tier.
- Single NAT gateway and private route table for private subnet outbound access.

ECS now uses the custom private subnets behind the public ALB. The legacy EC2 runtime still uses the default VPC path. For higher availability, a future iteration can add one NAT gateway per Availability Zone or replace NAT egress for AWS services with private VPC endpoints.

## Notes

- Run these commands from the `infra` directory.
- Run bootstrap commands from `infra/bootstrap`.
- If the bootstrap `state_bucket_name` changes, update the bucket name in `backend.tf` to match.
