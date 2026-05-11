#!/usr/bin/env bash
# Sets TF_VAR_docker_image / TF_VAR_worker_image / TF_VAR_migrate_image from an explicit
# deploy SHA, or from the HEAD SHA of the latest successful "CI - Build & Push Docker Images"
# run on main (.github/workflows/ci.yml) when no explicit SHA is provided.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY unset}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN unset}"
: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME unset}"

resolve_latest_main_sha() {
  local api_url resp sha
  api_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/ci.yml/runs?branch=main&status=success&per_page=1"

  resp="$(curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_url}")"

  sha="$(echo "${resp}" | jq -r '.workflow_runs[0].head_sha // empty')"
  if [[ -z "${sha}" || "${sha}" == "null" ]]; then
    echo "::error::No successful ci.yml run on main yet. Push any change under app/, worker/, migrate/, migrations/, scripts/run_migrations.py, or infra/ on main first, wait for \"CI - Build & Push Docker Images\" to go green (all three images including devops-migrate)." >&2
    exit 1
  fi

  echo "${sha}"
}

SHA="${IMAGE_SHA:-}"
SOURCE="explicit IMAGE_SHA"

if [[ -z "${SHA}" ]]; then
  SHA="$(resolve_latest_main_sha)"
  SOURCE="latest successful ci.yml run on main"
fi

if [[ ! "${SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error title=Invalid image SHA::IMAGE_SHA must be the full 40-character commit SHA used by Docker image tags." >&2
  exit 1
fi

IMG_API="${DOCKERHUB_USERNAME}/devops-api:${SHA}"
IMG_WKR="${DOCKERHUB_USERNAME}/devops-worker:${SHA}"
IMG_MIGRATE="${DOCKERHUB_USERNAME}/devops-migrate:${SHA}"

{
  echo "TF_VAR_docker_image=${IMG_API}"
  echo "TF_VAR_worker_image=${IMG_WKR}"
  echo "TF_VAR_migrate_image=${IMG_MIGRATE}"
} >>"${GITHUB_ENV}"

# Duplicate pins as step outputs so workflows can pass them via explicit `env:` on Terraform steps.
# Relying on GITHUB_ENV alone can leave Terraform using tfvars placeholders in some Actions setups.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "image_sha=${SHA}"
    echo "docker_image=${IMG_API}"
    echo "worker_image=${IMG_WKR}"
    echo "migrate_image=${IMG_MIGRATE}"
  } >>"${GITHUB_OUTPUT}"
fi

echo "Terraform images pinned to ${SHA:0:7} from ${SOURCE}"
