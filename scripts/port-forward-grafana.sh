#!/usr/bin/env bash
# port-forward-grafana.sh
# -----------------------------------------------------------------------------
# Open the Grafana UI locally by port-forwarding the kube-prometheus-stack
# Grafana service.
#
# Usage:
#   ./scripts/port-forward-grafana.sh           # -> http://localhost:3001
#   LOCAL_PORT=3005 ./scripts/port-forward-grafana.sh
#
# Default login (from monitoring/prometheus-values.yaml placeholder):
#   admin / changeme-use-a-secret
# Retrieve the real password (if set via secret) with:
#   kubectl -n monitoring get secret kube-prom-stack-grafana \
#     -o jsonpath='{.data.admin-password}' | base64 -d; echo
# -----------------------------------------------------------------------------
set -euo pipefail

NS="${NS:-monitoring}"
LOCAL_PORT="${LOCAL_PORT:-3001}"
SVC="${SVC:-kube-prom-stack-grafana}"

echo ">> Grafana UI: http://localhost:${LOCAL_PORT}  (user: admin)"
echo ">> forwarding svc/${SVC} 80 -> localhost:${LOCAL_PORT} (Ctrl-C to stop)"
exec kubectl -n "${NS}" port-forward "svc/${SVC}" "${LOCAL_PORT}:80"
