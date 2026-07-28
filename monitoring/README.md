# Monitoring & Logging — standalone YAMLs

All the standalone YAMLs that make up the observability stack for the
CloudKitchen platform on GKE. The chart values themselves live in
[`argocd/apps/app-monitoring.yaml`](../argocd/apps/app-monitoring.yaml) and
[`argocd/apps/app-logging.yaml`](../argocd/apps/app-logging.yaml); the files
in this directory are the **extras** on top (IngressRoutes, ServiceMonitor,
custom dashboards, alert rules) that the charts don't ship by default.

The end-to-end walkthrough is **[docs/gcp/06-monitoring-and-logging.md](../docs/gcp/06-monitoring-and-logging.md)** —
read that for context; this README is just the file index.

## File index

| Path                                          | What it is                                                                                  | Apply with                                                            |
| --------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `servicemonitor.yaml`                         | ServiceMonitor that tells Prometheus to scrape all 8 backend microservices.                 | `kubectl apply -f monitoring/servicemonitor.yaml`                     |
| `ingressroutes/grafana.yaml`                  | Traefik IngressRoute exposing Grafana at `http://<host>/grafana/`.                          | `kubectl apply -f monitoring/ingressroutes/grafana.yaml`              |
| `ingressroutes/prometheus.yaml`               | Traefik IngressRoute exposing Prometheus at `http://<host>/prometheus/`.                    | `kubectl apply -f monitoring/ingressroutes/prometheus.yaml`           |
| `ingressroutes/alertmanager.yaml`             | Traefik IngressRoute exposing Alertmanager at `http://<host>/alertmanager/`.                | `kubectl apply -f monitoring/ingressroutes/alertmanager.yaml`         |
| `prometheusrules.yaml`                        | Alerting + recording rules (error-rate SLO, CrashLoopBackOff, high latency, …).             | `kubectl apply -f monitoring/prometheusrules.yaml`                    |
| `dashboards/generate.py`                      | Python generator. One `dashboard()` function emits 10 panels per microservice.              | (template — re-run if you customize panels)                           |
| `dashboards/cloudkitchen-dashboards.yaml`     | Generated output — 8 ConfigMaps labeled `grafana_dashboard: "1"` (sidecar auto-loads them). | `kubectl apply -f monitoring/dashboards/cloudkitchen-dashboards.yaml` |

> ⚠️ **All four manual-apply YAMLs include the annotation
> `argocd.argoproj.io/sync-options: Prune=false`** so they survive an ArgoCD
> sync even though no Application currently tracks them. Don't strip those
> annotations.

## Apply everything in one shot

```bash
# from repo root
kubectl apply -f monitoring/servicemonitor.yaml
kubectl apply -f monitoring/ingressroutes/
kubectl apply -f monitoring/dashboards/cloudkitchen-dashboards.yaml
kubectl apply -f monitoring/prometheusrules.yaml      # optional — alert rules
```

## How the pieces fit

```
                      Traefik LB (single IP)
                                │
   ┌───────────────────────────┼─────────────────────────┐
   │                           │                          │
   ▼ /grafana/                 ▼ /prometheus/             ▼ /alertmanager/
   monitoring-grafana          kube-prometheus-           kube-prometheus-
   :80                         prometheus:9090            alertmanager:9093
       ▲                            ▲                          ▲
       │ datasource: Prometheus     │ scrapes /metrics on      │ fires alerts
       │ datasource: Loki           │ the named `http` port     │ from rules in
       │                            │                          │ prometheusrules.yaml
       │                            │   ServiceMonitor:        │
       │                            │   selects label          │
       │                            │   app.kubernetes.io/     │
       │                            │   part-of: cloudkitchen  │
       │                            │                          │
       │                ┌───────────┴────────────┐             │
       │                │  cloudkitchen ns        │             │
       │                │  8 Go services          │             │
       │                │  (each exposes          │             │
       │                │   /metrics on :8080)    │             │
       │                └────────────────────────┘             │
       │                                                       │
       │                                                       │
       │  Auto-loaded by Grafana's sidecar from any            │
       │  ConfigMap labeled grafana_dashboard=1 ⇒              │
       │  dashboards/cloudkitchen-dashboards.yaml (8 dashboards)│
       │                                                       │

   Logging stack (logging ns):
       Promtail (DaemonSet) ─► Loki :3100  ◀── Grafana queries via the
                                                Loki datasource
```

## URLs (replace `vijaygiduthuri.in` with your hostname)

| UI            | URL                                                                                                |
| ------------- | -------------------------------------------------------------------------------------------------- |
| Grafana       | http://vijaygiduthuri.in/grafana/                                                                  |
| Prometheus    | http://vijaygiduthuri.in/prometheus/                                                               |
| Alertmanager  | http://vijaygiduthuri.in/alertmanager/                                                             |
| Per-service dashboards | http://vijaygiduthuri.in/grafana/d/ck-&lt;service&gt;/cloudkitchen-&lt;service&gt;                         |
