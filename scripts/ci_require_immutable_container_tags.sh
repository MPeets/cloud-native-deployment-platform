#!/usr/bin/env bash
# Ensures Terraform gets real container pins in CI (tfvars use placeholder tags that ECS cannot pull).
# Also rejects :latest and tfvars-placeholder* substrings.
set -euo pipefail

_ci_require_pins() {
  local d="${TF_VAR_docker_image:-}"
  local w="${TF_VAR_worker_image:-}"
  local m="${TF_VAR_migrate_image:-}"
  if [[ -z "$d" || -z "$w" || -z "$m" ]]; then
    echo "::error title=Missing image pins::TF_VAR_docker_image, TF_VAR_worker_image, and TF_VAR_migrate_image must be set in GitHub Actions before Terraform (run scripts/ci_resolve_terraform_container_images.sh, or set all three explicitly)." >&2
    exit 1
  fi
}

_immutable_latest_check() {
  local name=$1
  local val=$2
  [[ -n "$val" ]] || return 0
  case "$val" in
  *:latest)
    echo "::error title=Mutable image tag::${name} must not use :latest; pin Git SHA, semver, or digest." >&2
    exit 1
    ;;
  esac
}

_placeholder_check() {
  local name=$1
  local val=$2
  [[ -n "$val" ]] || return 0
  case "$val" in
  *tfvars-placeholder*)
    echo "::error title=Invalid image tag::${name} still uses a tfvars placeholder; Terraform would deploy an image that does not exist on the registry. Run ci_resolve_terraform_container_images.sh or set a real tag." >&2
    exit 1
    ;;
  esac
}

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  _ci_require_pins
fi

_immutable_latest_check TF_VAR_docker_image "${TF_VAR_docker_image:-}"
_immutable_latest_check TF_VAR_worker_image "${TF_VAR_worker_image:-}"
_immutable_latest_check TF_VAR_migrate_image "${TF_VAR_migrate_image:-}"
_placeholder_check TF_VAR_docker_image "${TF_VAR_docker_image:-}"
_placeholder_check TF_VAR_worker_image "${TF_VAR_worker_image:-}"
_placeholder_check TF_VAR_migrate_image "${TF_VAR_migrate_image:-}"
