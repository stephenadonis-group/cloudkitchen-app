# Phase 2 — Traefik Ingress Controller

**Goal:** Install **Traefik** (our ingress controller) in the cluster, expose it
through an **AWS Network Load Balancer**, and verify the Traefik CRDs
(`IngressRoute`, `Middleware`, `TLSStore`) are installed. The chart deploys an
`IngressRoute` later — it needs Traefik running first.

**Time:** ~5 minutes.

---

## What is Traefik & why do we use it?

**Traefik** is a cloud-native edge router / ingress controller that turns
Kubernetes resources into routing rules. Other options exist (nginx-ingress,
AWS ALB Controller), but Traefik gives us:

| Feature | Why we care |
|---------|-------------|
| Native **`IngressRoute` CRD** | Cleaner than the legacy `Ingress` API, supports priority + middleware composition |
| **Built-in Let's Encrypt** support | (We'll actually use cert-manager in Phase 7, but it's available) |
| **Dynamic config** reload | No restart on rule changes |
| **Dashboard** | Free, useful for debugging routes |
| **Middlewares** | Easy CORS, basic auth, rate limit, headers |

---

## What this phase creates

```
                 internet
                    │
                    ▼
        ┌──────────────────────┐
        │  AWS Network LB      │   (auto-created by the LoadBalancer Service)
        └──────────┬───────────┘
                   ▼
            ┌──────────────┐
            │   Traefik    │   (Deployment, namespace = ingress)
            │  pods (web)  │
            └──────┬───────┘
                   │   (CRDs: IngressRoute, Middleware, TLSStore…)
                   ▼
        ┌──────────────────────┐
        │  cloudkitchen ns     │   (App workloads — deployed in Phase 4)
        └──────────────────────┘
```

---

## ✅ Prerequisites

| Check | Command | Expected |
|-------|---------|----------|
| Phase 1 done | `kubectl get nodes` | 2 nodes Ready |
| `helm` installed | `helm version` | v3.x |
| Cluster auth working | `kubectl get ns` | lists `default`, `kube-system`, … |

---

## Step 1 — Add the Traefik Helm repo

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
```
**What this does:**
- `helm repo add` registers an external chart repository.
- `helm repo update` fetches the latest chart index from every registered repo.

You can list available chart versions with:
```bash
helm search repo traefik/traefik --versions | head
```

---

## Step 2 — Create the `ingress` namespace

```bash
kubectl create namespace ingress
```
**What this does:** Creates a dedicated namespace so Traefik's pods, services,
and ConfigMaps don't mix with your app's `cloudkitchen` namespace.

---

## Step 3 — Install Traefik

Create a small values file so the choices are explicit (and reviewable):

```bash
cat > /tmp/traefik-values.yaml <<'EOF'
# Expose Traefik via an AWS Network Load Balancer (NLB) on ports 80 + 443.
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: instance
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing

# Entrypoints (Traefik's name for "listening ports").
ports:
  web:
    port: 80
    expose: true
    exposedPort: 80
    protocol: TCP
  websecure:
    port: 443
    expose: true
    exposedPort: 443
    protocol: TCP

# Mark this as the default ingress class.
ingressClass:
  enabled: true
  isDefaultClass: true

# Run 2 replicas for resilience.
deployment:
  replicas: 2

# Built-in dashboard (we'll port-forward to it for now; not exposed publicly).
ingressRoute:
  dashboard:
    enabled: true

# Sensible resource defaults.
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
EOF
```
**What this does:** Writes a minimal Traefik values file. Key bits:

| Field | Meaning |
|---|---|
| `service.type: LoadBalancer` + AWS annotations | EKS will auto-provision an **NLB** as soon as the Service is created |
| `ports.web` / `ports.websecure` | Two entrypoints — port 80 (`web`) for HTTP, port 443 (`websecure`) for HTTPS (Phase 7) |
| `ingressClass.isDefaultClass: true` | Lets you write `Ingress` resources without specifying a class |
| `ingressRoute.dashboard.enabled: true` | Enables the Traefik UI dashboard on path `/dashboard/` |

Now install:

```bash
helm install traefik traefik/traefik \
  -n ingress \
  -f /tmp/traefik-values.yaml
```
**What this does:**
- `helm install` deploys a new release named `traefik`.
- `-n ingress` targets the namespace we created.
- `-f /tmp/traefik-values.yaml` layers our custom values over the chart defaults.

Expected output ends with:
```
NAME: traefik
LAST DEPLOYED: …
NAMESPACE: ingress
STATUS: deployed
```

---

## Step 4 — Watch the AWS Load Balancer appear

```bash
kubectl -n ingress get svc traefik -w
```
**What this does:** Watches the Traefik Service in real time.
You'll see `EXTERNAL-IP` first as `<pending>`, then in 1–3 minutes change to an
AWS NLB hostname like `aXXXXXX-YYYYYY.elb.us-east-1.amazonaws.com`. Press Ctrl-C
when it appears.

Save that hostname (we'll call it `$LB_DNS`) — Phase 5 points your domain at it.

```bash
LB_DNS=$(kubectl -n ingress get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$LB_DNS"
```

---

## Step 5 — Verify everything

```bash
# 1. Traefik pods Running
kubectl -n ingress get pods
# Expect 2 traefik-... pods, status Running, READY 1/1.

# 2. Traefik CRDs installed (these are what the cloudkitchen chart's
#    ingressroute.yaml depends on)
kubectl get crd | grep traefik.io
# Expect at least: ingressroutes.traefik.io, middlewares.traefik.io,
#                  tlsstores.traefik.io, serverstransports.traefik.io, …

# 3. LB is reachable (no app yet, so Traefik 404s — that's success)
curl -I "http://$LB_DNS"
# Expect: HTTP/1.1 404 Not Found  (Traefik says: "no route matches" — perfect)

# 4. Quick look at the dashboard (optional)
kubectl -n ingress port-forward svc/traefik 9000:9000 &
# browse: http://localhost:9000/dashboard/   (note the trailing slash)
```

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `helm install` errors with `kind cluster context not found` | wrong kubeconfig context | `kubectl config current-context` should be your EKS cluster |
| Traefik Service stays `<pending>` forever | EKS can't create the LB (subnet tags? IAM?) | Check `kubectl -n ingress describe svc traefik` events; the VPC public subnets must have `kubernetes.io/role/elb=1` (the Terraform vpc module sets this) |
| `Error: no matches for kind "IngressRoute"` later | Traefik CRDs not installed | The chart installs them by default. Confirm with `kubectl get crd ingressroutes.traefik.io` |
| Pods CrashLoopBackOff | Resource limits too low | Increase memory/cpu in `/tmp/traefik-values.yaml`, `helm upgrade traefik … -f /tmp/traefik-values.yaml` |
| 404 from `$LB_DNS` | **Expected** — no IngressRoutes yet. Apps come in Phase 4 | continue |

---

## 📋 Phase 2 cheatsheet

```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update
kubectl create namespace ingress
helm install traefik traefik/traefik -n ingress -f /tmp/traefik-values.yaml

# Watch the LB
kubectl -n ingress get svc traefik -w
LB_DNS=$(kubectl -n ingress get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Tweak settings later
helm upgrade traefik traefik/traefik -n ingress -f /tmp/traefik-values.yaml

# Remove if you want to redo this phase
helm uninstall traefik -n ingress
```

---

## 🎉 What you accomplished

- ✅ Traefik running in the `ingress` namespace, exposed via an AWS NLB.
- ✅ Traefik CRDs installed — the chart's `IngressRoute` will be acceptable.
- ✅ A public DNS hostname you can already hit (it 404s because no routes yet).

➡️ **Next:** [Phase 3 — GitHub Actions CI](03-github-actions-cicd.md)
