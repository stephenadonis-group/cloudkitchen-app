# Phase 5 — DNS + GoDaddy (GCP)

**Goal:** Make the app reachable by your own domain instead of a raw IP.

**Time:** ~15 min.

> Before: `http://<LB_IP>/`
> After:  `http://vijaygiduthuri.in/`  and  `http://vijaygiduthuri.in/argocd/`

---

## ✅ Prerequisites

| Need                                              | How to check                                                 |
| ------------------------------------------------- | ------------------------------------------------------------ |
| Phase 4 done (app reachable at `http://<LB_IP>/`) | `kubectl -n cloudkitchen get pods` → 12 pods Running         |
| A domain you control                              | We use `vijaygiduthuri.in` (registered at GoDaddy)           |
| `dig` and `nslookup` on your laptop               | `dig +short google.com` and `nslookup google.com` both work  |

---

## Step 1 — Get the LoadBalancer IP, then add an A record at GoDaddy

### 1a — Read the LB IP from the cluster (no hard-coded values)

```bash
LB_IP=$(kubectl -n traefik get svc traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LB IP: ${LB_IP}"
```

Sample output:
```
LB IP: 35.224.38.103
```

### 1b — Add the A record at GoDaddy

1. Sign into https://account.godaddy.com/products
2. Click your domain → **DNS** (or **Manage DNS**)
3. Click **Add New Record**
4. Fill in:

   | Field    | Value                                         |
   | -------- | --------------------------------------------- |
   | **Type** | `A`                                           |
   | **Name** | `@` (apex) — or a label like `cloudkitchen`   |
   | **Value**| The IP from `echo $LB_IP` (paste it)          |
   | **TTL**  | `600` (10 min)                                |

5. **Save**.

> 💡 We used `Name = @` so the bare `vijaygiduthuri.in` resolves. With
> `Name = cloudkitchen` the URL becomes `cloudkitchen.vijaygiduthuri.in`.
> Both work — the chart accepts a list of hostnames in Step 3.

---

## Step 2 — Verify DNS propagation

GoDaddy → public resolvers usually takes 1–10 min.

### 2a — `dig`

```bash
dig +short @8.8.8.8 vijaygiduthuri.in
```
Expected: a single line with your `$LB_IP`.

### 2b — `nslookup`

```bash
nslookup vijaygiduthuri.in 8.8.8.8
```
Expected:
```
Name:    vijaygiduthuri.in
Address: 35.224.38.103          ← should equal your $LB_IP
```

### 2c — When the above two don't agree

Open https://dnschecker.org → paste your hostname. It queries DNS servers
from ~25 regions worldwide and shows which ones have the record yet.

### 2d — HTTP probe (sanity)

```bash
curl -sI -o /dev/null -w "%{http_code}\n" "http://vijaygiduthuri.in/"
```

Will be **404** until Step 3 lands the chart change — that's expected.
404 here means "Traefik received the request but no IngressRoute matched
the `Host:` header" — exactly what Step 3 fixes.

---

## Step 3 — Update the chart so it accepts the hostname

Two files change. Both edits are tiny — the rest of each file is untouched.

### Step 3a — `helm/cloudkitchen/values.yaml`

Open the file and find the `ingress:` block (around line 143). It currently
looks like this:

```yaml
ingress:
  enabled: true
  tls: false
  domain: 35.224.38.103         # 👈 a single string, hard-coded to the IP
  entryPoint: web
  tlsSecretName: cloudkitchen-tls
  clusterIssuer: letsencrypt-prod
```

**What to do:** delete the `domain:` line. In its place add a `hosts:`
**list** with your hostname first and the LB IP second. The block becomes:

```yaml
ingress:
  enabled: true
  tls: false
  hosts:                        # 👈 a list (one item per accepted hostname)
    - vijaygiduthuri.in         # 👉 YOUR hostname goes here
    - 35.224.38.103             # 👉 YOUR LB IP goes here (kept for curl-by-IP debugging)
  entryPoint: web
  tlsSecretName: cloudkitchen-tls
  clusterIssuer: letsencrypt-prod
```

**Why two hosts?** The first is what real users will type in a browser. The
second lets you keep curling the cluster by IP for debugging even after DNS
is in place.

Generate the exact lines for your environment (no manual typing of the IP):
```bash
HOSTNAME='vijaygiduthuri.in'                                                  # 👈 set to YOUR domain
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
printf '  hosts:\n    - %s\n    - %s\n' "${HOSTNAME}" "${LB_IP}"
```

Copy the printed 3 lines into the `ingress:` block.

---

### Step 3b — `helm/cloudkitchen/templates/ingressroute.yaml`

Two edits here.

#### Edit 1: add a helper at the very top of the file

Paste this **above** the existing `{{- if .Values.ingress.enabled }}` line
(so it becomes the first thing in the file):

```yaml
{{- /*
hostsMatcher: renders Traefik's host clause from .Values.ingress.hosts.
Traefik 3's Host() takes ONLY ONE argument — Host(`a`,`b`) is rejected.
We render Host(`a`) || Host(`b`) || ... and the callers wrap that in
parens so the surrounding `&& PathPrefix(...)` precedence works.
*/ -}}
{{- define "cloudkitchen.hostsMatcher" -}}
{{- range $i, $h := .Values.ingress.hosts -}}{{- if $i }} || {{ end }}Host(`{{ $h }}`){{- end -}}
{{- end -}}
```

#### Edit 2: update every `match:` line in the 10 routes

In the file there are 10 lines that look like this:

```yaml
    - match: Host(`{{ .Values.ingress.domain }}`) && PathPrefix(`/api/...`)
```

Replace every one of them with this form (note the **outer parens**):

```yaml
    - match: ({{ include "cloudkitchen.hostsMatcher" . }}) && PathPrefix(`/api/...`)
```

The `PathPrefix(...)` / `PathRegexp(...)` part on the right stays exactly
as it was — only the `Host(...)` clause on the left changes. Same for the
`PathPrefix(\`/\`)` frontend catch-all and the `PathRegexp(...)` menu rules.

**Why the outer parens?** Inside `cloudkitchen.hostsMatcher` we render
`Host(\`a\`) || Host(\`b\`)`. Without parens the `&&` in the surrounding
matcher would bind tighter than the `||` and Traefik would interpret the
rule wrong.

#### Verify your edits

Two greps tell you everything went right:

```bash
# Should be 0 — no remaining old-style matchers
grep -c 'Host(`{{ .Values.ingress.domain }}`)' helm/cloudkitchen/templates/ingressroute.yaml

# Should be 11 — 10 route matchers + 1 helper define line
grep -c 'cloudkitchen.hostsMatcher' helm/cloudkitchen/templates/ingressroute.yaml
```

Then render the chart locally to see the final rules:

```bash
helm template cloudkitchen ./helm/cloudkitchen | grep -E "match:" | head -5
```

Expected — every line starts with the same `(Host(...) || Host(...))`:
```
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathRegexp(`^/api/restaurants/...`)
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/api/menu`)
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/api/auth`)
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/api/users`)
    - match: (Host(`vijaygiduthuri.in`) || Host(`35.224.38.103`)) && PathPrefix(`/api/restaurants`)
```

---

## Step 4 — Push through the GitOps loop

```bash
git add helm/cloudkitchen/values.yaml helm/cloudkitchen/templates/ingressroute.yaml
git commit -m "phase 5: accept hostname (vijaygiduthuri.in) on the IngressRoute"
git push origin main
```

> The CI pipeline (`ci-gcp.yaml`) **does not** rebuild images on changes
> under `helm/**` — its `paths:` filter watches the service directories.
> So this push doesn't trigger CI. ArgoCD picks the change up directly,
> via its 3-minute repo poll.

To skip the wait, force a refresh:
```bash
kubectl -n argocd annotate app cloudkitchen \
  argocd.argoproj.io/refresh=hard --overwrite
```

Watch the Application reconcile:
```bash
kubectl -n argocd get app cloudkitchen -w
# Wait until you see: Synced / Healthy.  Ctrl+C to stop watching.
```

---

## Step 5 — Verify hostname-based access

```bash
HOSTNAME='vijaygiduthuri.in'
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "=== via hostname ==="
curl -s -o /dev/null -w "  /                -> HTTP %{http_code}\n" "http://${HOSTNAME}/"
curl -s -o /dev/null -w "  /argocd/         -> HTTP %{http_code}\n" "http://${HOSTNAME}/argocd/"
curl -s -o /dev/null -w "  /api/restaurants -> HTTP %{http_code}\n" "http://${HOSTNAME}/api/restaurants"

echo "=== via raw IP (must still work — second host in the list) ==="
curl -s -o /dev/null -w "  /                -> HTTP %{http_code}\n" "http://${LB_IP}/"
curl -s -o /dev/null -w "  /api/restaurants -> HTTP %{http_code}\n" "http://${LB_IP}/api/restaurants"
```

All should return **HTTP 200**.

> ⚠️ **HEAD vs GET quirk** — `curl -I` (HEAD) returns 404 on some routes
> even when GET returns 200. That's a Gin quirk (no HEAD handler defined
> for those routes), not a Traefik issue. Real browser traffic uses GET,
> so this doesn't affect users.

Open in a browser:
- **App:** http://vijaygiduthuri.in/
- **ArgoCD:** http://vijaygiduthuri.in/argocd/  (trailing slash required)

---

## Step 6 — Sanity-check Traefik's parsed routers

If Step 5 fails, this tells you whether Traefik even **accepted** the new
IngressRoute. A syntax error in the matcher silently disables the router.

```bash
kubectl -n traefik exec deploy/traefik -- wget -qO- http://localhost:8080/api/http/routers \
  | python3 -c "
import json, sys
ck = [r for r in json.load(sys.stdin) if 'cloudkitchen' in r.get('name','').lower()]
enabled = [r for r in ck if r.get('status')=='enabled']
print(f'  {len(enabled)} / {len(ck)} cloudkitchen routers ENABLED')
for r in ck:
  if r.get('status') != 'enabled':
    print(f'  ❌  {r[\"name\"][:60]}  err={r.get(\"error\")}')"
```

Expected: `10 / 10 cloudkitchen routers ENABLED`.

If any are not enabled, the `err=` field shows exactly which rule failed
parsing — see the Troubleshooting table.

---

## Step 7 — (Optional but recommended) Reserve the LB IP as a static address

By default GKE assigns an **ephemeral** IP. If you ever delete and recreate
the Traefik Service, the IP changes and your DNS goes stale.

```bash
PROJECT=$(gcloud config get-value project)
REGION=us-central1
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 1. Promote the current ephemeral IP to a regional static address.
gcloud compute addresses create traefik-lb-ip \
  --addresses="${LB_IP}" \
  --region="${REGION}" \
  --project="${PROJECT}"

# 2. Pin the Traefik Service to that static IP.
helm upgrade traefik traefik/traefik \
  --namespace traefik --reuse-values \
  --set service.loadBalancerIP="${LB_IP}"

# 3. Confirm the IP didn't change after the upgrade.
kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'
```

If you ever destroy the cluster, release the static IP so you stop being
billed (~$7/month):

```bash
gcloud compute addresses delete traefik-lb-ip --region=us-central1
```

---

## Troubleshooting

These are the real failures we hit on `cloudkitchen-dev-01` while landing
Phase 5:

| Symptom | Cause | Fix |
| --- | --- | --- |
| `dig` returns nothing for 15+ minutes | GoDaddy's NS hasn't pushed the record yet, or the record was saved against the wrong domain | Check https://dnschecker.org. Re-open the GoDaddy DNS page and make sure the record is there. |
| `nslookup` and `dig` disagree | They're querying different DNS servers | Force both to Google: `nslookup vijaygiduthuri.in 8.8.8.8` and `dig +short @8.8.8.8 vijaygiduthuri.in`. |
| Hostname resolves correctly, but `curl http://<host>/` is 404 | Chart's IngressRoute is still hard-coded to the IP. The browser sends `Host: <hostname>`, which doesn't match. | This whole Phase 5 — do Step 3. |
| After Step 3, ALL routes return 404 (including IP-by-curl). Traefik logs say `Host: unexpected number of parameters; got 2, expected one of [1]` | The multi-host comma form `Host(\`a\`,\`b\`)` is invalid in Traefik 3. | Use `Host(\`a\`) || Host(\`b\`)` instead — that's exactly what the `cloudkitchen.hostsMatcher` helper in Step 3b does. Wrap each call site in outer parens. |
| `curl -I` returns 404 but `curl` (GET) returns 200 | Gin doesn't auto-register HEAD handlers | Expected. Real traffic is GET. Test with GET, not HEAD. |
| ArgoCD shows `Synced` but the cluster still serves old behaviour | ArgoCD synced against an old git revision; the new commit hasn't been polled yet | `kubectl -n argocd annotate app cloudkitchen argocd.argoproj.io/refresh=hard --overwrite` |
| Some routes fixed, others still 404 | A stale `Host(\`{{ .Values.ingress.domain }}\`)` was left in the template | `grep -c 'Host(\`{{ .Values.ingress.domain }}\`)' helm/cloudkitchen/templates/ingressroute.yaml` should print 0. If not, find + replace the leftover. |
| Recreated the Traefik Service and DNS resolves to a dead IP | GKE assigned a new ephemeral IP | Either update GoDaddy, **or** do Step 7 — static IP — so this never happens again. |

---

➡️ **Next:** Phase 6 — Monitoring & Logging (Prometheus + Grafana + Loki).
