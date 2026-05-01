# cloud-native-deployment-platform

An end-to-end **DevOps sample**: a small **HTTP API** and **background worker** backed by **PostgreSQL**, packaged in **Docker**, deployed to **AWS** (ECS Fargate + load balancer) with **Terraform**, and validated by **GitHub Actions**. The same API is also packaged as **Kubernetes** manifests and a **Helm chart** for local clusters or a future move to managed Kubernetes—without changing the primary ECS design.

This file is the **map of the repo**. For depth, follow the links below.

## What lives where

| Part | Role | Docs |
|------|------|------|
| **[`app/`](app/)** | Express API (health, deployments CRUD, readiness). | [`app/README.md`](app/README.md) · [`app/test/README.md`](app/test/README.md) |
| **[`worker/`](worker/)** | Polls DB; moves deployments from pending through running to succeeded/failed (demo lifecycle). | [`worker/README.md`](worker/README.md) |
| **[`migrations/`](migrations/)** | Numbered SQL migrations. | Applied via [`scripts/run_migrations.py`](scripts/run_migrations.py); see [`scripts/README.md`](scripts/README.md) and [`docker/README.md`](docker/README.md). |
| **[`docker/`](docker/)** | Docker Compose: Postgres, migrations, API, worker. | [`docker/README.md`](docker/README.md) |
| **[`infra/`](infra/)** | Terraform: VPC, ECS Fargate, ALB, optional EC2 legacy, OIDC-friendly IAM (including incident log reader). | [`infra/README.md`](infra/README.md) |
| **[`k8s/`](k8s/)** | Kubernetes YAML + Helm chart for the API (portable packaging). | [`k8s/README.md`](k8s/README.md) |
| **[`scripts/`](scripts/)** | Python helpers: drift report, migrations runner, deploy health check, incident log pull. | [`scripts/README.md`](scripts/README.md) |
| **[`.github/workflows/`](.github/workflows/)** | CI/CD: image build, Terraform plan/apply/destroy, drift report, K8s lint, script lint, incident reports, etc. | Open the YAML files for triggers and inputs. |

## End-to-end flow (high level)

1. **Develop** the API and worker; **tests** run in CI.
2. **CI** builds and pushes API and worker container images; **Terraform** (manually or via workflows) rolls the API behind an **ALB** and runs the worker as a private ECS service.
3. **CloudWatch** collects logs; **scripts** can smoke-test the ALB, check ECS, scan recent logs, or summarize Terraform drift.
4. **Locally**, **Compose** brings up DB + migrate + API + worker so you can work without AWS.

**Production path:** ECS Fargate + ALB (Terraform). **Legacy path:** single EC2 + Docker (optional, off by default).

## GitHub Actions and AWS (OIDC)

Workflows assume an IAM role via **OIDC**—no long-lived AWS access keys stored in GitHub.

**Variables** (typical):

- `AWS_ROLE_TO_ASSUME` — ARN for the main deploy/infrastructure role
- `TF_AWS_REGION` — e.g. `eu-north-1`
- `TF_AMI_ID` — AMI for EC2 (still required as a Terraform variable when EC2 is disabled)
- `TF_DOCKER_IMAGE` — API image reference for Terraform (e.g. manual apply); image build workflows may derive tags from the commit
- `TF_WORKER_IMAGE` — worker image reference for manual Terraform workflows; defaults locally to the matching `devops-worker` tag when omitted
- `TF_ENABLE_ECS` — `true` for Fargate
- `TF_ENABLE_EC2` — `false` unless enabling the legacy VM path

**Secrets:**

- `TF_SSH_ALLOWED_CIDRS` — JSON array of CIDRs for SSH when EC2 is enabled, e.g. `["203.0.113.10/32"]`
- `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` — Docker Hub login for building and pushing the API and worker images (see [`ci.yml`](.github/workflows/ci.yml))

**Optional (incident log workflow):** set `AWS_INCIDENT_LOGS_READER_ROLE_ARN` from Terraform output `github_actions_incident_logs_reader_role_arn` — see [`infra/README.md`](infra/README.md).

The IAM **trust policy** for `AWS_ROLE_TO_ASSUME` must allow `token.actions.githubusercontent.com` for your repository. If you use [`infra/aws-oidc-role-trust-policy.json`](infra/aws-oidc-role-trust-policy.json) as a starting point, replace the example AWS account ID `123456789012` before creating the role.

## Related documentation

- **Bootstrap and drift:** [`infra/README.md`](infra/README.md)
- **Local full stack:** [`docker/README.md`](docker/README.md)
- **K8s-only packaging:** [`k8s/README.md`](k8s/README.md)
- **Operator / automation scripts:** [`scripts/README.md`](scripts/README.md)
