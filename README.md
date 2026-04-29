# cloud-native-deployment-platform
End-to-end CI/CD pipeline with Docker, AWS, and Terraform — plus **Kubernetes packaging** (manifests and Helm) for portable deployment patterns and portfolio use.

## Kubernetes (`k8s/`)

The production path in this repository is **ECS Fargate** (see below). The [`k8s/`](k8s/README.md) directory holds **vanilla YAML manifests** and a **Helm chart** for the same API. Together they support local clusters (Docker Desktop, kind, minikube) or a future move to managed Kubernetes without changing the current Terraform design.

**Start here:** [`k8s/README.md`](k8s/README.md) — layout, design notes, `kubectl` / `helm` commands, local testing tips, and how **CI** lints manifests and Helm on `k8s/**` changes (`.github/workflows/k8s-lint.yml`).
## Infrastructure setup

Terraform backend bootstrapping now lives in `infra/bootstrap`; setup and state migration steps are documented in `infra/README.md`.

## Runtime architecture

The primary runtime is **ECS Fargate** behind an **Application Load Balancer**. Terraform provisions the ECS cluster, task definition, service, ALB, target group, security groups, IAM execution role, and CloudWatch logging.

The original single-EC2 Docker/systemd deployment is kept only as an optional legacy/debug runtime and is disabled by default (`TF_ENABLE_EC2=false`). ECS/Fargate is enabled by default (`TF_ENABLE_ECS=true`) so the deployed path uses managed container orchestration instead of a single VM.

High-level flow:

- CI builds and pushes the Docker image.
- Terraform deploys the image as an ECS Fargate task/service.
- The ALB exposes HTTP traffic to the service.
- CloudWatch captures container logs.

## CI AWS authentication (OIDC)

This project uses GitHub Actions OIDC to assume an AWS IAM role (no long-lived AWS keys in GitHub secrets).

- GitHub Actions **Variables**:
  - `AWS_ROLE_TO_ASSUME`: IAM role ARN to assume from workflows
  - `TF_AWS_REGION`: AWS region (e.g. `eu-north-1`)
  - `TF_AMI_ID`: AMI id to deploy
  - `TF_DOCKER_IMAGE`: Docker image reference for EC2 to run
  - `TF_ENABLE_ECS`: `true` for ECS/Fargate runtime
  - `TF_ENABLE_EC2`: `false` unless enabling legacy EC2 for debugging
- GitHub Actions **Secrets**:
  - `TF_SSH_ALLOWED_CIDRS`: JSON array string like `["203.0.113.10/32"]`

IAM trust policy must allow `token.actions.githubusercontent.com` for this repository.
