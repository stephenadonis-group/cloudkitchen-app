# Phase 6 — Monitoring & Logging Stack

**Goal:** Install **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager
+ node-exporter + kube-state-metrics) and **Loki + Promtail**, configure
**ServiceMonitors** so every CloudKitchen service is scraped, add
**PrometheusRules** with real alerts, and import **Grafana dashboards**.

**Time:** ~15 minutes.

---

## What & why

Observability = **metrics + logs + traces**. This phase covers the first two:

| Stack | Component | Job |
|---|---|---|
| **Metrics** | Prometheus | scrapes `/metrics` from every pod + cluster components |
|  | Grafana | dashboards, ad-hoc queries |
|  | Alertmanager | dispatches alerts (Slack/email/PagerDuty) |
|  | kube-state-metrics | exposes K8s object counts as metrics |
|  | node-exporter | scrapes per-node OS metrics |
| **Logs** | Loki | log database (like Prometheus, but for text) |
|  | Promtail | DaemonSet that ships every pod's stdout into Loki |

Each of our 8 backend services already exposes `/metrics` on port `8080`
(Gin + prometheus client). The chart's Services carry the
`app.kubernetes.io/part-of: cloudkitchen` label — that's what the
ServiceMonitor selects.

---

## What this phase creates

```
                 ┌──────────────────────────┐
                 │   monitoring namespace   │
                 │   prometheus, grafana,   │
                 │   alertmanager, ksm,     │
                 │   node-exporter          │
                 └────────────┬─────────────┘
                              │ scrapes
                              ▼
              ┌──────────────────────────────┐
              │  cloudkitchen namespace      │
              │  ServiceMonitor selects all  │
              │  app.k8s.io/part-of:         │
              │       cloudkitchen           │
              └──────────────────────────────┘

                 ┌──────────────────────────┐
                 │   logging namespace      │
                 │   loki                   │
                 │   promtail (DaemonSet)   │ ← reads every pod's logs
                 └──────────────────────────┘
```

---

## ✅ Prerequisites

| Check | Command |
|-------|---------|
| Phase 4 done (app pods running) | `kubectl -n cloudkitchen get pods` |
| Services labelled correctly | `kubectl -n cloudkitchen get svc -l app.kubernetes.io/part-of=cloudkitchen` should list 9 services |
| `helm` repo cache is recent | `helm repo update` |

---

## Step 1 — Add the chart repos

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```
**What this does:** Registers the Prometheus and Grafana Helm chart
repositories so we can install kube-prometheus-stack (from
prometheus-community) and Loki/Promtail (from grafana).

---

## Step 2 — Create the `monitoring` namespace and install kube-prometheus-stack

```bash
kubectl create namespace monitoring

helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f monitoring/prometheus-values.yaml
```
**What this does:**
- Installs the bundle (Prometheus Operator + Prometheus + Alertmanager +
  Grafana + kube-state-metrics + node-exporter) as one release.
- `monitoring/prometheus-values.yaml` is a pre-tuned values file in the repo:
  - Lower resource requests (so it fits on small clusters)
  - Enables **annotation-based scrape discovery** so any pod with
    `prometheus.io/scrape: "true"` is scraped automatically
  - Default Grafana admin password set (change it!)

Wait for everything to come up (Prometheus and Grafana each take ~1 min):
```bash
kubectl -n monitoring rollout status statefulset/prometheus-kube-prom-stack-prometheus
kubectl -n monitoring rollout status deploy/kube-prom-stack-grafana
```

---

## Step 3 — Add a ServiceMonitor for the CloudKitchen services

The repo already has `monitoring/servicemonitor.yaml` that selects services
labelled `app.kubernetes.io/part-of: cloudkitchen`. Apply it:

```bash
kubectl apply -n monitoring -f monitoring/servicemonitor.yaml
```
**What this does:** Creates a `ServiceMonitor` CR. The Prometheus Operator
watches for these and adds matching Services to the Prometheus scrape config —
**without restarting Prometheus**. Since our chart already labels every service
with `app.kubernetes.io/part-of: cloudkitchen` and exposes a named port `http`,
this single resource covers all 9 services.

Verify the new targets appear:
```bash
kubectl -n monitoring port-forward svc/kube-prom-stack-prometheus 9090 &
# Open  http://localhost:9090/targets   in your browser
# Look for serviceMonitor/monitoring/cloudkitchen-services/0 -- all "UP".
```

---

## Step 4 — Apply the CloudKitchen PrometheusRules (alerts)

The repo has `monitoring/prometheusrules.yaml` defining:
- Recording rules: `cloudkitchen:http_requests:rate5m`,
  `cloudkitchen:http_5xx:rate5m`, `cloudkitchen:http_latency_p95`
- Alerts: `CloudKitchenHighErrorRate`, `CloudKitchenHighLatency`,
  `CloudKitchenPodNotReady`, `CloudKitchenCrashLoopBackOff`,
  `CloudKitchenDeploymentDegraded`, `CloudKitchenPostgresDown`,
  `CloudKitchenNATSDown`

```bash
kubectl apply -f monitoring/prometheusrules.yaml
```
**What this does:** The Prometheus Operator picks up any `PrometheusRule`
resource labelled `release: kube-prom-stack` and loads it into Prometheus —
again, no restart needed. Confirm they loaded:
```bash
# In the Prometheus UI -> Status -> Rules
# Or via API:
kubectl -n monitoring port-forward svc/kube-prom-stack-prometheus 9090 >/dev/null &
curl -s localhost:9090/api/v1/rules | jq '.data.groups[].name'
# Expect to see "cloudkitchen.http", "cloudkitchen.kubernetes", "cloudkitchen.data"
```

---

## Step 5 — Import the Grafana dashboards

The repo ships 5 dashboards in `monitoring/grafana/dashboards/`:
- `cpu-usage.json`
- `memory-usage.json`
- `pod-health.json`
- `http-request-rate.json`
- `http-error-rate.json`

### 5.1 — Get the Grafana admin password

```bash
kubectl -n monitoring get secret kube-prom-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d ; echo
```

### 5.2 — Open Grafana

```bash
kubectl -n monitoring port-forward svc/kube-prom-stack-grafana 3000:80
```
Browse https://localhost:3000 — login as `admin` + the password above.

### 5.3 — Import each dashboard

For each `*.json`: Grafana left menu → **Dashboards → New → Import → Upload
JSON file** → pick `monitoring/grafana/dashboards/<file>.json` → choose the
`Prometheus` datasource → **Import**.

> 💡 **Pro tip — load them automatically:** add them to the `kube-prom-stack`
> values under `grafana.dashboards.cloudkitchen` (configMap-style provisioning)
> so Grafana picks them up on every install. Phase 7 documents this pattern
> when we also surface Grafana through Traefik.

---

## Step 6 — Install Loki + Promtail (logs)

```bash
kubectl create namespace logging

helm install loki grafana/loki -n logging -f logging/loki-values.yaml
helm install promtail grafana/promtail -n logging -f logging/promtail-values.yaml
```
**What this does:**
- **Loki** = the log database. Runs as a StatefulSet (single binary by default
  — fine for learning; HA modes available).
- **Promtail** = a DaemonSet (one pod per node) that tails every container's
  log file and ships it to Loki, tagged with the namespace, pod, container,
  and the `level`/`service` fields we emit in our JSON logs.

Wait:
```bash
kubectl -n logging get pods
# Expect: loki-0 Running, promtail-* on each node
```

---

## Step 7 — Wire Loki into Grafana

In Grafana → **Configuration → Data sources → Add data source → Loki**.

| Field | Value |
|------|-------|
| Name | `Loki` |
| URL  | `http://loki.logging.svc.cluster.local:3100` |

Click **Save & test** → expect a green "Data source is working".

Now in **Grafana → Explore → Loki**, you can run LogQL:

| LogQL query | Returns |
|---|---|
| `{namespace="cloudkitchen"}` | every log line from any pod in our namespace |
| `{namespace="cloudkitchen", app="order-service"} \|= "ERROR"` | only order-service errors |
| `{namespace="cloudkitchen"} \|= "order.placed"` | every log line mentioning the event |

---

## Step 8 — Verify

```bash
# 1. All monitoring pods Running
kubectl -n monitoring get pods
kubectl -n logging   get pods

# 2. Prometheus targets — all UP
# Open localhost:9090/targets after port-forward; look for our 8 services.

# 3. Rules loaded
curl -s localhost:9090/api/v1/rules \
  | jq '.data.groups[] | select(.name | startswith("cloudkitchen"))'

# 4. Recording rule produces values
curl -sG --data-urlencode 'query=cloudkitchen:http_requests:rate5m' \
  localhost:9090/api/v1/query | jq .data.result | head

# 5. Grafana dashboards render with data — open the 5 imported boards.

# 6. Loki is receiving logs
# In Grafana → Explore → Loki:
#   {namespace="cloudkitchen"} | json
# Should show lines flowing in real time.
```

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Prometheus targets all `DOWN` | ServiceMonitor selector mismatch | Confirm services carry `app.kubernetes.io/part-of: cloudkitchen` label; `kubectl -n cloudkitchen get svc -L app.kubernetes.io/part-of` |
| `PrometheusRule` resource ignored | Missing `release: kube-prom-stack` label | already set in `monitoring/prometheusrules.yaml`; ensure your helm release is named `kube-prom-stack` |
| Grafana dashboards blank | Wrong datasource UID | edit panel → datasource → select `Prometheus` |
| `loki-0` `CrashLoopBackOff` (resource limits) | Loki single-binary needs ~1Gi memory | bump `resources.limits.memory` in `logging/loki-values.yaml`, `helm upgrade …` |
| Promtail not scraping our namespace | Filter too tight | `logging/promtail-values.yaml` already limits to `cloudkitchen` ns — broaden if needed |
| Alerts firing immediately after install | Recording rules need a few minutes of data | wait 10 min; alerts have `for: 5m`/`10m` cooldowns |

---

## 📋 Phase 6 cheatsheet

```bash
# Repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Monitoring stack
kubectl create ns monitoring
helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/prometheus-values.yaml
kubectl apply -n monitoring -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/prometheusrules.yaml

# Logs
kubectl create ns logging
helm install loki     grafana/loki     -n logging -f logging/loki-values.yaml
helm install promtail grafana/promtail -n logging -f logging/promtail-values.yaml

# UIs (port-forward for now; Phase 7 exposes them through Traefik)
kubectl -n monitoring port-forward svc/kube-prom-stack-prometheus 9090  &
kubectl -n monitoring port-forward svc/kube-prom-stack-grafana    3000:80 &
```

---

## 🎉 What you accomplished

- ✅ Prometheus is scraping every CloudKitchen service via a single
  ServiceMonitor.
- ✅ Recording rules + 6 alerts loaded; firing on real conditions.
- ✅ 5 Grafana dashboards imported and showing live data.
- ✅ Loki + Promtail capturing every container log; queryable from Grafana.

➡️ **Next:** [Phase 7 — HTTPS + sub-path routing](07-https-letsencrypt-and-routes.md)
