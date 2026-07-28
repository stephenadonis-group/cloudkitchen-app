# Phase 2 — Traefik Ingress Controller (GCP)

**Goal:** Install **Traefik** in the cluster, expose it through a **GCP TCP
LoadBalancer** (single static IP), and verify the Traefik CRDs
(`IngressRoute`, `Middleware`, `TLSStore`) are installed. ArgoCD and the
CloudKitchen app both deploy `IngressRoute` objects in later phases — they
need Traefik already running.

**Time:** ~5 minutes (provisioning the GCP LB is the slow step, ~60 s).

This is the **GCP counterpart** of [docs/eks/02-traefik-ingress.md](../eks/02-traefik-ingress.md).
Same chart, same flags — only the underlying LB differs.

| Concern              | EKS                                            | GKE (this doc)                                           |
| -------------------- | ---------------------------------------------- | -------------------------------------------------------- |
| LB the chart spawns  | NLB (via `LoadBalancer` Service)               | GCP TCP LoadBalancer (regional, single IP)               |
| LB cost              | ~$18/mo + bytes                                | ~$18/mo + bytes (essentially identical pricing)          |
| Special annotations  | `service.beta.kubernetes.io/aws-load-balancer-type: nlb` | None — GKE defaults are good                    |
| Namespace            | `ingress`                                      | **`traefik`** (per project convention; keep them apart)  |

---

## What is Traefik & why we use it

**Traefik** is a cloud-native edge router. Other options exist (nginx-ingress,
ingress-nginx, GKE's built-in ingress controller), but Traefik gives us:

| Feature                                  | Why we care                                                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Native **`IngressRoute` CRD**            | Cleaner than the standard `Ingress` API; supports priority, regex matchers, middleware composition         |
| **Built-in Let's Encrypt** support       | (We use cert-manager in Phase 7 because it's more flexible, but the option is there)                       |
| **Dynamic config reload**                | Change an IngressRoute → routes update in <1s, no restart                                                  |
| **Free dashboard**                       | Visualize all routes, see live request counts, debug 404s without reading kubectl                          |
| **Middlewares**                          | CORS, basic-auth, rate-limit, strip-prefix, add-header — composable, declared in YAML                      |

---

## What this phase creates

```
                  internet
                     │
                     ▼
        ┌──────────────────────────┐
        │  GCP TCP LoadBalancer    │   (provisioned by the `LoadBalancer` Service)
        │  single static IP (Geo:  │
        │   regional, us-central1) │
        └────────────┬─────────────┘
                     ▼
              ┌──────────────┐
              │   Traefik    │   (Deployment, namespace = traefik, 2 replicas)
              │    pods      │
              └──────┬───────┘
                     │  (CRDs: IngressRoute, Middleware, TLSStore, ServersTransport, …)
                     ▼
        ┌─────────────────────────────────────────────┐
        │  cloudkitchen ns + argocd ns               │
        │  (App workloads + ArgoCD UI — Phase 4+)    │
        └─────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

| Need                                      | How to check                                                                       |
| ----------------------------------------- | ---------------------------------------------------------------------------------- |
| Phase 1 done (GKE cluster up, kubeconfig) | `kubectl get nodes` shows 2 Ready                                                  |
| `helm` v3                                 | `helm version`                                                                     |
| Internet access to Helm Hub               | `helm repo add traefik https://traefik.github.io/charts && helm repo update` works |

---

## Step 1 — Install Traefik via Helm

We install into a dedicated `traefik` namespace (not `ingress` like the EKS
doc shows) — keeps controller workloads separate from app workloads, and
matches what's already running on `cloudkitchen-dev-01`.

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik

helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set service.type=LoadBalancer \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true \
  --set ingressRoute.dashboard.enabled=true \
  --set deployment.replicas=2 \
  --set 'ports.web.expose.default=true' \
  --set 'ports.web.exposedPort=80' \
  --set 'ports.websecure.expose.default=true' \
  --set 'ports.websecure.exposedPort=443' \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=256Mi \
  --wait --timeout=5m
```

What each flag does:

| Flag                                          | Why                                                                                                                                  |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `service.type=LoadBalancer`                   | Tells Kubernetes to provision a real cloud LB. GKE auto-creates a GCP TCP LoadBalancer + an external IP.                             |
| `ingressClass.enabled=true` + `isDefaultClass=true` | Creates the `IngressClass` so Traefik can claim plain-`Ingress` objects too. Default class = unmarked Ingresses go to Traefik.    |
| `ingressRoute.dashboard.enabled=true`         | Auto-creates an `IngressRoute` for the Traefik dashboard at `/dashboard/` + `/api`.                                                  |
| `deployment.replicas=2`                       | Two Traefik Pods across nodes → if one node drains, ingress doesn't go down.                                                         |
| `ports.web.expose.default=true`               | Port 80 (HTTP) is exposed on the LB.                                                                                                 |
| `ports.websecure.expose.default=true`         | Port 443 (HTTPS) is exposed on the LB. Phase 7 actually puts a cert on it.                                                           |
| `resources.requests/limits`                   | Small but realistic. Two replicas, ~256 MiB total memory.                                                                            |

> 📌 **The `traefik` namespace is intentional.** If you put it in `ingress`
> instead, half the docs in this repo (and the saved IngressRoute manifests)
> will quietly fail to bind. Use `traefik`.

---

## Step 2 — Verify

```bash
# Helm release
helm list -n traefik
# NAME    NAMESPACE  REVISION  STATUS    CHART          APP VERSION
# traefik traefik    1         deployed  traefik-40.x.x v3.x.x

# Pods
kubectl -n traefik get pods
# Expect 2 traefik-... pods Running 1/1

# Service: external IP shows up after ~60 s once GCP provisions the LB
kubectl -n traefik get svc traefik
# NAME     TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)                     AGE
# traefik  LoadBalancer   10.30.x.y     35.224.38.103  80:32xxx/TCP,443:32xxx/TCP  90s

# CRDs installed
kubectl get crd | grep traefik.io
# expect: ingressroutes.traefik.io, middlewares.traefik.io,
#         tlsoptions.traefik.io, tlsstores.traefik.io,
#         serverstransports.traefik.io, ...
```

Save the IP — every later doc references it:
```bash
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Traefik LB IP: $LB_IP"
```

---

## Step 3 — Quick HTTP probe (no IngressRoute yet → expect 404)

```bash
curl -sI -o /dev/null -w "%{http_code}\n" "http://${LB_IP}/"
# 404 — Traefik is up but no route matches. That's correct for this phase;
# Phase 4 (ArgoCD-applied chart) and Phase 4d (ArgoCD UI) install the routes.
```

A `404` here proves the LB → Traefik path works. If you instead see
`Connection refused` or `Connection timed out`, the LB hasn't finished
provisioning — re-check `kubectl get svc -n traefik` in ~60 s.

---

## Step 4 — Reach the Traefik dashboard

The dashboard is exposed at `/dashboard/` + `/api` by the auto-created
IngressRoute. **Trailing slash is required** (Traefik convention):

```bash
curl -sI -o /dev/null -w "%{http_code}\n" "http://${LB_IP}/dashboard/"
# Expect: 200
```

Open `http://<LB_IP>/dashboard/` in a browser. You'll see:
- **Routers** — all configured `IngressRoute`s, with the matchers and middlewares
- **Services** — backend Kubernetes Services Traefik forwards to
- **Middlewares** — installed middlewares (none until later phases)

⚠️ **Production-only note:** in real deployments, lock the dashboard behind
auth (basic-auth middleware) or restrict it to the bastion's IP. For a
learning cluster it's fine open.

---

## Step 5 — Make sure the LB IP is stable (or live with rotation)

The IP that GKE assigns to a `LoadBalancer` Service is **ephemeral** by
default — if you ever delete and recreate the Traefik Service, GKE picks a
new IP and your DNS goes stale.

To **promote the current ephemeral IP to a static reservation** so DNS
records survive:

```bash
# 1. Grab the IP Traefik already has. This is the IP we want to keep —
#    NOT a brand-new one from GCP's pool.
LB_IP=$(kubectl -n traefik get svc traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Current Traefik IP: ${LB_IP}"

# 2. Reserve it as a static address. The `--addresses=${LB_IP}` flag is
#    CRITICAL — it tells GCP "promote THIS specific IP to static". Without
#    that flag, GCP creates a brand-new random IP from the pool and your
#    existing LoadBalancer keeps using the old ephemeral one — see the
#    "doesn't bind" trap below.
gcloud compute addresses create traefik-lb-ip \
  --addresses="${LB_IP}" \
  --region=us-central1 \
  --project=<your-project-id>

# 3. Verify the address flipped to IN_USE
gcloud compute addresses describe traefik-lb-ip \
  --region=us-central1 \
  --format='table(name,address,status)'
# Expect:  traefik-lb-ip  <LB_IP>  IN_USE

# 4. Pin the Traefik Service spec to it (so a Service recreate would
#    re-claim the same IP instead of picking a new ephemeral one)
helm upgrade traefik traefik/traefik \
  --namespace traefik --reuse-values \
  --set service.loadBalancerIP="${LB_IP}"
```

> ⚠️ **The "doesn't bind" trap** — if you ran `gcloud compute addresses
> create` **without** `--addresses=${LB_IP}`, GCP gave you a brand-new
> random IP (not the one Traefik is using). Then `helm upgrade --set
> service.loadBalancerIP=<new-random-ip>` silently no-ops because **GKE
> cannot reassign an existing LoadBalancer to a different reserved IP**
> via a spec change — the Service is already bound to its current IP.
> Fix: `gcloud compute addresses delete traefik-lb-ip` to release the
> wrong reservation, then re-run the block above with the `--addresses=`
> flag set to the IP Traefik actually has.

This step is optional but strongly recommended. Without it, anything that
recreates the Service (e.g. `helm uninstall traefik`, a chart-level
rewrite, a Service deletion by mistake) gives you a new IP, breaking the
GoDaddy A record set in Phase 5.

---

## Step 6 — What's next

You now have a working ingress controller. The next phases add **what to
route**:

- **Phase 3** — CI pipeline that builds + pushes images to Artifact Registry
- **Phase 4** — ArgoCD installation + the cloudkitchen Application — which
  applies the **IngressRoutes** for the app (`/`, `/api/*`) and ArgoCD UI
  (`/argocd`) under this same Traefik LB
- **Phase 5** — point a DNS name at this LB IP
- **Phase 7** — cert-manager + Let's Encrypt → swap `http://` for `https://`

---

## Troubleshooting

| Symptom                                                                       | Likely cause                                                                                                  | Fix                                                                                                                                                                                                |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kubectl -n traefik get svc traefik` shows `EXTERNAL-IP <pending>` for >5 min | GCP LB still provisioning, OR the cluster's network can't talk to the LB controller (private cluster + no NAT) | Check `kubectl -n traefik describe svc traefik` events. If "no firewall rule for health check" — your firewall module is missing the GCP health-check ranges (`130.211.0.0/22`, `35.191.0.0/16`).  |
| `curl http://<LB_IP>/` → `Connection refused`                                 | Pods aren't Ready (failing health checks) so the LB has no backends                                           | `kubectl -n traefik get pods` — Pods should be 1/1 Running. If not, `kubectl -n traefik describe pod <name>` and `kubectl -n traefik logs <name>` to see the start-up error.                       |
| `curl http://<LB_IP>/dashboard/` → 404                                        | Dashboard `IngressRoute` wasn't installed (you set `ingressRoute.dashboard.enabled=false`)                    | `helm upgrade traefik traefik/traefik -n traefik --reuse-values --set ingressRoute.dashboard.enabled=true`                                                                                          |
| Cluster IngressRoutes match but requests get 404 anyway                       | Your `IngressRoute` lives in a namespace Traefik can't see (older Traefik versions required `providers.kubernetesCRD.namespaces`) | Traefik 3.x defaults to watching all namespaces. Confirm with `kubectl -n traefik logs deploy/traefik | grep -i namespace`. If restricted, set `providers.kubernetesCRD.allowCrossNamespace=true`.   |
| `helm install` fails with `cannot patch ... resource mapping not found`       | Traefik CRDs from an older install are still in the cluster (from a previous run / different namespace)       | `kubectl get crd | grep traefik.io` — delete the stale ones with `kubectl delete crd <name>`. **Warning:** this deletes IngressRoutes that depend on them — only do this on a clean cluster.        |
| GCP says "quota: external IPs in use"                                         | You've hit the 8/region static IP quota                                                                       | Either request a quota increase, or use the auto-assigned ephemeral IP for now.                                                                                                                    |

---

➡️ **Next:** [Phase 3 — GitHub Actions CI](03-github-actions-cicd.md)
