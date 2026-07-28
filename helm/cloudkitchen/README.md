# CloudKitchen — Helm Chart

The single umbrella Helm chart that deploys the **entire CloudKitchen food‑delivery
platform** (9 application workloads + PostgreSQL, Redis and NATS) into one
Kubernetes namespace.

---

## What is Helm?

Helm is a **package manager for Kubernetes** — just like `apt` is for Ubuntu or
`npm` is for Node.js.

Without Helm, deploying an application on Kubernetes means hand‑writing and applying
dozens of individual YAML files (Deployments, Services, ConfigMaps, Secrets, …) one
by one. To change something you'd have to find and edit each file separately.

**Helm bundles all those YAML files into a single package called a "Chart"** and
lets you template them with variables, so one chart can deploy a whole platform.

---

## Why Use Helm? (Advantages)

| Advantage | What it means in simple terms |
|-----------|-------------------------------|
| **Single command deploy** | Deploy all 52 Kubernetes resources with one command instead of 52 `kubectl apply` commands |
| **Easy upgrades** | Change a value, run one command — Helm figures out what changed and updates only that |
| **Rollback in seconds** | If an upgrade breaks something, one command takes you back to the previous working revision |
| **Reusable templates** | Write the YAML once with variables (`{{ .Values.authService.image }}`) and reuse it |
| **Version history** | Helm tracks every deployment as a numbered revision — you can see what changed and when |
| **Atomic deployments** | If any resource fails, Helm can roll the whole release back automatically |
| **Config in one place** | Every tunable setting lives in `values.yaml` — no hunting through manifests |

---

## What Does This Chart Deploy?

The complete **CloudKitchen** platform: 8 Go microservices + a React frontend, plus
their backing data stores, all in the **`cloudkitchen`** namespace.

### Workloads (9 app + 3 data stores)

| # | Component | Type | Port | Purpose |
|---|-----------|------|------|---------|
| 1 | **frontend** | React app (nginx) | 8080 | The user interface served to the browser |
| 2 | **auth-service** | Go API | 8080 | Registration, login, JWT issuance, RBAC roles |
| 3 | **user-service** | Go API | 8080 | User profiles and delivery addresses |
| 4 | **restaurant-service** | Go API | 8080 | Restaurant creation and listing |
| 5 | **menu-service** | Go API | 8080 | Categories, menu items, food search (Redis‑cached) |
| 6 | **order-service** | Go API | 8080 | Cart (Redis) and order placement / tracking |
| 7 | **payment-service** | Go API | 8080 | Mock payment processing |
| 8 | **delivery-service** | Go API | 8080 | Delivery assignment and status updates |
| 9 | **notification-service** | Go API | 8080 | Email/notification log (consumes events) |
| 10 | **PostgreSQL** | StatefulSet | 5432 | One database (`cloudkitchen`) with a **schema per service** |
| 11 | **Redis** | Deployment | 6379 | Caches menu search results and stores carts |
| 12 | **NATS (JetStream)** | StatefulSet | 4222 / 8222 | Async event bus between services (client / HTTP monitoring) |

> Every backend service listens on **8080** and exposes `/healthz` (liveness),
> `/readyz` (readiness) and `/metrics` (Prometheus). The frontend's non‑root nginx
> also listens on **8080**.

### Kubernetes resources created (52 total)

| Resource Type | Count | Purpose |
|---------------|-------|---------|
| Deployments | 10 | 8 backend services + frontend + Redis |
| StatefulSets | 2 | PostgreSQL and NATS (with persistent volumes for JetStream FileStorage) |
| Services | 12 | In‑cluster networking (9 app + postgres + redis + nats) |
| ConfigMaps | 8 | Non‑secret env per backend service (DB host/port/schema, Redis addr, NATS URL, …) |
| Secrets | 9 | 8 service secrets (DB/JWT) + postgres credentials (NATS runs unauthenticated in this chart) |
| HorizontalPodAutoscalers | 9 | Auto‑scale the 8 backends + frontend on CPU/memory |
| IngressRoute (Traefik) | 1 | Routes every public path to the right service + TLS |

---

## Chart Structure

```
helm/cloudkitchen/
├── Chart.yaml              # Chart metadata (name, version, description)
├── values.yaml             # ALL configurable values (images, replicas, ports, secrets…)
├── README.md               # This file
└── templates/              # One explicit file per resource per service
    ├── auth-service-deployment.yaml      auth-service-service.yaml
    ├── auth-service-configmap.yaml       auth-service-secret.yaml
    ├── auth-service-hpa.yaml
    │   ... (same 5 files for user / restaurant / menu / order /
    │        payment / delivery / notification) ...
    ├── frontend-deployment.yaml          frontend-service.yaml   frontend-hpa.yaml
    ├── postgres-statefulset.yaml         postgres-service.yaml   postgres-secret.yaml
    ├── redis-deployment.yaml             redis-service.yaml
    ├── nats-statefulset.yaml             nats-service.yaml
    ├── ingressroute.yaml                 # Traefik routing for all paths + TLS
    └── NOTES.txt                         # printed after install
```

Templates are written **explicitly** (one file per resource per service) rather than
with `range` loops, so each file is easy to read and reason about.

> PostgreSQL, Redis and NATS are **explicit manifests in this chart**, not Bitnami
> subchart dependencies — so `helm dependency build` is **not** required.

---

## Understanding `values.yaml`

Configuration is **flat** — one block per service, keyed in camelCase. Example:

```yaml
namespace: cloudkitchen

authService:
  deploymentname: auth-service-deployment
  servicename: auth-service          # in-cluster DNS name other services call
  image: <ecr>/cloudkitchen/auth-service:latest   # full image (CI bumps the tag)
  replicas: 2
  port: 8080
  schema: auth                       # PostgreSQL schema this service owns
  hpa: auth-service-autoscaler
  minReplicas: 2
  maxReplicas: 5
# ... userService, restaurantService, menuService, orderService,
#     paymentService, deliveryService, notificationService, frontend

postgres: { image, port, storage, storageClass }
redis:    { image, port }
nats:     { image, clientPort, monitorPort, storage, storageClass }
db:       { host: postgres, port, name: cloudkitchen, sslmode }
ingress:  { enabled, domain, entryPoint, tlsSecretName, clusterIssuer }
secrets:  { dbUser, dbPassword, jwtSecret, jwtExpiry, redisPassword }
```

**Schema‑per‑service:** there is one PostgreSQL database, `cloudkitchen`. Each service's
ConfigMap sets a different `DB_SCHEMA` (auth → `auth`, user → `users`, order → `orders`,
…) while sharing the same `DB_NAME`. Each service creates and migrates its own schema on
startup.

**Common tasks**

- **Set/disable a service** — edit its `replicas`/`minReplicas`, or comment out its block.
- **Set an image tag** — edit the service's `image:` string (CI does this automatically).
- **Turn ingress/TLS off** (for port‑forward testing) — `ingress.enabled: false`.

> This is **the** values file ArgoCD renders with and CI patches. There are **no**
> per‑environment override files (`environments/`).

---

## Ingress routing (Traefik)

A single `IngressRoute` routes `Host(cloudkitchen.example.com)` paths to services:

| Path | Service |
|------|---------|
| `/api/auth` | auth-service |
| `/api/users` | user-service |
| `/api/restaurants` | restaurant-service |
| `/api/restaurants/<id>/{menu,categories,items}`, `/api/menu` | menu-service *(higher priority)* |
| `/api/cart`, `/api/orders` | order-service |
| `/api/payments` | payment-service |
| `/api/deliveries` | delivery-service |
| `/api/notifications` | notification-service |
| `/` (catch‑all) | frontend |

TLS uses the secret `cloudkitchen-tls`. **Note:** the cert‑manager `Certificate` that
produces this secret is created **manually** during EKS HTTPS setup (it is intentionally
not part of this chart).

---

## ⚠️ How this chart is actually deployed (GitOps)

On EKS, **ArgoCD** deploys this chart automatically from Git — see [`argocd/`](../../argocd).
The CI pipeline ([`.github/workflows/ci.yaml`](../../.github/workflows/ci.yaml)) builds
images, pushes to ECR, and commits new image tags into `helm/cloudkitchen/values.yaml`;
ArgoCD then syncs. **CI never runs `helm upgrade`.**

The `helm` commands below are therefore for **local testing, manual operations, and
learning** — not the production deploy path.

---

## Complete Command Reference

### 1. Create the namespace (first‑time)

```bash
kubectl create namespace cloudkitchen
```
Creates the dedicated namespace all chart resources live in. Run before `helm install`
if it doesn't exist (or use `--create-namespace`).

### 2. Install the chart (first‑time deployment)

```bash
helm install cloudkitchen ./helm/cloudkitchen -n cloudkitchen
```
- `helm install` — deploy this chart for the first time
- `cloudkitchen` — the **release name** you give this deployment
- `./helm/cloudkitchen` — path to the chart folder
- `-n cloudkitchen` — target namespace

### 3. Upgrade an existing deployment

```bash
helm upgrade cloudkitchen ./helm/cloudkitchen -n cloudkitchen
```
Helm compares current state with the new templates and applies only the differences;
Kubernetes does a zero‑downtime rolling update.

### 4. Install or upgrade in one command (recommended for scripts)

```bash
helm upgrade --install cloudkitchen ./helm/cloudkitchen -n cloudkitchen --create-namespace
```
`--install` means "install if absent, upgrade if present". `--create-namespace` makes
the namespace if needed. Safest for automation.

### 5. Override values at deploy time

```bash
helm upgrade --install cloudkitchen ./helm/cloudkitchen -n cloudkitchen \
  --set frontend.replicas=3 \
  --set secrets.jwtSecret=super-secret-value
```
`--set key=value` overrides a value from `values.yaml` without editing the file.

### 6. Use a custom values file

```bash
helm upgrade --install cloudkitchen ./helm/cloudkitchen -n cloudkitchen \
  -f my-overrides.yaml
```
`-f` layers an extra values file on top of `values.yaml` (e.g. a local‑testing file with
`ingress.enabled=false`).

### 7. Release status

```bash
helm status cloudkitchen -n cloudkitchen
```
Shows whether the release is deployed/failed/upgrading, the last deploy time, and versions.

### 8. List releases

```bash
helm list -n cloudkitchen
```
```
NAME          NAMESPACE     REVISION  STATUS    CHART
cloudkitchen  cloudkitchen  3         deployed  cloudkitchen-0.2.0
```

### 9. Deployment history

```bash
helm history cloudkitchen -n cloudkitchen
```
Lists every revision with status, so you know what changed and when.

### 10. Roll back to a specific revision

```bash
helm rollback cloudkitchen 1 -n cloudkitchen
```
Reverts all changed resources to revision `1` (get the number from `helm history`).

### 11. Roll back to the previous revision

```bash
helm rollback cloudkitchen -n cloudkitchen
```
No number = go back one revision. Quick fix when the latest upgrade misbehaves.

### 12. Preview without deploying (dry run)

```bash
helm upgrade --install cloudkitchen ./helm/cloudkitchen -n cloudkitchen --dry-run=client
```
Renders and validates the templates **without** touching the cluster.

### 13. Render the final YAML (offline)

```bash
helm template cloudkitchen ./helm/cloudkitchen -n cloudkitchen
```
Outputs the fully‑substituted YAML Kubernetes would receive. Works without a cluster —
great for debugging templates.

### 14. Validate the chart

```bash
helm lint ./helm/cloudkitchen
```
Checks `Chart.yaml`, `values.yaml` and templates for mistakes. Run after editing templates.

### 15. Uninstall (delete everything)

```bash
helm uninstall cloudkitchen -n cloudkitchen
```
Removes all resources this chart created. ⚠️ This deletes the running app. **PostgreSQL
and NATS PVCs may persist** (StatefulSet PVCs are not auto‑deleted) — remove them with
`kubectl delete pvc -n cloudkitchen -l app=postgres` (and `-l app=nats` for the JetStream
volume) if you really want the data gone.

### 16. Uninstall but keep history

```bash
helm uninstall cloudkitchen -n cloudkitchen --keep-history
```
Deletes resources but keeps the release history so you can `helm rollback` later.

### 17. Inspect the values used

```bash
helm get values cloudkitchen -n cloudkitchen          # only overridden values
helm get values cloudkitchen -n cloudkitchen --all    # every value, incl. defaults
```

### 18. Inspect the deployed manifest

```bash
helm get manifest cloudkitchen -n cloudkitchen
```
Shows the exact YAML applied during the last deployment (what's actually running).

---

## Quick Reference Card

```bash
# First-time setup
kubectl create namespace cloudkitchen
helm install cloudkitchen ./helm/cloudkitchen -n cloudkitchen

# Day-to-day
helm upgrade cloudkitchen ./helm/cloudkitchen -n cloudkitchen     # deploy changes
helm status  cloudkitchen -n cloudkitchen                          # check status
helm list    -n cloudkitchen                                       # list releases
helm history cloudkitchen -n cloudkitchen                          # view history

# Safety
helm lint ./helm/cloudkitchen                                      # validate chart
helm template cloudkitchen ./helm/cloudkitchen -n cloudkitchen     # preview YAML
helm upgrade --install cloudkitchen ./helm/cloudkitchen --dry-run=client  # dry run

# Recovery
helm rollback cloudkitchen -n cloudkitchen                         # roll back last change
helm rollback cloudkitchen 1 -n cloudkitchen                       # roll back to revision 1

# Cleanup
helm uninstall cloudkitchen -n cloudkitchen                        # delete everything
```

---

## Security defaults

- **Pods** run as non‑root: `runAsNonRoot: true`, `runAsUser: 65532` (backends) / `101`
  (frontend nginx), with `fsGroup`.
- **Containers** set `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`.
- **Secrets** (DB password, `JWT_SECRET`) come from templated Kubernetes
  Secrets. The committed defaults are **for local/dev only** — in real clusters supply
  them via a secrets manager / External Secrets, never commit production values.
- **TLS** is terminated at Traefik using the `cloudkitchen-tls` secret (created manually
  via cert‑manager on EKS).

---

## Current Deployment Info (EKS)

- **Cluster:** `kubectl config current-context` to check
- **Region:** `us-east-1`
- **Image registry (ECR):** `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cloudkitchen/<service>`
- **Ingress controller:** Traefik (namespace `ingress`)
- **Access URL:** `https://cloudkitchen.example.com` (once DNS + TLS are set up)
- **GitOps:** ArgoCD watches this repo and syncs the chart automatically — see `argocd/`

### Connect to the cluster

```bash
aws eks update-kubeconfig --name <CLUSTER_NAME> --region us-east-1
kubectl get pods -n cloudkitchen
```

### Quick local smoke test (no ingress)

```bash
helm upgrade --install cloudkitchen ./helm/cloudkitchen -n cloudkitchen \
  --create-namespace --set ingress.enabled=false
kubectl -n cloudkitchen port-forward svc/frontend-service 8080:80
# open http://localhost:8080
```
