# Logging

Centralized log aggregation with **Grafana Loki** (storage/query) and
**Promtail** (collection), deployed into the `logging` namespace.

## Contents

| Path                    | Purpose |
|-------------------------|---------|
| `loki-values.yaml`      | Helm values for Loki (single-binary mode, 7-day retention) |
| `promtail-values.yaml`  | Helm values for Promtail DaemonSet (scrapes `cloudkitchen` ns, parses JSON) |

## How it works

The Go microservices write **structured JSON logs to stdout**, e.g.:

```json
{"time":"2026-05-27T10:00:00Z","level":"info","msg":"request handled","service":"order","trace_id":"abc123","method":"POST","path":"/orders","status":201,"duration_ms":12}
```

Promtail runs as a DaemonSet, tails `/var/log/pods/...`, keeps only pods in the
`cloudkitchen` namespace, parses the JSON, and promotes `level` and `service`
to Loki labels (kept deliberately low-cardinality). The application's own
`time` field is used as the log timestamp. Logs are pushed to the Loki gateway
and queried from Grafana.

## Install

```sh
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki \
  -n logging --create-namespace -f logging/loki-values.yaml

helm upgrade --install promtail grafana/promtail \
  -n logging -f logging/promtail-values.yaml
```

## Add Loki as a Grafana datasource

URL (in-cluster): `http://loki-gateway.logging.svc.cluster.local`

## Example LogQL queries

```logql
# All logs from the order service
{namespace="cloudkitchen", service="order"}

# Errors across all services
{namespace="cloudkitchen", level="error"}

# Error rate per service over 5m
sum by (service) (rate({namespace="cloudkitchen", level="error"}[5m]))

# Follow one request across services by trace id
{namespace="cloudkitchen"} |= "abc123"
```

## Production notes

- For real workloads switch Loki `storage.type` to `s3` (us-east-1 bucket) and
  grant access via **IRSA** (annotate the Loki ServiceAccount with the IAM role
  ARN). See `loki-values.yaml` comments.
- For higher throughput change `deploymentMode` to `SimpleScalable`.
