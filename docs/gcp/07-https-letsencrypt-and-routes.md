# Phase 7 — HTTPS with Let's Encrypt + Path-Routed Sub-Apps (GCP)

**Goal:** Install **cert-manager**, mint a free **Let's Encrypt** certificate
for your domain, flip the chart to **HTTPS** (`websecure` entryPoint), and
move ArgoCD + Grafana + Prometheus + Alertmanager over to HTTPS too — so
you finish with:

```
https://vijaygiduthuri.in                — the app UI
https://vijaygiduthuri.in/argocd         — ArgoCD UI
https://vijaygiduthuri.in/grafana        — Grafana
https://vijaygiduthuri.in/prometheus     — Prometheus
https://vijaygiduthuri.in/alertmanager   — Alertmanager
```

**Time:** ~15 minutes (most of it Let's Encrypt issuing the cert).

This is the **GCP counterpart** of [docs/eks/07-https-letsencrypt-and-routes.md](../eks/07-https-letsencrypt-and-routes.md).
Same architecture; only the install paths + service names differ.

---

## What & why

After Phase 5 you have HTTP working. Modern browsers warn on HTTP and many
auth flows (Grafana login form autofill, ArgoCD OAuth, etc.) refuse to run
over HTTP. So HTTPS is the next step.

**cert-manager** is the standard Kubernetes operator that talks to ACME
servers (Let's Encrypt, ZeroSSL, internal CA) to obtain + renew TLS
certificates automatically. We use Let's Encrypt's free public service
with the **HTTP-01** challenge: cert-manager creates a temporary IngressRoute
serving a token at `http://<your-domain>/.well-known/acme-challenge/…`,
Let's Encrypt fetches it to prove you control the domain, and emits a
90-day cert (renewed automatically at day 75).

```
        ┌──────────────────────────────────────────────────────┐
        │  cert-manager (cert-manager ns)                       │
        │   ┌─────────────────────────────────────────┐         │
        │   │  ClusterIssuer "letsencrypt-prod"        │         │
        │   └─────────────────────────────────────────┘         │
        │                       │                              │
        │                       ▼                              │
        │   Certificate "cloudkitchen-tls"  in cloudkitchen ns │
        │   → produces Secret "cloudkitchen-tls"                │
        └──────────────────────┬───────────────────────────────┘
                               │
                               ▼  (the Secret holds tls.crt + tls.key)
        Traefik IngressRoute (chart-rendered, ingress.tls=true)
        references secretName: cloudkitchen-tls  →  HTTPS!
```

---

## ⚠️ Heads-up — the Certificate is created manually

The cert-manager `Certificate` resource is **NOT** in the cloudkitchen
helm chart on purpose. The cert's lifecycle is tied to your **domain**,
not the chart's release lifecycle — keeping it separate makes it safer
to re-deploy the chart without churning the cert (Let's Encrypt
rate-limits real-cert issuance to 5/week per registered domain).

So in this phase we **apply the Certificate manifest by hand** from
`security/cert-manager/certificate.yaml`.

---

## ✅ Prerequisites

| Check | How |
|---|---|
| Phase 5 done (your domain resolves to the LB IP) | `dig +short vijaygiduthuri.in` → returns your LB IP (e.g. `136.112.45.103`) |
| Phase 6 done (monitoring + logging) | `kubectl -n monitoring get pods` healthy |
| Port 80 reachable from the internet | Used by Let's Encrypt for HTTP-01 challenge. Traefik listens on 80 by default. |
| `kubectl` + `helm` work | `kubectl get nodes` and `helm version` succeed |

> 💡 **Why port 80 has to stay open** — even after we flip the app to
> HTTPS, we keep port 80 reachable so cert-manager can solve the HTTP-01
> challenge during renewals. Traefik will redirect normal traffic from
> `:80` → `:443` (configured in Step 4) while still passing
> `/.well-known/acme-challenge/…` through to cert-manager's solver.

---

## Step 1 — Install cert-manager

Two equally valid paths. Pick one.

### Option A — As an ArgoCD Application (matches Phase 6 pattern)

Two paste-and-go blocks below. Both files in the repo
([argocd/project.yaml](../../argocd/project.yaml) +
[argocd/apps/app-cert-manager.yaml](../../argocd/apps/app-cert-manager.yaml))
are intentionally kept in a generic placeholder state — the YAMLs below are
the **working Phase 7 versions** with the three AppProject guardrails already
baked in:

| Fix baked into the YAML below | Without it… |
|---|---|
| `cert-manager` added to AppProject `destinations:` | ArgoCD rejects sync — *"namespace cert-manager is not permitted in project 'cloudkitchen'"* |
| App's `destination.namespace: cert-manager` (was `ingress`) | cert-manager would install into the wrong ns; Traefik already owns `traefik` ns |
| `global.leaderElection.namespace: cert-manager` in Helm values | Chart writes leader-election `Role` / `RoleBinding` into `kube-system` by default → AppProject blocks it |

#### 1a — Update the AppProject (adds the `cert-manager` destination)

```bash
cat > /tmp/argocd-project.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: cloudkitchen
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: CloudKitchen platform project (microservices + platform add-ons)
  sourceRepos:
    - https://github.com/vijaygiduthuri/cloudkitchen-app.git
    - https://helm.traefik.io/traefik
    - https://charts.jetstack.io
    - https://prometheus-community.github.io/helm-charts
    - https://grafana.github.io/helm-charts
  destinations:
    - {server: https://kubernetes.default.svc, namespace: cloudkitchen}
    - {server: https://kubernetes.default.svc, namespace: monitoring}
    - {server: https://kubernetes.default.svc, namespace: logging}
    - {server: https://kubernetes.default.svc, namespace: ingress}
    - {server: https://kubernetes.default.svc, namespace: argocd}
    - {server: https://kubernetes.default.svc, namespace: cert-manager}   # 👈 Phase 7 addition
  clusterResourceWhitelist:
    - {group: "",                           kind: Namespace}
    - {group: apiextensions.k8s.io,         kind: CustomResourceDefinition}
    - {group: rbac.authorization.k8s.io,    kind: ClusterRole}
    - {group: rbac.authorization.k8s.io,    kind: ClusterRoleBinding}
    - {group: admissionregistration.k8s.io, kind: ValidatingWebhookConfiguration}
    - {group: admissionregistration.k8s.io, kind: MutatingWebhookConfiguration}
    - {group: storage.k8s.io,               kind: StorageClass}
    - {group: scheduling.k8s.io,            kind: PriorityClass}
    - {group: apiregistration.k8s.io,       kind: APIService}
  namespaceResourceWhitelist:
    - {group: "*", kind: "*"}
  sourceNamespaces:
    - argocd
EOF
kubectl apply -f /tmp/argocd-project.yaml
```

Verify the AppProject now whitelists `cert-manager`:

```bash
kubectl -n argocd get appproject cloudkitchen \
  -o jsonpath='{range .spec.destinations[*]}{.namespace}{"\n"}{end}'
# Expect 6 lines — cloudkitchen, monitoring, logging, ingress, argocd, cert-manager
```

#### 1b — Create the cert-manager ArgoCD Application

```bash
cat > /tmp/app-cert-manager.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: cloudkitchen
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.15.3
    helm:
      values: |
        installCRDs: true
        replicaCount: 2
        # 👇 keeps leader-election Roles/RoleBindings out of kube-system
        #    (kube-system is NOT in the AppProject's destinations list).
        global:
          leaderElection:
            namespace: cert-manager
        extraArgs:
          - --dns01-recursive-nameservers-only
          - --dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true     # CRDs > 256 KB annotation limit → needs SSA
EOF
kubectl apply -f /tmp/app-cert-manager.yaml
```

#### 1c — Wait for ArgoCD to roll cert-manager out

ArgoCD auto-syncs, creates the `cert-manager` namespace, and installs the
chart. Wait until all cert-manager pods are Ready (~70 s):

```bash
kubectl -n argocd get app cert-manager -w
# Wait until: Synced  Healthy   (Ctrl-C once it does)

kubectl -n cert-manager get pods
# Expect 4 pods Running 1/1:
#   cert-manager-*             (×2 replicas)
#   cert-manager-cainjector-*
#   cert-manager-webhook-*
```

> 💡 **Why the repo files differ from the inline YAMLs**
> The repo's `argocd/project.yaml` + `argocd/apps/app-cert-manager.yaml`
> are kept in a generic placeholder state on purpose — so the earlier
> phases of this doc set stay clean for any learner. The blocks above
> are the working Phase 7 versions. After Phase 7, you can either leave
> the repo files as-is (ArgoCD reconciles against the cluster `Application`
> object, not the file in git, so this is fine) **or** copy the inline
> YAMLs into the repo + commit + push to keep git == cluster.

### Option B — Direct `helm install` (simpler one-off, no ArgoCD)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set replicaCount=2 \
  --set global.leaderElection.namespace=cert-manager \
  --wait --timeout=5m
```

Either way: 3 cert-manager pods Running + 5 CRDs installed
(`certificates`, `certificaterequests`, `clusterissuers`, `issuers`,
`orders`, `challenges`).

```bash
kubectl get crd | grep cert-manager.io
kubectl -n cert-manager get pods
```

---

## Step 2 — Apply the Let's Encrypt ClusterIssuer

One ClusterIssuer, one apply. Uses Let's Encrypt's production API + the
HTTP-01 challenge via Traefik.

> 📧 Email is hard-coded to `vijaygiduthuri@gmail.com`. Let's Encrypt only
> uses it to warn you before a cert expires — change in the heredoc below
> if you want notices going to a different inbox.

### Apply

```bash
cat > /tmp/clusterissuer.yaml <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: vijaygiduthuri@gmail.com         # 👈 used for expiry notices
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
kubectl apply -f /tmp/clusterissuer.yaml
```

### Verify

```bash
kubectl get clusterissuer
# NAME               READY   AGE
# letsencrypt-prod   True    30s
```

If `READY=False`, the most likely cause is cert-manager pods aren't ready
yet (Step 1 wait). Re-run `kubectl -n cert-manager get pods` and confirm
all 4 are Running, then check:

```bash
kubectl describe clusterissuer letsencrypt-prod | tail -10
```

---

## Step 3 — Create the Certificate

One Certificate manifest, one apply, one wait. The domain is hard-coded
to `vijaygiduthuri.in`.

### Apply

```bash
cat > /tmp/certificate.yaml <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cloudkitchen-tls
  namespace: cloudkitchen
spec:
  secretName: cloudkitchen-tls          # the Secret the chart will read
  duration: 2160h                        # 90 days (Let's Encrypt default)
  renewBefore: 360h                      # renew 15 days before expiry
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt-prod               # the ClusterIssuer from Step 2
    kind: ClusterIssuer
    group: cert-manager.io
  commonName: vijaygiduthuri.in
  dnsNames:
    - vijaygiduthuri.in
EOF
kubectl apply -f /tmp/certificate.yaml
```

### Wait + verify

```bash
kubectl -n cloudkitchen get certificate cloudkitchen-tls -w
# Wait for READY=True. Typically 30-60 seconds.
```

Verify it's a real Let's Encrypt cert (issuer `Let's Encrypt`, not anything
else):

```bash
kubectl -n cloudkitchen get secret cloudkitchen-tls \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -dates
# Expect:  issuer=C=US, O=Let's Encrypt, CN=YE1 (or R10/R11 — Let's Encrypt's intermediate CAs)
#          notBefore=...    notAfter=...
```

### If issuance is stuck

```bash
# Look at the Certificate's status conditions:
kubectl -n cloudkitchen describe certificate cloudkitchen-tls | tail -30

# Look at the active HTTP-01 challenge:
kubectl -n cloudkitchen get challenges
kubectl -n cloudkitchen describe challenge <name> | tail -30

# Most common cause: port 80 not reachable from the public internet so
# Let's Encrypt can't fetch http://your-domain/.well-known/acme-challenge/...
# Try it yourself:
curl -v http://vijaygiduthuri.in/.well-known/acme-challenge/test
# Expect: 404 (the challenge token doesn't exist yet — but the request reached Traefik).
# Connection refused / timeout = port 80 blocked upstream.
```

> 💡 **Heads up on Let's Encrypt rate limits**
> Let's Encrypt's production API limits you to **5 duplicate certificates
> per week per registered domain**. For a single-host learning project
> that's plenty — but if you're iterating and might hit it, you can switch
> to their staging API temporarily by changing the issuer's `server:` URL
> to `https://acme-staging-v02.api.letsencrypt.org/directory`. Staging is
> unlimited but emits certs your browser won't trust.

---

## Step 4 — Flip the cloudkitchen IngressRoute to HTTPS

The `cloudkitchen` IngressRoute is the only Phase 7 resource that's
rendered by an ArgoCD-managed chart (`path: helm/cloudkitchen`,
`syncPolicy.automated.selfHeal: true`). If we just `kubectl apply` an
HTTPS version, ArgoCD would revert it back to HTTP within ~30 s.

So we do it in two paste-and-go blocks: **(4a)** tell ArgoCD to stop
auto-healing this one app, then **(4b)** apply the HTTPS-flavor
IngressRoute directly with kubectl.

> ⚠️ **Trade-off you're making by skipping git**
> The cloudkitchen App will show **OutOfSync** in the ArgoCD UI from now
> on (red badge) because git still says `tls: false, entryPoint: web`
> while the cluster says `websecure + tls`. That's expected — git is no
> longer the source of truth for this resource. To restore the GitOps
> flow later, see the "Restore GitOps for cloudkitchen App" callout
> below this step.

### 4a — Disable ArgoCD auto-sync on the cloudkitchen App

```bash
kubectl -n argocd patch application cloudkitchen --type=json \
  -p='[{"op":"remove","path":"/spec/syncPolicy/automated"}]'

# Verify automated sync is gone (should print nothing — the field is removed):
kubectl -n argocd get application cloudkitchen \
  -o jsonpath='{.spec.syncPolicy.automated}{"\n"}'
```

### 4b — Apply the HTTPS-flavor IngressRoute

All 10 chart-rendered routes are preserved exactly as the chart produces
them — only `entryPoints: [web]` becomes `[websecure]` and a `tls:` block
is added at the bottom:

```bash
cat > /tmp/cloudkitchen-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: cloudkitchen
  namespace: cloudkitchen
  labels:
    app: cloudkitchen
spec:
  entryPoints:
    - websecure                                            # 👈 was: web
  routes:
    # --- menu sub-paths (higher priority) ---
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathRegexp(`^/api/restaurants/[^/]+/(menu|categories|items)`)
      kind: Rule
      priority: 200
      services:
        - {name: menu-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/menu`)
      kind: Rule
      priority: 200
      services:
        - {name: menu-service, port: 8080}
    # --- one rule per service ---
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/auth`)
      kind: Rule
      priority: 100
      services:
        - {name: auth-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/users`)
      kind: Rule
      priority: 100
      services:
        - {name: user-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/restaurants`)
      kind: Rule
      priority: 100
      services:
        - {name: restaurant-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && (PathPrefix(`/api/cart`) || PathPrefix(`/api/orders`))
      kind: Rule
      priority: 100
      services:
        - {name: order-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/payments`)
      kind: Rule
      priority: 100
      services:
        - {name: payment-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/deliveries`)
      kind: Rule
      priority: 100
      services:
        - {name: delivery-service, port: 8080}
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/api/notifications`)
      kind: Rule
      priority: 100
      services:
        - {name: notification-service, port: 8080}
    # --- frontend catch-all (lowest priority) ---
    - match: (Host(`vijaygiduthuri.in`) || Host(`136.112.45.103`)) && PathPrefix(`/`)
      kind: Rule
      priority: 1
      services:
        - {name: frontend-service, port: 80}
  tls:                                                     # 👈 NEW block
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/cloudkitchen-ingressroute.yaml
```

### Verify

```bash
kubectl -n cloudkitchen get ingressroute cloudkitchen \
  -o jsonpath='{.spec.entryPoints} {.spec.tls.secretName}{"\n"}'
# Expect:  ["websecure"] cloudkitchen-tls
```

### Smoke test

```bash
curl -sI "https://vijaygiduthuri.in/" | head -1
# Expect: HTTP/2 200

curl -s "https://vijaygiduthuri.in/api/restaurants" | head -c 200 ; echo
# Expect: JSON array of restaurants

# All 10 microservice routes still work — try a couple more:
curl -s -o /dev/null -w "HTTP %{http_code}\n" "https://vijaygiduthuri.in/api/auth/health"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "https://vijaygiduthuri.in/api/menu"
```

🎉 The app is now on **HTTPS with a real browser-trusted certificate**.

> ℹ️ **Restore GitOps for the cloudkitchen App later (optional)**
> When you're ready to put git back in charge of the chart, do this once:
>
> ```bash
> # 1. Update git so the chart renders HTTPS too:
> sed -i 's/^  tls: false$/  tls: true/'                  helm/cloudkitchen/values.yaml
> sed -i 's/^  entryPoint: web$/  entryPoint: websecure/' helm/cloudkitchen/values.yaml
> git add helm/cloudkitchen/values.yaml
> git commit -m "phase 7: flip cloudkitchen ingress to HTTPS (post-hoc)"
> git push origin main
>
> # 2. Re-enable ArgoCD auto-sync. Because git now matches the live state,
> #    selfHeal will NOT revert anything:
> kubectl -n argocd patch application cloudkitchen --type=merge -p '{
>   "spec": {"syncPolicy": {"automated": {"prune": true, "selfHeal": true}}}
> }'
> ```

---

## Step 5 — Move ArgoCD / Grafana / Prometheus / Alertmanager to HTTPS

Right now those four UIs are reachable at `http://vijaygiduthuri.in/argocd/`,
`/grafana/`, `/prometheus/`, `/alertmanager/`. To move them to HTTPS, two
things change:

1. Each IngressRoute switches from `entryPoints: [web]` → `[websecure]` and
   gets a `tls: { secretName: cloudkitchen-tls }` block.
2. Because each IngressRoute lives in a **different namespace**
   (`monitoring`, `argocd`) and Traefik can only read the TLS Secret from
   the IngressRoute's own namespace, **we duplicate the Secret into each
   target namespace**.

### 5a — Duplicate the TLS Secret into `monitoring` and `argocd`

```bash
kubectl get secret cloudkitchen-tls -n cloudkitchen -o yaml \
  | sed 's/namespace: cloudkitchen/namespace: monitoring/' \
  | kubectl apply -f -

kubectl get secret cloudkitchen-tls -n cloudkitchen -o yaml \
  | sed 's/namespace: cloudkitchen/namespace: argocd/' \
  | kubectl apply -f -

# Verify
kubectl get secret cloudkitchen-tls -n monitoring
kubectl get secret cloudkitchen-tls -n argocd
```

> 💡 **About renewal** — cert-manager only refreshes the **original** Secret
> in the `cloudkitchen` namespace (the one tied to the `Certificate`
> resource). When the cert auto-renews (~day 75), you'll need to re-run
> the two `kubectl get | sed | apply` commands above to refresh the
> duplicates. For a learning project this is fine.
> If you want fully-automatic propagation, install
> [reflector](https://github.com/emberstack/kubernetes-reflector) and
> annotate the source Secret — out of scope here.

### 5b — Re-apply the 3 observability IngressRoutes (HTTPS version)

These IngressRoutes are **not** ArgoCD-managed (no app's `path:` points at
[monitoring/ingressroutes/](../../monitoring/ingressroutes/)) — they're
applied directly via kubectl. So a `kubectl apply` of the inline YAMLs below
is the final state; nothing will revert them.

```bash
cat > /tmp/grafana-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`vijaygiduthuri.in`) && PathPrefix(`/grafana`)
      kind: Rule
      services:
        - name: monitoring-grafana
          port: 80
  tls:
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/grafana-ingressroute.yaml
```

```bash
cat > /tmp/prometheus-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`vijaygiduthuri.in`) && PathPrefix(`/prometheus`)
      kind: Rule
      services:
        - name: kube-prometheus-prometheus
          port: 9090
  tls:
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/prometheus-ingressroute.yaml
```

```bash
cat > /tmp/alertmanager-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: alertmanager
  namespace: monitoring
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`vijaygiduthuri.in`) && PathPrefix(`/alertmanager`)
      kind: Rule
      services:
        - name: kube-prometheus-alertmanager
          port: 9093
  tls:
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/alertmanager-ingressroute.yaml
```

### 5c — Update the ArgoCD IngressRoute

The ArgoCD IngressRoute lives in the cluster (created via kubectl in
Phase 4, not in any chart). The easiest way to flip it to HTTPS is to
re-apply a corrected version:

```bash
cat > /tmp/argocd-ingressroute.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`vijaygiduthuri.in`) && PathPrefix(`/argocd`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
  tls:
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/argocd-ingressroute.yaml
```

No `StripPrefix` middleware — ArgoCD was installed with
`configs.params.server.rootpath=/argocd` (Phase 4), so it already
expects the `/argocd` prefix on incoming requests.

---

## Step 6 — Verify all 5 URLs over HTTPS

```bash
DOMAIN=vijaygiduthuri.in

# 1. App UI
curl -sI "https://$DOMAIN/"                       | head -1
# Expect: HTTP/2 200

# 2. ArgoCD UI
curl -sIL "https://$DOMAIN/argocd/"               | head -1
# Expect: HTTP/2 200 (Argo redirects 307 → 200 with -L)

# 3. Grafana
curl -sIL "https://$DOMAIN/grafana/login"         | head -1
# Expect: HTTP/2 200

# 4. Prometheus
curl -sIL "https://$DOMAIN/prometheus/-/ready"    | head -1
# Expect: HTTP/2 200

# 5. Alertmanager
curl -sL  "https://$DOMAIN/alertmanager/-/ready"
# Expect: "OK"
```

Open each in a browser — you should see the **🔒 padlock** with a
browser-trusted (Let's Encrypt R10/R11 issuer) cert:

- https://vijaygiduthuri.in/                  → React UI
- https://vijaygiduthuri.in/argocd/           → ArgoCD UI (admin / your bootstrap password)
- https://vijaygiduthuri.in/grafana/          → Grafana (admin / prom-operator)
- https://vijaygiduthuri.in/prometheus/       → Prometheus
- https://vijaygiduthuri.in/alertmanager/     → Alertmanager

All five served over **HTTPS with a real browser-trusted certificate**. 🔒

---

## Step 7 — Redirect HTTP → HTTPS (catch-all)

If you `curl http://vijaygiduthuri.in/` right now you'll see:

```
404 page not found
```

That's because Step 4 + Step 5 moved every route to `entryPoints: [websecure]`
(port 443) — there's nothing listening on `entryPoints: [web]` (port 80)
anymore. Traefik gets the request, finds no IngressRoute that matches the
`web` entrypoint, and returns 404.

Standard fix: add a **Middleware + wildcard IngressRoute** that catches
every HTTP request and 308-redirects it to HTTPS. The repo ships this as
[monitoring/http-to-https-redirect.yaml](../../monitoring/http-to-https-redirect.yaml).

### Apply

```bash
cat > /tmp/http-to-https-redirect.yaml <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-to-https
  namespace: cloudkitchen
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  redirectScheme:
    scheme: https
    permanent: true   # 308 Permanent Redirect (cacheable)
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: http-to-https-redirect
  namespace: cloudkitchen
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  entryPoints:
    - web                              # ONLY HTTP — HTTPS routes bypass this
  routes:
    - match: HostRegexp(`.+`)          # match every host (Traefik 3 syntax)
      kind: Rule
      priority: 1                       # lowest priority so any explicit HTTP
                                        # route (e.g. cert-manager's HTTP-01
                                        # challenge) takes precedence
      middlewares:
        - name: redirect-to-https
      services:
        - name: frontend-service        # never actually reached — the
          port: 80                      # middleware short-circuits with 308
EOF
kubectl apply -f /tmp/http-to-https-redirect.yaml
```

### Verify

```bash
# Each path should now return 308 with Location: https://…
for path in / argocd/ grafana/login prometheus/-/ready alertmanager/-/ready; do
  printf "%-30s -> " "http://...${path}"
  curl -sI "http://vijaygiduthuri.in/${path#/}" \
    | awk '/^HTTP|^[Ll]ocation:/ {printf "%s ", $0}' ; echo
done
# Expect for each:  HTTP/1.1 308 Permanent Redirect  Location: https://vijaygiduthuri.in/...

# And follow the redirect — should land on 200 over HTTPS
for path in / argocd/ grafana/login prometheus/-/ready alertmanager/-/ready; do
  printf "%-30s -> %s\n" "http://...${path}" \
    "$(curl -sIL -o /dev/null -w '%{http_code} %{url_effective}' "http://vijaygiduthuri.in/${path#/}")"
done
# Expect:  200 https://vijaygiduthuri.in/...  for every path
```

### Why this works without breaking Let's Encrypt renewal

cert-manager solves the HTTP-01 challenge by creating a **temporary**
IngressRoute that listens on `web` and matches `/.well-known/acme-challenge/...`.
That route has a more specific path matcher (and a higher implicit priority
than our `priority: 1` catch-all), so Traefik picks it over our redirect
for the challenge traffic only. Everything else still 308s to HTTPS.

> ⚠️ **Why the `traefik` chart's `ports.web.redirectTo` doesn't work for us**
> The Traefik Helm chart used to support `ports.web.redirectTo.port=websecure`
> as a one-line redirect, but the schema in chart v40+ rejects that key
> (`additional properties 'redirectTo' not allowed`). The Middleware +
> IngressRoute pattern above is the chart-version-independent equivalent
> and works on every Traefik 3.x deployment.

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Certificate` stuck `READY=False` for >5 min | Let's Encrypt HTTP-01 can't reach `http://vijaygiduthuri.in/.well-known/acme-challenge/…` | Confirm port 80 is open: `curl http://vijaygiduthuri.in/.well-known/acme-challenge/test` should return 404 (not "connection refused"). `kubectl get challenges -A` shows the exact URL Let's Encrypt is probing — curl it from your laptop. |
| Browser shows "NET::ERR_CERT_AUTHORITY_INVALID" or warns | Either the certificate isn't ready yet OR you're hitting Traefik via an IP without the matching `Host:` header (Traefik then serves a self-signed default cert) | Confirm `kubectl -n cloudkitchen get certificate cloudkitchen-tls` shows `READY=True`, and curl with the hostname (`curl https://vijaygiduthuri.in/`), not the IP. |
| Rate-limited by Let's Encrypt (5 certs / week / domain) | You hit issuance failures in a loop or recreated the Certificate multiple times | Wait an hour (the rate window is rolling). Or temporarily point the Issuer's `server:` URL at the staging API (`https://acme-staging-v02.api.letsencrypt.org/directory`) while debugging — staging is unlimited but emits untrusted certs. |
| `kubectl get challenges` shows the challenge stuck "pending" | cert-manager's HTTP-01 solver IngressRoute clashed with something | `kubectl -n cert-manager delete order --all` (forces a fresh attempt). If it keeps failing, check `kubectl -n cert-manager logs deploy/cert-manager` for the specific error. |
| `/grafana` works but the page renders un-styled / blank | TLS secret not present in `monitoring` ns, or the IngressRoute still has `entryPoints: [web]` | Re-run Step 5a (duplicate Secret) + re-verify the edits in 5b landed: `kubectl -n monitoring get ingressroute grafana -o jsonpath='{.spec.entryPoints}'` should print `[websecure]`. |
| `/argocd` returns "ERR_TOO_MANY_REDIRECTS" | ArgoCD's `server.insecure=true` got lost during a chart upgrade — it now tries to redirect from `/argocd` to `https://localhost/argocd` | `helm upgrade argocd argo/argo-cd -n argocd --reuse-values --set 'configs.params.server\.insecure=true' --set 'configs.params.server\.rootpath=/argocd'`, then `kubectl -n argocd rollout restart deploy argocd-server`. |
| Certificate renews but `/grafana` and `/argocd` still serve the OLD cert | The duplicated Secrets in `monitoring` + `argocd` are stale — cert-manager only refreshed `cloudkitchen/cloudkitchen-tls` | Re-run the two `kubectl get | sed | apply` commands from Step 5a. To automate, install [reflector](https://github.com/emberstack/kubernetes-reflector). |
| `error from server: no matches for kind "Certificate"` | cert-manager CRDs didn't install | `kubectl get crd | grep cert-manager.io` should list 6 CRDs. If empty, re-run Step 1 with `--set crds.enabled=true`. |

---

## 📋 Phase 7 cheatsheet

Every step except Step 4 is now a paste-and-go heredoc — see the full
YAML inline in each step above. Quick summary:

| # | What | Where to copy from |
|---|---|---|
| 1a | AppProject + `cert-manager` ns | Step 1a heredoc → `kubectl apply` |
| 1b | cert-manager Application | Step 1b heredoc → `kubectl apply` |
| 2  | ClusterIssuer `letsencrypt-prod` | Step 2 heredoc → `kubectl apply` |
| 3  | Certificate `cloudkitchen-tls` | Step 3 heredoc → wait `READY=True` |
| 4a | Disable ArgoCD auto-sync on `cloudkitchen` App | Step 4a one-liner |
| 4b | HTTPS-flavor cloudkitchen IngressRoute (10 routes preserved) | Step 4b heredoc → `kubectl apply` |
| 5a | Copy TLS Secret → `monitoring` + `argocd` | Step 5a one-liner |
| 5b | Grafana / Prometheus / Alertmanager IngressRoutes | Step 5b — 3 separate heredocs |
| 5c | ArgoCD IngressRoute | Step 5c heredoc |
| 6  | Browser-verify all 5 URLs over HTTPS | Step 6 |
| 7  | HTTP→HTTPS catch-all redirect | Step 7 heredoc |

Final smoke test (HTTPS round-trip on all 5 endpoints):

```bash
for URL in / /argocd/ /grafana/login /prometheus/-/ready /alertmanager/-/ready; do
  printf "%-30s  -> " "$URL"
  curl -sIL -o /dev/null -w "HTTP %{http_code}\n" "https://vijaygiduthuri.in$URL"
done
```

---

## 🎉 What you accomplished

- ✅ **cert-manager** running with the Let's Encrypt production issuer
- ✅ A real **browser-trusted TLS certificate** in the cluster, auto-renewing every 75 days
- ✅ Chart flipped to HTTPS via the existing `ingress.tls` toggle — no chart-template edits needed
- ✅ **All 5 UIs** (app, ArgoCD, Grafana, Prometheus, Alertmanager) reachable under the **same domain** over HTTPS

You now have a **production-shape** GKE deployment:

```
https://vijaygiduthuri.in                📱 the app
https://vijaygiduthuri.in/argocd         🚀 GitOps controller
https://vijaygiduthuri.in/grafana        📊 dashboards
https://vijaygiduthuri.in/prometheus     📈 metrics
https://vijaygiduthuri.in/alertmanager   🚨 alerts
```

---

## 🧹 Tearing it all down

When you finish the learning journey:

```bash
# 1. (Optional) helm uninstalls — quick
helm uninstall cloudkitchen   -n cloudkitchen
helm uninstall argocd         -n argocd
helm uninstall traefik        -n traefik
helm uninstall cert-manager   -n cert-manager
# (monitoring + logging Apps will go away with the cluster — they're
#  ArgoCD-managed so you can ALSO `kubectl -n argocd delete app monitoring logging`)

# 2. Delete StatefulSet PVCs (NOT auto-deleted)
kubectl -n cloudkitchen delete pvc -l app=postgres
kubectl -n cloudkitchen delete pvc -l app=nats
kubectl -n monitoring  delete pvc --all
kubectl -n logging     delete pvc --all

# 3. Release the static LB IP (otherwise GCP keeps billing ~$7/month)
gcloud compute addresses delete traefik-lb-ip --region=us-central1

# 4. Destroy the GCP infra
cd gcp-terraform && terraform destroy
```

Billing drops to ~$0/day within ~10 minutes once `terraform destroy` finishes.

---

🏁 **You did it.** The full DevOps lifecycle in seven phases on GKE:
**infra → ingress → CI → CD → DNS → observability → HTTPS**.

Go put this on your resume.
