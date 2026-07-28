# Phase 4 — ArgoCD Deploys the App (accessed via Traefik)

**Goal:** Install **ArgoCD** in the cluster, expose its UI through **Traefik**
(the ingress we set up in Phase 2 — *no port-forward needed*), then let ArgoCD
pull the Helm chart from your Git repo and deploy the entire CloudKitchen
platform. About **12 pods** come up.

**Time:** ~10 minutes.

---

## What & why

**ArgoCD** = a controller that watches your Git repo and keeps the cluster in
sync with it. No more `helm upgrade` from a laptop — just `git push`.

We already have Traefik + an AWS Load Balancer from Phase 2. We'll add a small
**IngressRoute** so ArgoCD's UI is reachable at:

```
http://<LB_DNS>/argocd
```

That's the "real-world" pattern — every UI in the cluster is reached through
the same ingress. We never port-forward in production.

---

## What this phase creates

```
   you / browser
        │
        ▼
   http://<LB_DNS>/argocd                 ← Phase 2's Traefik LB
        │
        ▼
   Traefik IngressRoute  (PathPrefix /argocd)
        │
        ▼
   argocd-server  (argocd namespace)
        │  reads
        ▼
   GitHub repo  ─── helm/cloudkitchen ───►  cloudkitchen namespace
                                            (12 pods: 8 svcs + UI + PG + Redis + NATS)
```

---

## ✅ Prerequisites

| Check | Command |
|-------|---------|
| Traefik installed + LB exists | `kubectl -n ingress get svc traefik` shows an EXTERNAL-IP |
| CI pushed images and bumped values.yaml | `git pull && grep image: helm/cloudkitchen/values.yaml \| head` |

Grab the LB hostname once — every step below uses it:
```bash
LB_DNS=$(kubectl -n ingress get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$LB_DNS"
```

---

## Step 1 — Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --set configs.params."server\.rootpath"=/argocd
```

The three flags matter:

| Flag | Why |
|------|-----|
| `server.service.type=ClusterIP` | We expose it through Traefik, not a separate LB |
| `server.insecure=true` | ArgoCD speaks plain HTTP internally — TLS is terminated at Traefik later (Phase 7) |
| `server.rootpath=/argocd` | Tells the UI/API "you live under `/argocd`" so links and assets resolve correctly |

Wait for it:
```bash
kubectl -n argocd rollout status deploy/argocd-server
```

---

## Step 2 — Get the admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
```
Copy that — you'll log in as `admin` with it.

> Change it on first login → User Info → Update Password.
> Then delete the bootstrap secret: `kubectl -n argocd delete secret argocd-initial-admin-secret`.

---

## Step 3 — Expose ArgoCD through Traefik

```bash
cat > /tmp/argocd-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - web                         # HTTP (port 80). Phase 7 switches this to websecure.
  routes:
    - match: PathPrefix(`/argocd`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
EOF
kubectl apply -f /tmp/argocd-ingressroute.yaml
```

That's it — Traefik now routes any request to `<LB_DNS>/argocd*` to the
`argocd-server` service. No host condition yet, so it works with the bare LB
hostname (Phase 5 wires up your real domain).

---

## Step 4 — Open the ArgoCD UI in your browser

```
http://<LB_DNS>/argocd
```
(replace `<LB_DNS>` with the value from the top of this page)

Login: `admin` + the password from Step 2.

You should see the empty ArgoCD dashboard.

---

## Step 5 — Capture your GitHub repo URL

Both YAMLs below need your real repo URL. Capture it once:

```bash
GH_REPO=$(git remote get-url origin)
echo "$GH_REPO"
# e.g.  https://github.com/<your-username>/cloudkitchen.git
```

> Private repo? In the ArgoCD UI → **Settings → Repositories → Connect Repo
> using HTTPS** → add a username + personal access token. Or make the repo
> public for now.

---

## Step 6 — Create the AppProject

An **AppProject** is a guardrail in ArgoCD: it tells the controller *which Git
repos may deploy, into which namespaces, and which Kubernetes kinds are
allowed*. Every Application below references it via `spec.project`.

Create and apply the file:

```bash
cat > /tmp/argocd-project.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: cloudkitchen
  namespace: argocd                    # AppProjects always live in the argocd ns
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: CloudKitchen platform project

  # Which Git repos may be deployed by Applications in this project
  sourceRepos:
    - $GH_REPO                                          # your repo
    - https://helm.traefik.io/traefik                   # Traefik chart repo
    - https://charts.jetstack.io                        # cert-manager chart repo
    - https://prometheus-community.github.io/helm-charts # kube-prom-stack
    - https://grafana.github.io/helm-charts             # Loki/Promtail/Grafana

  # Which clusters + namespaces may be deployed to
  destinations:
    - { server: https://kubernetes.default.svc, namespace: cloudkitchen }
    - { server: https://kubernetes.default.svc, namespace: monitoring }
    - { server: https://kubernetes.default.svc, namespace: logging }
    - { server: https://kubernetes.default.svc, namespace: ingress }
    - { server: https://kubernetes.default.svc, namespace: argocd }

  # Cluster-scoped kinds Argo is allowed to create (CRDs, ClusterRoles, etc.)
  clusterResourceWhitelist:
    - { group: "",                            kind: Namespace }
    - { group: apiextensions.k8s.io,          kind: CustomResourceDefinition }
    - { group: rbac.authorization.k8s.io,     kind: ClusterRole }
    - { group: rbac.authorization.k8s.io,     kind: ClusterRoleBinding }
    - { group: admissionregistration.k8s.io,  kind: ValidatingWebhookConfiguration }
    - { group: admissionregistration.k8s.io,  kind: MutatingWebhookConfiguration }
    - { group: storage.k8s.io,                kind: StorageClass }

  # Namespaced kinds — "*"/"*" allows everything inside the destination namespaces
  namespaceResourceWhitelist:
    - { group: "*", kind: "*" }
EOF
kubectl apply -f /tmp/argocd-project.yaml
```

**What each section does**

| Field | Plain-English meaning |
|---|---|
| `metadata.name: cloudkitchen` | The project name. Apps say `spec.project: cloudkitchen` to belong to it. |
| `metadata.namespace: argocd` | AppProjects always live in the `argocd` control-plane namespace. |
| `finalizers` | Tells Kubernetes "delete child Applications before deleting this project." |
| `sourceRepos` | A whitelist of Git/Helm repos. If you try to deploy from a repo not listed here, ArgoCD refuses. |
| `destinations` | Cluster + namespace pairs you're allowed to deploy to. We list the 5 platform namespaces of this project. |
| `clusterResourceWhitelist` | Cluster-scoped kinds Argo may create. Needed for add-ons that install CRDs/ClusterRoles (cert-manager, Prometheus operator, etc.). |
| `namespaceResourceWhitelist` | Namespaced kinds allowed inside destinations. `*/*` = anything common (Deployments, Services, Secrets, …). |

Verify:
```bash
kubectl -n argocd get appproject cloudkitchen
# Expect: NAME=cloudkitchen, AGE a few seconds
```

---

## Step 7 — Create the CloudKitchen Application

An **Application** is the actual "deploy this" instruction. It tells ArgoCD:
"render the Helm chart at `helm/cloudkitchen` from this repo and apply the
result to the `cloudkitchen` namespace, automatically."

```bash
cat > /tmp/argocd-app-cloudkitchen.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudkitchen
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: cloudkitchen                # belongs to the AppProject from Step 6

  # WHERE the manifests come from
  source:
    repoURL: $GH_REPO
    targetRevision: main               # the Git branch / tag / commit to track
    path: helm/cloudkitchen            # folder inside the repo (the Helm chart)
    # No valueFiles: the chart's own values.yaml is the source of truth.
    # CI bumps image: lines in that same file.

  # WHERE the manifests get applied
  destination:
    server: https://kubernetes.default.svc    # the cluster Argo is running on
    namespace: cloudkitchen                   # target namespace

  syncPolicy:
    automated:
      prune: true                     # remove resources deleted from git
      selfHeal: true                  # auto-correct out-of-band drift (kubectl edits)
    syncOptions:
      - CreateNamespace=true          # create the cloudkitchen ns if it doesn't exist
      - ServerSideApply=true          # safer apply for big CRD-bearing manifests
    retry:
      limit: 5
      backoff: { duration: 10s, factor: 2, maxDuration: 3m }
EOF
kubectl apply -f /tmp/argocd-app-cloudkitchen.yaml
```

**What each section does**

| Field | Plain-English meaning |
|---|---|
| `spec.project: cloudkitchen` | Belongs to the AppProject we just created — inherits its repo/namespace whitelists. |
| `source.repoURL` | The Git repo to clone. (For Helm-repo Applications you'd put the chart repo URL here instead.) |
| `source.targetRevision: main` | Which branch / tag / commit to follow. ArgoCD watches HEAD of this. |
| `source.path: helm/cloudkitchen` | The sub-folder in the repo that holds the chart (`Chart.yaml`, `values.yaml`, `templates/`). |
| `destination.server` | `https://kubernetes.default.svc` = "this cluster, internally". Multi-cluster setups list other API server URLs here. |
| `destination.namespace: cloudkitchen` | All rendered manifests are applied into this namespace. |
| `syncPolicy.automated.prune: true` | When you `git rm` a manifest, ArgoCD deletes it from the cluster too. |
| `syncPolicy.automated.selfHeal: true` | If someone runs `kubectl edit` on a managed object, ArgoCD reverts it. Real GitOps. |
| `syncOptions.CreateNamespace=true` | ArgoCD creates the `cloudkitchen` namespace if it isn't there yet. |
| `syncOptions.ServerSideApply=true` | Uses Kubernetes server-side apply — handles large CRDs and `last-applied` annotations cleanly. |
| `retry.*` | Exponential backoff on transient apply errors (up to 5 attempts, capped at 3 min). |

ArgoCD will now clone your repo → render `helm/cloudkitchen` with its
`values.yaml` (the one CI keeps current) → apply all **52 manifests**.

> 💡 **Want to use the in-repo files instead?** The same YAMLs live at
> `argocd/project.yaml` and `argocd/apps/app-cloudkitchen.yaml`. Edit the
> `repoURL` placeholder, commit, then `kubectl apply -f argocd/project.yaml`
> and `kubectl apply -f argocd/apps/app-cloudkitchen.yaml`. We use heredocs
> above purely so you can copy-paste-and-run from this guide.

ArgoCD will now clone → render the chart with its `values.yaml` (the one CI
keeps current) → apply all 52 manifests.

---

## Step 8 — Watch the sync

In the **UI**: click `cloudkitchen` → watch the resource tree fill in.

Or from the terminal:
```bash
kubectl -n cloudkitchen get pods -w
```

Expected end state — **12 pods Running 1/1**:
```
auth-service-deployment-...           1/1 Running
delivery-service-deployment-...       1/1 Running
menu-service-deployment-...           1/1 Running
notification-service-deployment-...   1/1 Running
order-service-deployment-...          1/1 Running
payment-service-deployment-...        1/1 Running
restaurant-service-deployment-...     1/1 Running
user-service-deployment-...           1/1 Running
frontend-deployment-...               1/1 Running
postgres-0                            1/1 Running
nats-0                                1/1 Running
redis-...                             1/1 Running
```

---

## ✅ Verify

```bash
# 1. ArgoCD app is Synced + Healthy
kubectl -n argocd get app cloudkitchen \
  -o jsonpath='{.status.sync.status}/{.status.health.status}'; echo
# Expect:  Synced/Healthy

# 2. PVCs bound (this is what the EBS CSI driver was added for in Phase 1)
kubectl -n cloudkitchen get pvc
# Expect: data-postgres-0 and data-nats-0 -> Bound

# 3. ArgoCD UI reachable via Traefik (the realtime way)
curl -I "http://$LB_DNS/argocd" | head -1
# Expect: HTTP/1.1 200 OK   (or a 307 redirect to /argocd/)

# 4. App is reachable from inside the cluster (no DNS yet — that's Phase 5)
kubectl run -n cloudkitchen --rm -it --image=curlimages/curl curltest -- \
  curl -s auth-service:8080/healthz
# Expect: {"status":"ok","service":"auth-service"}
```

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| ArgoCD UI loads but assets 404 / blank page | `server.rootpath=/argocd` wasn't applied | `helm upgrade argocd argo/argo-cd -n argocd --reuse-values --set configs.params."server\.rootpath"=/argocd && kubectl -n argocd rollout restart deploy argocd-server` |
| `curl http://$LB_DNS/argocd` → 404 | IngressRoute missing or wrong path | `kubectl -n argocd get ingressroute` — should list `argocd`; re-apply Step 3 |
| App shows `Unknown` / can't reach repo | Repo is private without creds | UI → Settings → Repositories → add HTTPS creds |
| PVCs stuck `Pending` | EBS CSI not running | `kubectl -n kube-system get pods | grep ebs-csi` — confirm Phase 1 addon |
| `ImagePullBackOff` on app pods | ECR auth from nodes failed | the node IAM role already has `AmazonEC2ContainerRegistryReadOnly`; verify the image string in `helm/cloudkitchen/values.yaml` matches what's in ECR |
| `CrashLoopBackOff` on a service | Postgres not ready / migration error | `kubectl -n cloudkitchen logs <pod>` — postgres-0 must come up first |
| Same image tag deploys despite CI bump | values.yaml not committed back | `git log --oneline -- helm/cloudkitchen/values.yaml` should show the CI bot commits |
| NATS pod `CrashLoopBackOff`, logs print the `nats-server --help` text | A non-existent CLI flag was passed (e.g. `--max_file_store=2GB` — that's a **config-file** option, not a flag) | Edit `helm/cloudkitchen/templates/nats-statefulset.yaml`, remove the bogus arg, `helm upgrade` |
| App pods Running but no events flow; `kubectl logs auth-service-...` shows `broker unavailable, events disabled` from boot time | Service started while NATS was still crash-looping. The **old** soft-fail broker init kept the pod alive with publishes silently dropped — even after NATS recovered, the pod never reconnected | Fixed in code (auth/user/restaurant now `os.Exit(1)` if NATS is unreachable so the kubelet restarts them until NATS is healthy). If you ever see it again: `kubectl -n cloudkitchen rollout restart deploy auth-service user-service restaurant-service` |
| New orders fail with `no available agent` after a few test runs | delivery-service only seeded 3 agents and they all got "stuck" on previous test orders. JetStream `MaxDeliver=2` then drops the redelivery | Fixed in migration (`delivery-service/migrations/0001_init.sql` now seeds 10 agents). Hot fix in a live cluster: `kubectl -n cloudkitchen exec postgres-0 -- psql -U postgres -d cloudkitchen -c 'UPDATE delivery.agents SET available=TRUE;'` |

---

## 📋 Phase 4 cheatsheet

```bash
# Install ArgoCD with sub-path config
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --set configs.params."server\.rootpath"=/argocd

# Admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# IngressRoute (Traefik routes /argocd -> argocd-server)
kubectl apply -f /tmp/argocd-ingressroute.yaml

# Open in browser
LB_DNS=$(kubectl -n ingress get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Open: http://$LB_DNS/argocd"

# Deploy the app  (apply the two heredoc files from Steps 6 & 7)
kubectl apply -f /tmp/argocd-project.yaml
kubectl apply -f /tmp/argocd-app-cloudkitchen.yaml
kubectl -n cloudkitchen get pods -w

# Force a resync
kubectl -n argocd patch app cloudkitchen --type merge -p '{"operation":{"sync":{}}}'
```

---

## 🎉 What you accomplished

- ✅ ArgoCD installed and **reachable via Traefik** at
  `http://<LB_DNS>/argocd` — no port-forward.
- ✅ Your Git repo is the **source of truth** — every push reconciles.
- ✅ All 12 CloudKitchen pods deployed, PVCs bound, services Up.

➡️ **Next:** [Phase 5 — Traefik DNS + GoDaddy](05-traefik-dns-and-godaddy.md)
