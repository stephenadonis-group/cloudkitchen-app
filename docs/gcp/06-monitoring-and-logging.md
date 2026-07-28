# Phase 6 — Monitoring + Logging (GCP)

**Goal:** Add a full observability stack — **Prometheus** (metrics), **Grafana**
(dashboards), **Alertmanager** (alerts), **Loki** (logs), **Promtail** (log
shipper) — and expose Grafana, Prometheus, and Alertmanager UIs under
sub-paths of your existing domain.

**Time:** ~25 min. Most of it is waiting for the charts to come up
(Prometheus + Alertmanager each provision a PVC and a StatefulSet).

> Before this phase: cluster has the app + ArgoCD + Traefik. No metrics, no logs.
> After:  http://vijaygiduthuri.in/grafana/      — dashboards
>         http://vijaygiduthuri.in/prometheus/   — Prometheus UI
>         http://vijaygiduthuri.in/alertmanager/ — Alertmanager UI
>         Logs from every Pod stream into Loki, queryable from Grafana.

---

## What gets installed

```
                       internet
                          │
                          ▼
              ┌──────────────────────┐
              │ Traefik LB (existing) │
              │ 35.224.38.103         │
              └──────────┬───────────┘
                         │  IngressRoutes (one per UI)
        ┌────────────────┼──────────────────┐
        │                │                  │
        ▼                ▼                  ▼
   /grafana/        /prometheus/      /alertmanager/
        │                │                  │
        ▼                ▼                  ▼
   ┌─────────────────────────────────────────────────────────┐
   │  namespace: monitoring                                   │
   │  ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌──────────┐ │
   │  │ Grafana  │ │ Prometheus │ │Alertmanager│ │node-exp/ │ │
   │  │          │ │   (PVC)    │ │  (PVC)     │ │ kube-st  │ │
   │  └────┬─────┘ └─────┬──────┘ └────────────┘ └──────────┘ │
   │       │             ▲                                    │
   │       │             │ scrape (ServiceMonitor CRDs)       │
   │       │             │                                    │
   │       │       ┌─────┴─────────────────────────────┐      │
   │       │       │ every Pod with /metrics endpoint  │      │
   │       │       └───────────────────────────────────┘      │
   │       │ datasource                                       │
   │       ▼                                                  │
   │  ┌──────────┐                                            │
   │  │   Loki   │ ◀── Promtail (DaemonSet) tails container   │
   │  │  (PVC)   │     logs on every node                     │
   │  └──────────┘                                            │
   │  namespace: logging                                      │
   └─────────────────────────────────────────────────────────┘
```

| Component | Chart | Namespace | Why |
|---|---|---|---|
| Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics | `kube-prometheus-stack` | `monitoring` | The well-known "kube-prom-stack" bundle. One install, all of it wired together with `ServiceMonitor` CRDs. |
| Loki + Promtail | `loki-stack` | `logging` | Loki = log store. Promtail = DaemonSet that tails container logs on every node and ships them to Loki. |

---

## ✅ Prerequisites

| Need                                              | How to check                                                            |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| Phase 5 done (DNS works, app reachable at hostname) | `curl -sI http://vijaygiduthuri.in/`  → HTTP 200                       |
| Cluster has CPU/memory headroom                   | `kubectl top nodes`  → both nodes < 50% CPU + memory                    |
| Storage class `standard-rwo` available            | `kubectl get storageclass`  → `standard-rwo` should exist (GKE default) |

---

## Step 1 — Update `argocd/apps/app-monitoring.yaml`

The file already exists; we change its `helm.values:` block to make
Grafana / Prometheus / Alertmanager serve at sub-paths on your domain.

**What to do:** open [argocd/apps/app-monitoring.yaml](../../argocd/apps/app-monitoring.yaml)
and replace its `spec.source.helm.values:` block with the version below
(the rest of the file — apiVersion, metadata, destination, syncPolicy —
stays the same).

```yaml
        fullnameOverride: kube-prometheus

        # ---------------------------------------------------------------
        # Grafana — served at /grafana via Traefik IngressRoute (external
        # to this chart). The chart's bundled Ingress is DISABLED.
        # ---------------------------------------------------------------
        grafana:
          enabled: true
          defaultDashboardsEnabled: true
          ingress:
            enabled: false         # 👈 we use a Traefik IngressRoute instead
          grafana.ini:
            server:
              domain: vijaygiduthuri.in
              root_url: "http://vijaygiduthuri.in/grafana/"
              serve_from_sub_path: true
          additionalDataSources:
            - name: Loki           # 👈 auto-add Loki as a Grafana datasource
              type: loki
              uid: loki
              access: proxy
              url: http://loki.logging.svc.cluster.local:3100
              isDefault: false
              jsonData:
                maxLines: 1000
          resources:
            requests: {cpu: 50m,  memory: 128Mi}
            limits:   {cpu: 200m, memory: 256Mi}

        # ---------------------------------------------------------------
        # Prometheus — served at /prometheus.
        # routePrefix + externalUrl together tell Prometheus that all of
        # its UI links + redirects should be /prometheus-prefixed.
        # ---------------------------------------------------------------
        prometheus:
          prometheusSpec:
            retention: 15d
            routePrefix: /prometheus                            # 👈
            externalUrl: http://vijaygiduthuri.in/prometheus    # 👈
            serviceMonitorSelectorNilUsesHelmValues: false
            podMonitorSelectorNilUsesHelmValues: false
            resources:
              requests: {cpu: 250m, memory: 512Mi}
              limits:   {cpu: "1",  memory: 2Gi}
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 20Gi

        # ---------------------------------------------------------------
        # Alertmanager — served at /alertmanager.
        # ---------------------------------------------------------------
        alertmanager:
          enabled: true
          alertmanagerSpec:
            routePrefix: /alertmanager                           # 👈
            externalUrl: http://vijaygiduthuri.in/alertmanager   # 👈
            resources:
              requests: {cpu: 25m,  memory: 64Mi}
              limits:   {cpu: 100m, memory: 128Mi}
```

**What changed compared to the template the repo originally shipped with:**

| Field                                  | Why                                                                                                                                            |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `grafana.ingress.enabled: false`       | We aren't using kube-prom-stack's bundled Ingress — we use a Traefik IngressRoute (added in Step 4) under the existing LB.                     |
| `grafana.grafana.ini.server.*`         | Tells Grafana its public URL is at `/grafana/`. Without this, its HTML asset paths point at `/` and the page breaks behind the sub-path.       |
| `grafana.additionalDataSources: [Loki]` | Wires Loki in as a Grafana datasource so log panels work without manual configuration after install.                                          |
| `prometheus.routePrefix: /prometheus`  | Mounts the Prometheus UI under `/prometheus`. Without it, Prometheus would assume `/` and asset paths break.                                  |
| `prometheus.externalUrl`               | The fully-qualified URL Prometheus emits in alert links + redirects. Must match what Traefik routes to.                                       |
| `alertmanager.routePrefix` + `externalUrl` | Same idea, for Alertmanager.                                                                                                              |
| `ignoreDifferences: StatefulSet.volumeClaimTemplates` | StatefulSet PVC templates are immutable after creation — same trap that hit `cloudkitchen` in Phase 4. Pre-empt it here.        |

> 🔑 **Admin password:** stays at the chart default (`admin / prom-operator`)
> for the first login. We change it via the Grafana UI in Step 5; we don't
> commit a password to git. If you need to rotate without a UI login,
> bump `grafana.adminPassword` in this file later.

---

## Step 2 — Update `argocd/apps/app-logging.yaml`

**File to edit:** [argocd/apps/app-logging.yaml](../../argocd/apps/app-logging.yaml)

The repo already ships this Application configured to install **loki-stack**
(Loki + Promtail) into the `logging` namespace, with `grafana: {enabled: false}`
(correctly defers Grafana to the monitoring stack).

**One thing to add:** an explicit `promtail.config.lokiAddress` override.

The chart's default lokiAddress is `http://<release-name>:3100/...` which
resolves to `http://logging:3100/...`. **But the actual Loki Service is
`logging-loki`** (the chart appends `-loki` to the release name on the Loki
side, NOT on the Promtail side). Without the override, Promtail logs flood
with:

```
dial tcp: lookup logging on 34.118.224.10:53: no such host
```

Add this inside the `promtail:` block:

```yaml
promtail:
  enabled: true
  config:
    lokiAddress: http://logging-loki:3100/loki/api/v1/push
```

That's the only change. Everything else stays.

---

## Step 3 — Apply both Applications

```bash
kubectl apply -f argocd/apps/app-monitoring.yaml
kubectl apply -f argocd/apps/app-logging.yaml
```

ArgoCD picks them up immediately (auto-sync). Watch:

```bash
kubectl -n argocd get app -w
# Wait until both monitoring + logging are Synced + Healthy.
```

**Expected boot timeline** on a 2-node `e2-standard-4` cluster:

| t       | What you should see                                                                |
| ------- | ---------------------------------------------------------------------------------- |
| 0:00    | Apply Applications; ArgoCD starts pulling charts                                   |
| 0:30    | `logging` namespace + Loki PVC + promtail pods created                             |
| 1:00    | `monitoring` namespace + kube-prom-stack CRDs (~30 of them) applied                |
| 1:30    | Prometheus + Alertmanager StatefulSets create PVCs, pods come up                   |
| 2:30    | All 7 monitoring pods Running 1/1                                                  |
| 3:00    | Grafana finishes its first-time setup + datasources load                           |

---

## Step 4 — Sanity-check services + fix the trap GKE always hits

GKE's control plane (etcd, kube-scheduler, kube-controller-manager,
kube-proxy, coredns) is **managed by Google** — none of it is scrape-able
from a worker node. The default kube-prom-stack tries to create Services
for those components anyway, in `kube-system`. Our AppProject
(`argocd/project.yaml`) whitelists only `cloudkitchen`, `monitoring`,
`logging`, `ingress`, `argocd` — so the sync **fails**:

```
namespace kube-system is not permitted in project 'cloudkitchen'
```

The fix is **already** in the manifest we apply in Step 1 — but if you
ever bump kube-prom-stack to a chart version that re-introduces the
defaults, you'll see this again. Disable in `helm.values:`:

```yaml
kubeEtcd:                  {enabled: false}
kubeScheduler:             {enabled: false}
kubeControllerManager:     {enabled: false}
kubeProxy:                 {enabled: false}
coreDns:                   {enabled: false}
```

Verify everything is up:

```bash
kubectl -n monitoring get pods
# alertmanager-kube-prometheus-alertmanager-0     2/2 Running
# kube-prometheus-operator-...                    1/1 Running
# monitoring-grafana-...                          3/3 Running
# monitoring-kube-state-metrics-...               1/1 Running
# monitoring-prometheus-node-exporter-...         1/1 Running   (one per node)
# prometheus-kube-prometheus-prometheus-0         2/2 Running

kubectl -n logging get pods
# logging-loki-0           1/1 Running
# logging-promtail-...     1/1 Running   (one per node)
```

And take note of the actual Service names — you'll need them for Step 5:

```bash
kubectl -n monitoring get svc
# monitoring-grafana                   ClusterIP   ...   80/TCP
# kube-prometheus-prometheus           ClusterIP   ...   9090/TCP
# kube-prometheus-alertmanager         ClusterIP   ...   9093/TCP
```

---

## Step 5 — Add Traefik IngressRoutes for `/grafana`, `/prometheus`, `/alertmanager`

We expose all three UIs under the **existing** Traefik LB (no new IPs, no
new DNS records). The cleanest way: three small standalone YAML files
applied directly with `kubectl apply`. No Helm templates, no chart wiring.

> ⚠️ Replace the two host values (`vijaygiduthuri.in` and `35.224.38.103`)
> below with **YOUR** domain and **YOUR** Traefik LB IP. Both appear in
> every match line; just find-and-replace before saving each file.

### 5a — `monitoring/ingressroutes/grafana.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/grafana`)
      kind: Rule
      services:
        - name: monitoring-grafana
          port: 80
```

### 5b — `monitoring/ingressroutes/prometheus.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: prometheus
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/prometheus`)
      kind: Rule
      services:
        - name: kube-prometheus-prometheus
          port: 9090
```

### 5c — `monitoring/ingressroutes/alertmanager.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/alertmanager`)
      kind: Rule
      services:
        - name: kube-prometheus-alertmanager
          port: 9093
```

### 5d — Apply all three

Save the three YAMLs above to local files and apply them in one shot:

```bash
kubectl apply -f monitoring/ingressroutes/grafana.yaml
kubectl apply -f monitoring/ingressroutes/prometheus.yaml
kubectl apply -f monitoring/ingressroutes/alertmanager.yaml

# Confirm:
kubectl -n monitoring get ingressroute
# NAME           AGE
# alertmanager   5s
# grafana        7s
# prometheus     6s
```

### Why these specific values?

| Field in YAML                  | Where it comes from                                                                                                                |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `namespace: monitoring`        | The kube-prometheus-stack chart deploys Grafana/Prometheus/Alertmanager Services into the `monitoring` namespace (Step 4 confirms). |
| `entryPoints: [web]`           | Plain HTTP on port 80. Phase 7 swaps this to `websecure` (HTTPS).                                                                  |
| `Host(`<your-domain>`)`        | Your production hostname. Browsers + curl-by-domain hit this matcher.                                                              |
| `Host(`<your-LB-IP>`)`         | The Traefik LB IP. Kept as a second host so `curl http://<LB-IP>/grafana/` keeps working for debugging.                            |
| `services.name`                | The Service name printed by `kubectl -n monitoring get svc`. Don't guess — copy from there.                                       |
| `services.port`                | Standard Grafana = 80, Prometheus = 9090, Alertmanager = 9093.                                                                     |

### Verify access

```bash
curl -sIL -o /dev/null -w "/grafana/      -> HTTP %{http_code}\n" "http://vijaygiduthuri.in/grafana/"
curl -sIL -o /dev/null -w "/prometheus/   -> HTTP %{http_code}\n" "http://vijaygiduthuri.in/prometheus/"
curl -sL "http://vijaygiduthuri.in/alertmanager/-/ready"   # prints "OK"
```

Open in browser:
- **Grafana:** http://vijaygiduthuri.in/grafana/  — login `admin / prom-operator`
- **Prometheus:** http://vijaygiduthuri.in/prometheus/
- **Alertmanager:** http://vijaygiduthuri.in/alertmanager/

> ⚠️ The default Grafana password is `prom-operator`. **Change it on first
> login** (User Icon → Profile → Change Password) and then optionally
> delete the chart's `admin-user`/`admin-password` Secret.

---

## Step 6 — Wire ServiceMonitors so Prometheus scrapes our 8 backend services

The `kube-prom-stack` Prometheus auto-discovers `ServiceMonitor` CRDs in
**every namespace** (we set `serviceMonitorSelectorNilUsesHelmValues: false`
in Step 1). So we just drop one ServiceMonitor in the cloudkitchen ns and
Prometheus picks it up — no chart wiring needed.

All 8 backend Services already share the label `app.kubernetes.io/part-of:
cloudkitchen` (set by the cloudkitchen helm chart's `<svc>-service.yaml`
templates) and expose `/metrics` on the `http` port. **One ServiceMonitor
selects all of them at once.**

### Save `monitoring/servicemonitor.yaml`

Copy this YAML to a local file as-is. No edits needed — it picks up every
cloudkitchen service automatically by label.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cloudkitchen-services
  namespace: cloudkitchen
  labels:
    # `release: monitoring` matches kube-prom-stack's default
    # serviceMonitorSelector if anyone tightens it later. Safe even when
    # the selector is wide-open (we set it that way in Step 1).
    release: monitoring
spec:
  # Only look at Services in the cloudkitchen namespace.
  namespaceSelector:
    matchNames:
      - cloudkitchen
  # Pick every Service that has this label. The chart sets it on all 8
  # backend services (auth, user, restaurant, menu, order, payment,
  # delivery, notification) but NOT on frontend/postgres/redis/nats —
  # so those don't get scraped (frontend is nginx, the others use their
  # own exporters if you ever need them).
  selector:
    matchLabels:
      app.kubernetes.io/part-of: cloudkitchen
  # Tell Prometheus: scrape the port NAMED 'http' on each matched
  # Service, hit the /metrics path, every 30 seconds.
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

### Apply it

```bash
kubectl apply -f monitoring/servicemonitor.yaml

# Confirm:
kubectl -n cloudkitchen get servicemonitor
# NAME                    AGE
# cloudkitchen-services   5s
```

### Why these specific values?

| Field                                                       | Why                                                                                                                                                                |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `namespace: cloudkitchen`                                   | ServiceMonitors live where the services they target live.                                                                                                          |
| `labels.release: monitoring`                           | Hedge against someone later setting `serviceMonitorSelector` on the Prometheus CR. With this label, the default `matchLabels: {release: monitoring}` matches. |
| `namespaceSelector.matchNames: [cloudkitchen]`              | Limits scraping to the cloudkitchen ns. Without this, Prometheus would consider Services with the same label in any namespace.                                     |
| `selector.matchLabels: {app.kubernetes.io/part-of: cloudkitchen}` | The label every backend Service in the chart carries. **Verify this on your cluster:** `kubectl -n cloudkitchen get svc auth-service -o yaml | grep -A 3 labels`. |
| `endpoints.port: http`                                      | The *name* of the Service port, **not** the number. Our chart names port 8080 as `http`. Look at your Services to confirm.                                         |
| `endpoints.path: /metrics`                                  | Where each Go service serves Prometheus metrics. Our chart's Gin middleware exposes them at this path automatically.                                               |
| `endpoints.interval: 30s`                                   | Scrape every 30 s. Sensible default; lower = more data + more load on each service.                                                                                |

### Verify scrape

```bash
curl -s "http://vijaygiduthuri.in/prometheus/api/v1/query?query=up%7Bnamespace%3D%22cloudkitchen%22%7D" \
  | python3 -m json.tool | head -40
```

Each of the 8 services should show `up = 1`. Confirm with a real query:

```bash
curl -s "http://vijaygiduthuri.in/prometheus/api/v1/query?query=sum%20by(service)%20(http_requests_total%7Bnamespace%3D%22cloudkitchen%22%7D)" \
  | python3 -m json.tool
```

Each service should report ~hundreds–thousands of `http_requests_total`
(those are mostly health/readiness probe hits accumulating over time).

---

## Step 7 — Smoke test in Grafana

1. Open **http://vijaygiduthuri.in/grafana/** and log in.
2. Top-left menu → **Connections → Data sources**:
   - **Prometheus** should be there (added by the chart automatically).
   - **Loki** should be there too (we added it via `additionalDataSources`
     in Step 1).
   - Click each and "Save & test" — both should turn green.
3. Top-left menu → **Dashboards → Browse**. Pick **"Kubernetes / Compute Resources / Namespace (Pods)"**:
   - Select Namespace = `cloudkitchen` in the top dropdown.
   - You should see CPU + memory usage panels for each of the 12 cloudkitchen pods.
4. Top-left menu → **Explore**. Switch the datasource to **Loki**:
   - Try query  `{namespace="cloudkitchen"}`  + Run.
   - You should see live logs streaming from every cloudkitchen pod.

If all three of those work, the monitoring stack itself is fully functional.
**Next step gives you per-service dashboards** — way more useful for daily
debugging than the generic kube-prom-stack dashboards.

---

## Step 8 — Per-service dashboards (one per microservice)

The chart ships ~20 generic Kubernetes dashboards (node/pod/namespace/etc.)
but nothing app-aware. To debug a single microservice you want **one focused
dashboard** with that service's RPS, errors, latency, pod CPU/mem, and live
logs — all on one screen.

Grafana auto-loads dashboards from any **ConfigMap labeled
`grafana_dashboard: "1"`** (the kube-prom-stack chart enables a "sidecar"
container that watches the cluster for this exact label). So the recipe is:

> Generate one ConfigMap per service, each containing the dashboard JSON,
> all labeled `grafana_dashboard: "1"`. `kubectl apply` them. Grafana
> auto-loads them within ~30 s.

### 8a — Generator script

The repo ships a small Python generator at
[monitoring/dashboards/generate.py](../../monitoring/dashboards/generate.py).
It takes one dashboard template (10 panels × 5 rows: stats, traffic, latency,
resources, logs) and emits 8 ConfigMaps — one per microservice — into a
single multi-doc YAML.

Run it (or skip — the repo already ships the generated output at
`monitoring/dashboards/cloudkitchen-dashboards.yaml`, so you can apply it
directly with the command in Step 8c):

```bash
cd monitoring/dashboards
python3 generate.py > cloudkitchen-dashboards.yaml
```

### 8b — Each dashboard has 10 panels

```
┌──────────────────────────────────────────────────────────────────────┐
│  Requests/sec  │  Error rate %  │  p95 latency  │  Pods up           │  Row 1: stats
├────────────────┴────────────────┼───────────────┴────────────────────┤
│  Requests/sec  by status code   │  Requests/sec  by path (top 5)     │  Row 2: traffic
├─────────────────────────────────┴────────────────────────────────────┤
│             HTTP latency  (p50 / p95 / p99)                          │  Row 3: latency
├─────────────────────────────────┬────────────────────────────────────┤
│  CPU usage  (cores, per pod)    │  Memory  (MiB, per pod)            │  Row 4: resources
├─────────────────────────────────┴────────────────────────────────────┤
│             Logs  (Loki, filtered to this service)                   │  Row 5: logs
└──────────────────────────────────────────────────────────────────────┘
```

Auto-refreshes every 30 s; default range is "last 1 hour".

The metric queries use the labels that the Gin Prometheus middleware
already exposes (`service`, `method`, `path`, `status`) plus the cAdvisor
`container_cpu_usage_seconds_total` / `container_memory_working_set_bytes`
filtered by pod-name prefix. The logs panel queries Loki with
`{namespace="cloudkitchen", app="<service>"}` — Promtail adds those labels
automatically.

### 8c — Apply

```bash
# From the repo root:
kubectl apply -f monitoring/dashboards/cloudkitchen-dashboards.yaml

# Sanity:
kubectl -n monitoring get cm -l grafana_dashboard=1
# 8 grafana-dashboard-<service> ConfigMaps, plus the ~20 kube-prom-stack ones
```

### 8d — Verify in Grafana

Wait ~30 s for the sidecar to load them, then either:

**Option A — query the Grafana API directly:**

```bash
GRAFANA_PWD=$(kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d)

curl -s -u "admin:${GRAFANA_PWD}" \
  "http://vijaygiduthuri.in/grafana/api/search?type=dash-db&query=CloudKitchen" \
  | python3 -m json.tool
```

You should see all 8 dashboards listed.

**Option B — open in browser:**

Each dashboard has a stable UID (`ck-<service>`):

| Service              | URL                                                                                  |
| -------------------- | ------------------------------------------------------------------------------------ |
| auth-service         | http://vijaygiduthuri.in/grafana/d/ck-auth-service/cloudkitchen-auth-service         |
| user-service         | http://vijaygiduthuri.in/grafana/d/ck-user-service/cloudkitchen-user-service         |
| restaurant-service   | http://vijaygiduthuri.in/grafana/d/ck-restaurant-service/cloudkitchen-restaurant-service |
| menu-service         | http://vijaygiduthuri.in/grafana/d/ck-menu-service/cloudkitchen-menu-service         |
| order-service        | http://vijaygiduthuri.in/grafana/d/ck-order-service/cloudkitchen-order-service       |
| payment-service      | http://vijaygiduthuri.in/grafana/d/ck-payment-service/cloudkitchen-payment-service   |
| delivery-service     | http://vijaygiduthuri.in/grafana/d/ck-delivery-service/cloudkitchen-delivery-service |
| notification-service | http://vijaygiduthuri.in/grafana/d/ck-notification-service/cloudkitchen-notification-service |

### 8e — How to customize (or add a new service)

The template lives in `generate.py`'s `dashboard()` function — modify panels
there, then re-run the generator. **To add a 9th service:** add its name
to the `SERVICES = [...]` list at the top and re-run.

If you change a dashboard, `kubectl apply` the regenerated YAML — Grafana
sidecar detects the ConfigMap change and reloads within ~30 s.

---

## Step 9 — (Optional) Alerting rules

Prometheus is collecting metrics; one more step turns "I have metrics" into
"I get paged when something breaks". The repo ships **[monitoring/prometheusrules.yaml](../../monitoring/prometheusrules.yaml)**
— a single `PrometheusRule` CRD containing 3 recording rules + 7 alert rules
covering the most common breakages.

### What fires

| Group                      | Rule / alert                       | Trigger                                                                                  | Severity   |
| -------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------- | ---------- |
| `cloudkitchen.http`        | `cloudkitchen:http_requests:rate5m`| Recording rule — `sum by (service) (rate(http_requests_total[5m]))`. Speeds up dashboards. | (recording)|
| `cloudkitchen.http`        | `cloudkitchen:http_5xx:rate5m`     | Recording rule — same shape, filtered to `status=~"5.."`.                                | (recording)|
| `cloudkitchen.http`        | `cloudkitchen:http_latency_p95`    | Recording rule — `histogram_quantile(0.95, …)`.                                          | (recording)|
| `cloudkitchen.http`        | `CloudKitchenHighErrorRate`        | >5% 5xx for 5 min on any service                                                         | warning    |
| `cloudkitchen.http`        | `CloudKitchenHighLatency`          | p95 latency > 1 s for 10 min                                                             | warning    |
| `cloudkitchen.kubernetes`  | `CloudKitchenPodNotReady`          | A cloudkitchen pod has been NotReady for 5 min                                           | warning    |
| `cloudkitchen.kubernetes`  | `CloudKitchenCrashLoopBackOff`     | A container restarted >3 times in 15 min                                                 | critical   |
| `cloudkitchen.kubernetes`  | `CloudKitchenDeploymentDegraded`   | A Deployment has fewer ready replicas than its spec for 10 min                           | warning    |
| `cloudkitchen.data`        | `CloudKitchenPostgresDown`         | `postgres-0` NotReady for 2 min                                                          | critical   |
| `cloudkitchen.data`        | `CloudKitchenNATSDown`             | `nats-0` NotReady for 2 min                                                              | critical   |

Recording rules are evaluated on the same interval as a scrape — once a
minute by default — and the resulting time series are queryable like any
metric. Use them in dashboards and other alert rules to keep query cost low.

### Apply

```bash
kubectl apply -f monitoring/prometheusrules.yaml

# Sanity: Prometheus picks it up automatically since the chart sets
# ruleSelectorNilUsesHelmValues: false (or via the `release: monitoring` label).
kubectl -n cloudkitchen get prometheusrule
# NAME                          AGE
# cloudkitchen-rules            5s
```

### Where alerts go

By default they fire into the cluster's **Alertmanager** (the
`/alertmanager` UI you set up in Step 5c). Wiring Alertmanager to a real
receiver — Slack, PagerDuty, email — is configured in the
`alertmanager.config:` block of `argocd/apps/app-monitoring.yaml`. Out of
scope for this phase; the alerts will sit in the Alertmanager UI until you
add a receiver.

---

## File index

Every standalone YAML this phase produced is collected under
**[monitoring/](../../monitoring/)** with a top-level README. Quick reference:

| File                                                             | Step | What                                                                                |
| ---------------------------------------------------------------- | ---- | ----------------------------------------------------------------------------------- |
| `argocd/apps/app-monitoring.yaml`                                | 1    | kube-prom-stack Helm values (Grafana sub-path, Loki datasource, GKE scraper toggles) |
| `argocd/apps/app-logging.yaml`                                   | 2    | loki-stack Helm values (Loki + Promtail; lokiAddress override)                       |
| `monitoring/ingressroutes/grafana.yaml`                          | 5    | Traefik route `/grafana/`    -> monitoring-grafana:80                               |
| `monitoring/ingressroutes/prometheus.yaml`                       | 5    | Traefik route `/prometheus/` -> kube-prometheus-prometheus:9090                     |
| `monitoring/ingressroutes/alertmanager.yaml`                     | 5    | Traefik route `/alertmanager/` -> kube-prometheus-alertmanager:9093                 |
| `monitoring/servicemonitor.yaml`                                 | 6    | ServiceMonitor selecting all 8 cloudkitchen backends                                 |
| `monitoring/dashboards/generate.py`                              | 8    | Python generator — emits 8 ConfigMaps (one per service)                              |
| `monitoring/dashboards/cloudkitchen-dashboards.yaml`             | 8    | Generated output — `kubectl apply -f` this                                          |
| `monitoring/prometheusrules.yaml`                                | 9    | Recording + alerting rules                                                          |

See [monitoring/README.md](../../monitoring/README.md) for the same table
plus the apply-all snippet.

---

## Troubleshooting

These are the real failures we hit on `cloudkitchen-dev-01` while landing
Phase 6, in order:

| Symptom                                                                                            | Cause                                                                                                                            | Fix                                                                                                                                                              |
| -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ArgoCD `monitoring` App stuck `OutOfSync / Missing`, retry messages say `namespace kube-system is not permitted in project` | kube-prom-stack tried to create scrape Services in `kube-system` for GKE-managed components.                                     | In `app-monitoring.yaml` set `kubeEtcd/kubeScheduler/kubeControllerManager/kubeProxy/coreDns: {enabled: false}`. They're unscrape-able on GKE anyway.            |
| `app-monitoring.yaml` edited but the live App's `helm.values:` still shows the old block            | `kubectl apply` ran against a partially-formed ArgoCD operation in retry state.                                                  | Clear the stuck operation, then re-apply: `kubectl -n argocd patch app monitoring --type merge -p '{"operation":null}'` then `kubectl apply -f .../app-monitoring.yaml` again. |
| Grafana datasource for Loki shows "Cannot connect"                                                  | URL `http://loki.logging.svc.cluster.local:3100` is wrong — the Service is `logging-loki`, not `loki`. The loki-stack chart adds the `-loki` suffix on the Loki Service. | Fix the Grafana datasource URL to `http://logging-loki.logging.svc.cluster.local:3100`. (We do this in Step 1.)                                                  |
| Promtail logs flood with `dial tcp: lookup logging on ...:53: no such host`                         | Same naming surprise as above. The chart's default `promtail.config.lokiAddress` is `http://<release>:3100/...`, which resolves to `http://logging:3100` — broken. | Override `promtail.config.lokiAddress: http://logging-loki:3100/loki/api/v1/push` in `app-logging.yaml`. (Step 2.)                                              |
| After changing `promtail.config.lokiAddress`, Promtail pods don't pick it up                        | The promtail config is stored in a **Secret** (not a ConfigMap); pods don't auto-restart on Secret change.                        | `kubectl -n logging rollout restart daemonset logging-promtail` after the new Secret is in place.                                                                |
| Prometheus + Alertmanager UIs return 404 even though `/grafana/` works                              | Both have `routePrefix` config that affects how they generate redirects. If `routePrefix` doesn't match the IngressRoute path, links break. | `app-monitoring.yaml` sets `prometheus.prometheusSpec.routePrefix: /prometheus` and `alertmanager.alertmanagerSpec.routePrefix: /alertmanager` (Step 1).         |
| `curl -I` (HEAD) returns 405 on Prometheus/Alertmanager UIs                                         | Those servers don't define HEAD. Same Gin-style quirk.                                                                            | Use GET (`curl` without `-I`). Real browser traffic uses GET.                                                                                                    |
| StatefulSets (Prometheus / Alertmanager / Loki) show permanent OutOfSync on `volumeClaimTemplates`  | StatefulSet PVC templates are **immutable** after creation — same trap that bit the cloudkitchen App.                            | Add `ignoreDifferences: [{group: apps, kind: StatefulSet, jsonPointers: [/spec/volumeClaimTemplates]}]` on the Application. (`app-monitoring.yaml` already does.) |

---

## Prometheus Queries (reference)

Once everything's running, here's a hand-picked set of PromQL queries that
exercise the metrics our setup actually exposes — useful for debugging or
just exploring.

Open the **Prometheus UI** at **http://vijaygiduthuri.in/prometheus/**,
paste a query into the *Expression* box, and click the **Execute** button
(the blue `▷` play icon on the right of the box). Results appear in the
**Table** tab below.

> **Tip:** after pasting, you must **click Execute** — pressing `Enter`
> alone doesn't run the query in the new Prometheus UI.

> **Note:** when a result row shows `{}` with a number next to it, the
> `{}` means "no labels" and the number IS the value. Scroll right if
> the table cuts it off.

CloudKitchen's Go services use the Gin Prometheus middleware, which
exposes a single shared metric `http_requests_total` with labels
`service`, `method`, `path`, `status`. So most queries filter by
`{service="..."}` rather than separate per-service metric names.

### Query 1 — Are all targets UP?

```promql
up
```

Every target Prometheus is scraping. Rows with value `1` are UP. Look for
`namespace="cloudkitchen"` rows in the table.

### Query 2 — All CloudKitchen targets

```promql
up{namespace="cloudkitchen"}
```

Filters to just the 8 backend services. All should show value `1`.

### Query 3 — Total HTTP requests per service

```promql
sum by (service) (http_requests_total{namespace="cloudkitchen"})
```

Lifetime request count for each service. Numbers grow steadily; health
probes (`/healthz`, `/readyz`) dominate when the cluster is idle.

### Query 4 — Per-route detail for auth-service

```promql
http_requests_total{service="auth-service"}
```

One row per `method`+`path`+`status` combo. Spot which endpoints are
most active and which return errors.

### Query 5 — Per-route detail for order-service

```promql
http_requests_total{service="order-service"}
```

Same shape, different service. Repeat for any of the 8 services.

### Query 6 — Request rate (requests / second) per service

```promql
sum by (service) (rate(http_requests_total{namespace="cloudkitchen"}[5m]))
```

Current throughput per service, averaged over the last 5 min. This is the
same series the per-service Grafana dashboards' "Requests/sec" panel uses.

### Query 7 — 5xx error rate (errors / second) per service

```promql
sum by (service) (rate(http_requests_total{namespace="cloudkitchen", status=~"5.."}[5m]))
```

Should be `0` or very low on a healthy cluster. Sudden non-zero values
mean something started failing.

> **If you see `Empty query result` / no rows** — that's the **healthy
> state**. PromQL's `rate(...)` returns no series at all when no 5xx
> response has been recorded in the last 5 minutes; summing over no
> series gives an empty result. To force a row to fire for testing,
> hit an invalid endpoint, e.g.
> `curl -X POST http://vijaygiduthuri.in/api/auth/login -d 'bogus'`.

### Query 8 — Error percentage per service

```promql
sum by (service) (rate(http_requests_total{namespace="cloudkitchen", status=~"5.."}[5m]))
  /
clamp_min(sum by (service) (rate(http_requests_total{namespace="cloudkitchen"}[5m])), 1e-9)
```

5xx as a fraction of total. Values are 0–1 (multiply by 100 for percent).
The `clamp_min` avoids divide-by-zero when a service has no traffic.

> Same caveat as Query 7 — when there are no 5xx responses anywhere, the
> numerator is empty and so is the result. **Empty result = no errors.**

### Query 9 — p95 latency per service (seconds)

```promql
histogram_quantile(0.95, sum by (le, service) (rate(http_request_duration_seconds_bucket{namespace="cloudkitchen"}[5m])))
```

The 95th-percentile response latency. Sub-100 ms is healthy for most
CRUD endpoints. Spikes indicate slow DB queries or upstream pressure.

### Query 10 — Top 5 busiest endpoints

```promql
topk(5, sum by (service, path) (rate(http_requests_total{namespace="cloudkitchen"}[5m])))
```

The 5 most-active routes across the whole platform right now. Health
probes usually dominate when there's no real traffic.

### Query 11 — Pod restart counts

```promql
kube_pod_container_status_restarts_total{namespace="cloudkitchen"}
```

One row per container. `0` is ideal. Non-zero values mean the kubelet had
to restart that container (OOM, crash, liveness probe failure). Useful
for spotting flapping pods.

### Query 12 — Deployment available replicas

```promql
kube_deployment_status_replicas_available{namespace="cloudkitchen"}
```

Available replicas per Deployment. Should match `spec.replicas`; if
lower, some pods are NotReady.

### Query 13 — CPU usage per pod (cores)

```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="cloudkitchen", container!="POD", container!=""}[5m]))
```

CPU consumption per pod, in **cores** (1.0 = one full vCPU). Watch for
pods near their `resources.limits.cpu`.

### Query 14 — Memory usage per pod (MiB)

```promql
sum by (pod) (container_memory_working_set_bytes{namespace="cloudkitchen", container!="POD", container!=""}) / 1024 / 1024
```

Working-set memory per pod, in MiB. Compare against the pod's memory
limit. If it crosses the limit, the kubelet OOM-kills the container.

### Query 15 — Active goroutines per service (Go-runtime health)

```promql
go_goroutines{namespace="cloudkitchen"}
```

Number of live goroutines per service. A **steadily growing number** is
a classic goroutine-leak signature — typically a missing `defer cancel()`
on a context.

### Query 16 — Go garbage collection time (seconds/sec)

```promql
rate(go_gc_duration_seconds_sum{namespace="cloudkitchen"}[5m])
```

Time spent in GC per second. High values (>0.1 s/s sustained) indicate
memory pressure — bump memory limits or hunt allocations.

### Query 17 — Active firing alerts

```promql
ALERTS{alertstate="firing"}
```

Same alerts shown in the Alertmanager UI, but as a Prometheus table.
If you applied `prometheusrules.yaml` (Step 9), the 7 alert rules feed
this view.

> **You'll always see at least one alert here named `Watchdog`** — that's
> the chart's built-in heartbeat alert. It's *designed* to always fire.
> Alertmanager treats it as a liveness signal: if Watchdog stops firing,
> something is wrong with your monitoring pipeline. So a healthy cluster
> shows exactly **1** row here: `Watchdog`. Anything else firing is a
> real signal.

### Query 18 — Recording rule we set up in Step 9

```promql
cloudkitchen:http_requests:rate5m
```

The pre-computed "requests / sec by service" recording rule. Faster than
re-computing the `rate()` each time — handy in dashboards or other rules.
Equivalent to Query 6.

---

## Alertmanager

Open the Alertmanager UI at **http://vijaygiduthuri.in/alertmanager/** to see:

- **Active alerts** (firing)
- **Silenced alerts**
- **Alert history**

If you applied `monitoring/prometheusrules.yaml` in Step 9, the 7 alert
rules are continuously evaluated. On a healthy cluster they all show
`inactive`.

To make an alert actually fire (for testing), the simplest trick is to
push a Deployment into CrashLoopBackOff for >15 min using an invalid
image:

```bash
# Use an image that doesn't exist — pod will fail to pull + restart in a loop
kubectl -n cloudkitchen set image deployment/auth-service-deployment \
  auth-service=nonexistent.example.com/bad-image:404

# Watch the alert state in Prometheus:
#   ALERTS{alertname="CloudKitchenCrashLoopBackOff"}
# After ~15 min of restarts it transitions: pending -> firing

# Revert when done:
kubectl -n cloudkitchen rollout undo deployment/auth-service-deployment
```

In production, Alertmanager's `config:` block (in
`argocd/apps/app-monitoring.yaml`) is where you wire firing alerts to a
real receiver — Slack, PagerDuty, email. Out of scope for this phase;
firing alerts just sit in the UI until you add a receiver.

---

➡️ **Next:** Phase 7 — HTTPS via cert-manager + Let's Encrypt (flip the
chart from HTTP entryPoint `web` to TLS-terminated `websecure`).
