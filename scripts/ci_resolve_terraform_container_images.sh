#!/usr/bin/env bash
# Sets TF_VAR_docker_image / TF_VAR_worker_image from the HEAD SHA of the latest successful
# "CI - Build & Push Docker Images" workflow run on main (.github/workflows/ci.yml).
# Matches deploy.yml, which uses the same SHA after that workflow completes.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY unset}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN unset}"
: "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME unset}"

API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/ci.yml/runs?branch=main&status=success&per_page=1"

RESP="$(curl -fsSL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${API_URL}")"

SHA="$(echo "${RESP}" | jq -r '.workflow_runs[0].head_sha // empty')"
if [[ -z "${SHA}" || "${SHA}" == "null" ]]; then
  echo "::error::No successful ci.yml run on main; push a change under app/ or worker/ to main first." >&2
  exit 1
fi

IMG_API="${DOCKERHUB_USERNAME}/devops-api:${SHA}"
IMG_WKR="${DOCKERHUB_USERNAME}/devops-worker:${SHA}"

{
  echo "TF_VAR_docker_image=${IMG_API}"
  echo "TF_VAR_worker_image=${IMG_WKR}"
} >>"${GITHUB_ENV}"

# Duplicate pins as step outputs so workflows can pass them via explicit `env:` on Terraform steps.
# Relying on GITHUB_ENV alone can leave Terraform using tfvars placeholders in some Actions setups.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "docker_image=${IMG_API}"
    echo "worker_image=${IMG_WKR}"
  } >>"${GITHUB_OUTPUT}"
fi

echo "Terraform images pinned to Docker CI HEAD SHA ${SHA:0:7}"
