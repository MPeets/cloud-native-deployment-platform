# Terraform Infrastructure

This folder contains both:

- `backend-bootstrap.tf`: creates the S3 bucket used by Terraform remote state.
- `backend.tf`: configures Terraform to use that S3 backend (with S3 lockfile locking).

Because these live in the same root module, first-time setup requires a one-time bootstrap flow.

## Local config (`terraform.tfvars`)

This repo includes `terraform.tfvars.example` as a template. Create your local `terraform.tfvars` from it (do not commit it; it can contain personal IPs).

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` and set `ssh_allowed_cidrs` to your public IPv4 `/32`.

## First-Time Bootstrap (No Existing Remote State)

1. Temporarily disable the S3 backend config by renaming `backend.tf`:

```bash
mv backend.tf backend.tf.disabled
```

2. Initialize and apply with the default local backend:

```bash
terraform init
terraform apply
```

3. Re-enable the backend config:

```bash
mv backend.tf.disabled backend.tf
```

4. Re-initialize and migrate local state to S3:

```bash
terraform init -migrate-state
```

5. Verify state now points to the remote backend:

```bash
terraform state list
```

## Normal Workflow (After Bootstrap)

Once the backend is bootstrapped, use normal Terraform commands:

```bash
terraform plan
terraform apply
```

## ECS Fargate (cloud-native runtime)

This stack contains an ECS Fargate baseline (cluster + task definition + service) running the `docker_image`.

To enable ECS resources, set `enable_ecs = true` in your local `terraform.tfvars`.

Note: at this stage the service is assigned a public IP and the security group allows inbound traffic to `app_port` from the internet. A follow-up improvement is to front the service with an Application Load Balancer and restrict task networking.

## Notes

- Run these commands from the `infra` directory.
- If backend resource names change in `backend-bootstrap.tf`, update `backend.tf` to match.
