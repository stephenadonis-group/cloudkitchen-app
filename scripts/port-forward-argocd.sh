#!/usr/bin/env bash
# port-forward-argocd.sh
# -----------------------------------------------------------------------------
# Open the ArgoCD UI locally by port-forwarding the argocd-server service.
#
# Usage:
#   ./scripts/port-forward-argocd.sh            # -> https://localhost:8083
#   LOCAL_PORT=9000 ./scripts/port-forward-argocd.sh
#
# Tip: print the initial admin password with:
#   kubectl -n argocd get secret argocd-initial-admin-secret \
#     -o jsonpath='{.data.password}' | base64 -d; echo
# -----------------------------------------------------------------------------
set -euo pipefail

NS="${NS:-argocd}"
LOCAL_PORT="${LOCAL_PORT:-8083}"

echo ">> ArgoCD UI: https://localhost:${LOCAL_PORT}  (user: admin)"
echo ">> initial password:"
kubectl -n "${NS}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null && echo || \
  echo "   (argocd-initial-admin-secret not found — maybe already rotated)"

echo ">> forwarding svc/argocd-server 443 -> localhost:${LOCAL_PORT} (Ctrl-C to stop)"
exec kubectl -n "${NS}" port-forward svc/argocd-server "${LOCAL_PORT}:443"
