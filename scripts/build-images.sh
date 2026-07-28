#!/usr/bin/env bash
# build-images.sh
# -----------------------------------------------------------------------------
# Build a container image for every CloudKitchen backend service (and optionally
# the frontend). Each service has its own Dockerfile at ./<service>/Dockerfile.
#
# Usage:
#   ./scripts/build-images.sh                 # build all with tag 'local'
#   TAG=dev ./scripts/build-images.sh         # custom tag
#   REGISTRY=123.dkr.ecr.us-east-1.amazonaws.com/cloudkitchen \
#     TAG=$(git rev-parse --short HEAD) PUSH=1 ./scripts/build-images.sh
#
# Env:
#   REGISTRY   image name prefix (default: cloudkitchen). e.g. an ECR repo base.
#   TAG        image tag (default: local)
#   PUSH       if "1", docker push each image after building
#   FRONTEND   if "1", also build ./frontend
# -----------------------------------------------------------------------------
set -euo pipefail

# Resolve repo root (parent of this script's dir) so the script works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REGISTRY="${REGISTRY:-cloudkitchen}"
TAG="${TAG:-local}"
PUSH="${PUSH:-0}"
FRONTEND="${FRONTEND:-0}"

SERVICES=(auth-service user-service restaurant-service menu-service order-service payment-service delivery-service notification-service)

echo ">> Building CloudKitchen images (registry=${REGISTRY} tag=${TAG})"

build_one() {
  local name="$1" ctx="$2"
  local image="${REGISTRY}/${name}:${TAG}"
  echo ">> [${name}] building ${image} from ${ctx}"
  docker build -t "${image}" "${ctx}"
  if [[ "${PUSH}" == "1" ]]; then
    echo ">> [${name}] pushing ${image}"
    docker push "${image}"
  fi
}

for svc in "${SERVICES[@]}"; do
  build_one "${svc}" "${ROOT_DIR}/${svc}"
done

if [[ "${FRONTEND}" == "1" ]]; then
  build_one "frontend" "${ROOT_DIR}/frontend"
fi

echo ">> Done. Built ${#SERVICES[@]} service image(s)."
