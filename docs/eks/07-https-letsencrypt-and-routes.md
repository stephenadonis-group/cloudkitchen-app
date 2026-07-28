# Phase 7 — HTTPS with Let's Encrypt + Path-Routed Sub-Apps

**Goal:** Install **cert-manager**, mint a free **Let's Encrypt** certificate
for your domain, flip the chart to **HTTPS** (`websecure`), and route
**ArgoCD, Grafana, Prometheus** through Traefik under the same domain so you
finish with:

```
https://cloudkitchen.<your-domain>             — the app UI
https://cloudkitchen.<your-domain>/argocd      — ArgoCD UI
https://cloudkitchen.<your-domain>/grafana     — Grafana
https://cloudkitchen.<your-domain>/prometheus  — Prometheus
```

**Time:** ~15 minutes (most of it Let's Encrypt issuing the cert).

---

## What & why

After Phase 5 you have HTTP working. Modern browsers warn on HTTP and many
auth flows refuse to run, so HTTPS is mandatory.

**cert-manager** is the standard Kubernetes operator that talks to ACME
servers (Let's Encrypt, ZeroSSL, internal CA) to obtain + renew certificates
automatically. We use Let's Encrypt's free service with **HTTP-01** challenges
(easiest — just needs port 80 reachable, which it already is via Traefik).

```
        ┌────────────────────────────────────────────────────┐
        │  cert-manager (cert-manager ns)                    │
        │   ┌──────────────────────────────────────────┐     │
        │   │  ClusterIssuer "letsencrypt-prod"        │     │
        │   │  ClusterIssuer "letsencrypt-staging"     │     │
        │   └──────────────────────────────────────────┘     │
        │                       │                            │
        │                       ▼                            │
        │   Certificate "cloudkitchen-tls"                   │
        │   → produces Secret "cloudkitchen-tls" in          │
        │     cloudkitchen namespace                         │
        └────────────────────┬───────────────────────────────┘
                             │
                             ▼
        Traefik IngressRoute (Phase 4 chart, ingress.tls=true)
        uses secretName=cloudkitchen-tls → HTTPS!
```

---

## ⚠️ Heads-up — The Certificate is created manually

We **intentionally** removed the cert-manager `Certificate` resource from the
Helm chart (back in Phase 1-ish). The certificate's lifecycle is tied to your
domain, not the chart's lifecycle — keeping it separate makes it safer to
re-deploy the chart without churning the cert (Let's Encrypt rate-limits real
certs at 5/week per registered domain).

So in this phase we **apply the Certificate manifest by hand** from
`security/cert-manager/`.

---

## ✅ Prerequisites

| Check | How |
|-------|-----|
| Phase 5 done (your domain resolves) | `dig +short cloudkitchen.<your-domain>` returns the LB IPs |
| Phase 6 done (monitoring + logging) | `kubectl -n monitoring get pods` healthy |
| Port 80 reachable from the internet | Used by Let's Encrypt for HTTP-01 challenge |

---

## Step 1 — Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager
```
**What this does:**
- Installs the cert-manager Helm chart into a new `cert-manager` namespace.
- `crds.enabled=true` installs the CRDs (`Certificate`, `Issuer`,
  `ClusterIssuer`, `Order`, `Challenge`).
- Three Deployments come up: `cert-manager`, `cert-manager-cainjector`,
  `cert-manager-webhook`.

Wait:
```bash
kubectl -n cert-manager rollout status deploy/cert-manager
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
```

---

## Step 2 — Apply the ClusterIssuers (staging + prod)

The repo ships both in `security/cert-manager/`:
- `cluster-issuer-staging.yaml` → Let's Encrypt **staging** API. Use this for
  initial testing — staging certs aren't trusted by browsers, but staging is
  not rate-limited so you can iterate freely.
- `cluster-issuer-prod.yaml` → Let's Encrypt **production** API. Use this once
  you've confirmed the flow works.

Both use the **HTTP-01 solver via Traefik**.

```bash
# Set your email first (required by Let's Encrypt for expiry notices)
EMAIL="you@yourdomain.com"
sed -i "s/admin@cloudkitchen.example.com/$EMAIL/" security/cert-manager/cluster-issuer-*.yaml

kubectl apply -f security/cert-manager/cluster-issuer-staging.yaml
kubectl apply -f security/cert-manager/cluster-issuer-prod.yaml
```
**What this does:** Creates two cluster-wide Issuers. The Certificate (next
step) references one of them by name.

Verify:
```bash
kubectl get clusterissuer
# Both should be Ready=True after ~30s.
```

---

## Step 3 — MANUALLY create the Certificate

```bash
DOMAIN=cloudkitchen.<your-domain>

# Start with STAGING to avoid rate limits while debugging
cat > /tmp/cloudkitchen-cert.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cloudkitchen-tls
  namespace: cloudkitchen
spec:
  secretName: cloudkitchen-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - $DOMAIN
EOF
kubectl apply -f /tmp/cloudkitchen-cert.yaml
```
**What this does:** Tells cert-manager to obtain a TLS certificate for
`$DOMAIN` from the staging issuer and store it in a Secret named
`cloudkitchen-tls` in the `cloudkitchen` namespace — which is exactly the
secret name the chart's IngressRoute references.

Watch:
```bash
kubectl -n cloudkitchen get certificate cloudkitchen-tls -w
# Wait for READY=True (typically <60s)

# Drilling deeper if stuck:
kubectl -n cloudkitchen describe certificate cloudkitchen-tls
kubectl -n cloudkitchen get challenges
```

Once `READY=True`, switch to **prod** for a browser-trusted cert:
```bash
sed -i 's|letsencrypt-staging|letsencrypt-prod|' /tmp/cloudkitchen-cert.yaml
kubectl apply -f /tmp/cloudkitchen-cert.yaml
# Watch again until READY=True
kubectl -n cloudkitchen get certificate cloudkitchen-tls -w
```

---

## Step 4 — Flip the chart to HTTPS

Edit `helm/cloudkitchen/values.yaml`:

```yaml
ingress:
  enabled: true
  tls: true                     # was false
  domain: cloudkitchen.<your-domain>    # (already from Phase 5)
  entryPoint: websecure         # was 'web'
  tlsSecretName: cloudkitchen-tls
  clusterIssuer: letsencrypt-prod
```

Commit + push → ArgoCD syncs the new IngressRoute (port 443, TLS secret
referenced):
```bash
git commit -am "ingress: enable TLS (websecure + cloudkitchen-tls)" && git push
```

Force the sync immediately instead of waiting for the poll:
```bash
kubectl -n argocd patch app cloudkitchen --type merge -p '{"operation":{"sync":{}}}'
```

Test:
```bash
curl -I "https://$DOMAIN"                # 200 (no -k needed; cert is trusted)
curl -s "https://$DOMAIN/api/restaurants" | head -c 200 ; echo
```

🎉 You're on **HTTPS**.

---

## Step 5 — Route ArgoCD / Grafana / Prometheus under the same domain

This is the subtle part. Each app must (1) be reachable from Traefik and
(2) be **told it lives under a sub-path**, otherwise its UI builds absolute
URLs that 404.

### 5.1 — Reconfigure each app

**Grafana** (path `/grafana`)
```bash
helm upgrade kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f monitoring/prometheus-values.yaml \
  --set grafana."grafana\.ini".server.root_url="https://$DOMAIN/grafana" \
  --set grafana."grafana\.ini".server.serve_from_sub_path=true
```

**ArgoCD** (path `/argocd`)
```bash
helm upgrade argocd argo/argo-cd \
  -n argocd \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --set configs.params."server\.rootpath"=/argocd
kubectl -n argocd rollout restart deploy argocd-server
```

**Prometheus** (path `/prometheus`)
```bash
helm upgrade kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --set prometheus.prometheusSpec.externalUrl="https://$DOMAIN/prometheus" \
  --set prometheus.prometheusSpec.routePrefix=/prometheus
```

### 5.2 — Add IngressRoutes for the sub-paths

Create one file holding three IngressRoutes (one per app). The
`StripPrefix` middleware removes `/grafana`, `/argocd`, `/prometheus` before
the request hits the upstream — paired with each app's sub-path config above.

```bash
DOMAIN=cloudkitchen.<your-domain>
cat > /tmp/sub-apps.yaml <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-grafana
  namespace: monitoring
spec:
  stripPrefix:
    prefixes: ["/grafana"]
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(\`$DOMAIN\`) && PathPrefix(\`/grafana\`)
      kind: Rule
      middlewares:
        - name: strip-grafana
      services:
        - name: kube-prom-stack-grafana
          port: 80
  tls:
    secretName: cloudkitchen-tls
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-prometheus
  namespace: monitoring
spec:
  stripPrefix:
    prefixes: ["/prometheus"]
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: prometheus
  namespace: monitoring
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(\`$DOMAIN\`) && PathPrefix(\`/prometheus\`)
      kind: Rule
      middlewares:
        - name: strip-prometheus
      services:
        - name: kube-prom-stack-prometheus
          port: 9090
  tls:
    secretName: cloudkitchen-tls
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(\`$DOMAIN\`) && PathPrefix(\`/argocd\`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
  tls:
    secretName: cloudkitchen-tls
EOF
kubectl apply -f /tmp/sub-apps.yaml
```
**What this does:**
- Adds two new IngressRoutes (Grafana, Prometheus), each with a `StripPrefix`
  Middleware so `/grafana/foo` is rewritten to `/foo` before hitting the
  backend (paired with `serve_from_sub_path` / `route-prefix` from Step 5.1).
- **Upgrades the ArgoCD IngressRoute** (already created in Phase 4 on the
  `web` entrypoint) to `websecure` + `tls.secretName: cloudkitchen-tls`. The
  Phase 4 HTTP route at `http://<LB_DNS>/argocd` will stop working — by
  design — and ArgoCD becomes reachable only at `https://$DOMAIN/argocd`.
- No `StripPrefix` for ArgoCD because its `server.rootpath` already makes it
  *expect* the prefix on inbound requests.

> ⚠️ **TLS secret is in `cloudkitchen` namespace, but these IngressRoutes are
> in other namespaces.** Traefik can read a TLS secret across namespaces
> through a `TLSStore` — or simpler, **copy/duplicate the secret** into
> `argocd` and `monitoring`:
> ```bash
> kubectl get secret cloudkitchen-tls -n cloudkitchen -o yaml \
>   | sed 's/namespace: cloudkitchen/namespace: monitoring/' | kubectl apply -f -
> kubectl get secret cloudkitchen-tls -n cloudkitchen -o yaml \
>   | sed 's/namespace: cloudkitchen/namespace: argocd/' | kubectl apply -f -
> ```
> (cert-manager only refreshes the original; if you want auto-renew everywhere,
> create one `Certificate` per namespace or use the
> [reflector](https://github.com/emberstack/kubernetes-reflector) operator.)

---

## Step 6 — Verify the four URLs

```bash
DOMAIN=cloudkitchen.<your-domain>

# 1. App UI
curl -I "https://$DOMAIN" | head -1                              # HTTP/2 200

# 2. ArgoCD UI
curl -I "https://$DOMAIN/argocd" | head -1                       # HTTP/2 200 (or 307 to login)

# 3. Grafana
curl -I "https://$DOMAIN/grafana/login" | head -1                # HTTP/2 200

# 4. Prometheus
curl -I "https://$DOMAIN/prometheus/graph" | head -1             # HTTP/2 200
```

Open each in a browser:
- https://cloudkitchen.\<your-domain\>          → React UI
- https://cloudkitchen.\<your-domain\>/argocd   → ArgoCD UI (login: admin / your reset password)
- https://cloudkitchen.\<your-domain\>/grafana  → Grafana (admin + password from Phase 6 step 5.1)
- https://cloudkitchen.\<your-domain\>/prometheus → Prometheus UI

All four served over **HTTPS with a real browser-trusted certificate**. 🔒

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Certificate` stuck `Ready=False` for >5 min | Let's Encrypt HTTP-01 can't reach `http://$DOMAIN/.well-known/acme-challenge/…` | confirm port 80 is open on the LB; `kubectl get challenges -A` shows the test URL the validator tries — `curl` it yourself |
| Browser says "NET::ERR_CERT_AUTHORITY_INVALID" on prod issuer | You actually have the staging cert | edit `/tmp/cloudkitchen-cert.yaml` `issuerRef.name` to `letsencrypt-prod`, `kubectl apply` again, wait |
| Rate-limited by Let's Encrypt | You requested too many real certs (5/week/domain) | use the staging issuer until everything works, then switch once |
| ArgoCD login page loads but assets 404 | `server.rootpath` not set / not propagated | re-run the `helm upgrade argocd …` from Step 5.1 and `kubectl -n argocd rollout restart deploy/argocd-server` |
| Grafana UI loads but no styles | StripPrefix not applied | check the IngressRoute references `strip-grafana` Middleware AND `grafana.ini.server.serve_from_sub_path=true` |
| Prometheus 404s on `/prometheus/graph` | `route-prefix` mismatch | `kubectl -n monitoring get prometheus -o yaml \| grep -E 'externalUrl\|routePrefix'` — should both end in `/prometheus` |
| HTTPS works for the app but fails on /argocd | TLS secret missing in argocd ns | duplicate the secret per Step 5.2 sidebar |
| `error from server: no matches for kind Middleware` | Traefik CRDs not installed | Phase 2 install includes them; `kubectl get crd \| grep traefik` should list `middlewares.traefik.io` |

---

## 📋 Phase 7 cheatsheet

```bash
# cert-manager + issuers
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
kubectl apply -f security/cert-manager/cluster-issuer-staging.yaml
kubectl apply -f security/cert-manager/cluster-issuer-prod.yaml

# Manual cert (STAGING first, then PROD)
kubectl apply -f /tmp/cloudkitchen-cert.yaml
kubectl -n cloudkitchen get certificate -w

# Flip chart to HTTPS
sed -i 's/tls: false/tls: true/'        helm/cloudkitchen/values.yaml
sed -i 's/entryPoint: web/entryPoint: websecure/' helm/cloudkitchen/values.yaml
git commit -am "ingress: HTTPS" && git push

# Sub-app reconfig (run once)
helm upgrade argocd argo/argo-cd -n argocd \
  --set configs.params."server\.rootpath"=/argocd
helm upgrade kube-prom-stack prometheus-community/kube-prometheus-stack -n monitoring \
  --reuse-values \
  --set grafana."grafana\.ini".server.root_url="https://$DOMAIN/grafana" \
  --set grafana."grafana\.ini".server.serve_from_sub_path=true \
  --set prometheus.prometheusSpec.externalUrl="https://$DOMAIN/prometheus" \
  --set prometheus.prometheusSpec.routePrefix=/prometheus
kubectl apply -f /tmp/sub-apps.yaml
```

---

## 🎉 What you accomplished

- ✅ **cert-manager** installed with staging + prod Let's Encrypt issuers.
- ✅ A real **browser-trusted TLS certificate** auto-renewing in your cluster.
- ✅ Chart flipped to HTTPS via the new `ingress.tls` toggle (no chart code
  change for next time).
- ✅ **ArgoCD, Grafana, Prometheus** all reachable under the **same domain via
  sub-paths**, behind TLS, going through Traefik.

You now have a **production-shape** EKS deployment:

```
https://cloudkitchen.<your-domain>             📱 the app
https://cloudkitchen.<your-domain>/argocd      🚀 GitOps controller
https://cloudkitchen.<your-domain>/grafana     📊 dashboards
https://cloudkitchen.<your-domain>/prometheus  📈 metrics & alerts
```

---

## 🧹 Tearing it all down

When you finish the learning journey:

```bash
# 1. (Optional) Uninstall the helm releases (faster than `terraform destroy` alone)
helm uninstall cloudkitchen -n cloudkitchen
helm uninstall kube-prom-stack -n monitoring
helm uninstall loki promtail -n logging
helm uninstall argocd -n argocd
helm uninstall traefik -n ingress
helm uninstall cert-manager -n cert-manager

# 2. Delete StatefulSet PVCs (not auto-deleted)
kubectl -n cloudkitchen delete pvc -l app=postgres
kubectl -n cloudkitchen delete pvc -l app=nats

# 3. Destroy the AWS infra
cd terraform && terraform destroy
```

Bill stops within ~10 minutes once `terraform destroy` finishes.

---

🏁 **You did it.** The full DevOps lifecycle in seven phases: infra → ingress →
CI → CD → DNS → observability → HTTPS. Go put this on your resume.
