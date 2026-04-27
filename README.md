# cloud-native-deployment-platform
End-to-end CI/CD pipeline with Docker, AWS, and Terraform

## Infrastructure setup

Terraform backend bootstrapping and state migration steps are documented in `infra/README.md`.

## Runtime architecture

This project includes an ECS Fargate baseline (containers-as-primitives) in addition to the original single-EC2 Docker/systemd path.

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
