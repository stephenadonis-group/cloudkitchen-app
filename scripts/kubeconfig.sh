#!/usr/bin/env bash
# kubeconfig.sh
# -----------------------------------------------------------------------------
# Update your local kubeconfig to point at the CloudKitchen EKS cluster, then
# verify connectivity.
#
# Usage:
#   ./scripts/kubeconfig.sh
#   CLUSTER_NAME=cloudkitchen-prod REGION=us-east-1 ./scripts/kubeconfig.sh
#   PROFILE=cloudkitchen ./scripts/kubeconfig.sh        # use a named AWS profile
#
# Env:
#   CLUSTER_NAME  EKS cluster name (default: cloudkitchen)
#   REGION        AWS region        (default: us-east-1)
#   PROFILE       AWS CLI profile   (optional)
#
# Requires: aws CLI, kubectl
# -----------------------------------------------------------------------------
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-cloudkitchen}"
REGION="${REGION:-us-east-1}"
PROFILE="${PROFILE:-}"

PROFILE_ARG=()
[[ -n "${PROFILE}" ]] && PROFILE_ARG=(--profile "${PROFILE}")

echo ">> Updating kubeconfig for EKS cluster '${CLUSTER_NAME}' in ${REGION}"
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  "${PROFILE_ARG[@]}"

echo ">> Current context: $(kubectl config current-context)"
echo ">> Cluster nodes:"
kubectl get nodes -o wide

echo ">> CloudKitchen namespaces:"
kubectl get ns cloudkitchen monitoring logging ingress argocd 2>/dev/null || true
