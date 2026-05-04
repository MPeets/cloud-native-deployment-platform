#!/usr/bin/env bash
# Fails CI when container image vars use :latest (mutable tag / ECS rollout foot-gun).
set -euo pipefail

_immutable_check() {
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

_immutable_check TF_VAR_docker_image "${TF_VAR_docker_image:-}"
_immutable_check TF_VAR_worker_image "${TF_VAR_worker_image:-}"
