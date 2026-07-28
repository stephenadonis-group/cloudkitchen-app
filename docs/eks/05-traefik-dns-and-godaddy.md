# Phase 5 — Access via Traefik LB & Point Your Domain

**Goal:** Verify the app is reachable through Traefik's AWS LB hostname, then
**point your own domain at it via a GoDaddy CNAME**, and finally smoke-test the
full register → order → tracking flow against your domain. (Still HTTP — TLS is
Phase 7.)

**Time:** ~15 minutes (mostly waiting for DNS propagation).

---

## What & why

After Phase 4, the app is **deployed** but reaches only via the auto-generated
NLB hostname (something like
`aXXXXXX-YYYYYY.elb.us-east-1.amazonaws.com`). That works for testing, but
nobody will type that. We give it a real name with a single DNS record.

```
   user types  cloudkitchen.<your-domain>
                       │
                       ▼
    GoDaddy DNS  (CNAME -> aXXXXX...elb.us-east-1.amazonaws.com)
                       │
                       ▼
    AWS Network LB  (created by the Traefik Service in Phase 2)
                       │
                       ▼
    Traefik routes  Host(`cloudkitchen.<your-domain>`)
                    → cloudkitchen ns Services
```

---

## ✅ Prerequisites

| Check | Command |
|-------|---------|
| App is deployed (Phase 4) | `kubectl -n cloudkitchen get pods` — all Running |
| Traefik LB hostname known | `kubectl -n ingress get svc traefik` — `EXTERNAL-IP` populated |
| A domain you own | GoDaddy account with the domain in your portfolio |

---

## Step 1 — Capture the LB hostname

```bash
LB_DNS=$(kubectl -n ingress get svc traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$LB_DNS"
```
Should print something like `aabbccdd1122334455.elb.us-east-1.amazonaws.com`.

---

## Step 2 — Smoke-test using a forced Host header

The chart's IngressRoute matches on
`Host(\`cloudkitchen.example.com\`)` (the default `ingress.domain`), **not** the
LB hostname. So a direct curl to the LB returns 404 — Traefik says "no rule
matches that host". Override it with a header:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "http://$LB_DNS" \
  -H 'Host: cloudkitchen.example.com'
# Expect: 200 (the frontend renders)

curl -s "http://$LB_DNS/api/auth/healthz" \
  -H 'Host: cloudkitchen.example.com'
# Expect: {"status":"ok","service":"auth-service"}  -- 404 is also possible
# because /api/auth/healthz isn't an auth route; try a real one:
curl -i -s "http://$LB_DNS/api/restaurants" \
  -H 'Host: cloudkitchen.example.com'
# Expect: HTTP/1.1 200 OK   plus a JSON body (probably an empty array [])
```
**What this does:** Curls the public LB but tells it "treat me as if I came
in via the host `cloudkitchen.example.com`". Traefik then matches the rule and
routes you to the right backend.

If you get `200` on `/api/restaurants` — **the entire stack works end-to-end**:
LB → Traefik → restaurant-service → Postgres.

---

## Step 3 — Decide on a hostname under your real domain

Pick a subdomain you'll point at the cluster. Conventions:

| Goal | Example |
|------|---------|
| Test cluster | `cloudkitchen.test.yourname.com` |
| Personal portfolio | `cloudkitchen.yourname.dev` |
| Production-ish | `app.yourname.com` |

> ⚠️ Use a **subdomain**, not the apex (e.g. `yourname.com`). GoDaddy doesn't
> support `CNAME` at the apex; using ALIAS / forwarding there is messier.

We'll use `cloudkitchen.<your-domain>` below — swap in yours.

---

## Step 4 — Create the GoDaddy CNAME

1. Log into https://account.godaddy.com → **My Products** → next to your domain
   click **DNS**.
2. **Add new record**:

| Field | Value |
|------|-------|
| Type | `CNAME` |
| Name | `cloudkitchen` *(the subdomain — without the dot or your domain)* |
| Value | the `$LB_DNS` from Step 1 *(no `http://`, no trailing dot)* |
| TTL | `1 Hour` *(or as low as GoDaddy allows — speeds up the next change)* |

3. **Save**.

DNS propagation: GoDaddy is usually fast (1–10 minutes), but can take longer.
Check from your terminal:
```bash
dig +short cloudkitchen.<your-domain> CNAME
# Expect: aXXXX...elb.us-east-1.amazonaws.com.

dig +short cloudkitchen.<your-domain>
# Expect: 3 IPv4 addresses (one per AZ).
```

---

## Step 5 — Tell the chart your real domain

The chart's `ingress.domain` is still `cloudkitchen.example.com`. Update it to
your real subdomain so Traefik's `Host(...)` rules match real DNS:

```bash
# In your local checkout:
DOMAIN=cloudkitchen.<your-domain>
sed -i "s|domain: cloudkitchen.example.com|domain: $DOMAIN|" helm/cloudkitchen/values.yaml
git add helm/cloudkitchen/values.yaml
git commit -m "helm: point ingress at $DOMAIN"
git push
```
**What this does:** Changes the `ingress.domain` value, commits, pushes.
**ArgoCD will auto-sync within ~30 seconds** (its default polling interval) and
patch the IngressRoute. Watch it:

```bash
kubectl -n cloudkitchen get ingressroute cloudkitchen \
  -o jsonpath='{.spec.routes[0].match}' ; echo
# Expect: ...Host(`cloudkitchen.<your-domain>`)...
```

---

## Step 6 — Test via your real domain

```bash
DOMAIN=cloudkitchen.<your-domain>

# Site loads
curl -I "http://$DOMAIN"

# Public API works
curl -s "http://$DOMAIN/api/restaurants" | head -c 200 ; echo
```

Open `http://cloudkitchen.<your-domain>` in your browser — the React UI loads.

---

## Step 7 — Full end-to-end smoke test against your domain

```bash
DOMAIN=cloudkitchen.<your-domain>
J='-H Content-Type:application/json'

# 1. Register a customer
curl -s -X POST $J -d '{"email":"cust@ck.io","password":"pass1234","role":"customer"}' \
  http://$DOMAIN/api/auth/register
CTOK=$(curl -s -X POST $J -d '{"email":"cust@ck.io","password":"pass1234"}' \
  http://$DOMAIN/api/auth/login | jq -r .token)

# 2. Register a restaurant-admin and create a restaurant
curl -s -X POST $J -d '{"email":"owner@ck.io","password":"pass1234","role":"restaurant-admin"}' \
  http://$DOMAIN/api/auth/register
ATOK=$(curl -s -X POST $J -d '{"email":"owner@ck.io","password":"pass1234"}' \
  http://$DOMAIN/api/auth/login | jq -r .token)
RID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" \
  -d '{"name":"Spice Hub","city":"Hyderabad","address":"MG Road"}' \
  http://$DOMAIN/api/restaurants | jq -r .id)

# 3. Add a menu item and order it
CATID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" -d '{"name":"Mains"}' \
  http://$DOMAIN/api/restaurants/$RID/categories | jq -r .id)
ITEMID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" \
  -d "{\"category_id\":\"$CATID\",\"name\":\"Chicken Biryani\",\"price\":250,\"available\":true}" \
  http://$DOMAIN/api/restaurants/$RID/items | jq -r .id)
curl -s -X POST $J -H "Authorization: Bearer $CTOK" \
  -d "{\"item_id\":\"$ITEMID\",\"name\":\"Chicken Biryani\",\"qty\":2,\"price\":250}" \
  http://$DOMAIN/api/cart/items
OID=$(curl -s -X POST $J -H "Authorization: Bearer $CTOK" -d "{\"restaurant_id\":\"$RID\"}" \
  http://$DOMAIN/api/orders | jq -r .id)
echo "ORDER=$OID"

# 4. Watch the async chain land
sleep 5
curl -s -H "Authorization: Bearer $CTOK" http://$DOMAIN/api/orders/$OID | jq '.status'         # ASSIGNED
curl -s -H "Authorization: Bearer $CTOK" http://$DOMAIN/api/payments/order/$OID | jq '.status' # SUCCESS
curl -s -H "Authorization: Bearer $CTOK" http://$DOMAIN/api/deliveries/order/$OID | jq '.status' # ASSIGNED
```

Identical flow to the local docker-compose test — but it's hitting your EKS
cluster via your domain through Traefik. **Real cloud deployment, working.** 🎉

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `curl http://$LB_DNS` returns 404 | Host header doesn't match `ingress.domain` | use `-H 'Host: cloudkitchen.example.com'` or update `ingress.domain` |
| DNS doesn't resolve | GoDaddy still propagating | wait 5-15 min, or `dig @8.8.8.8 cloudkitchen.<your-domain>` to bypass local resolver cache |
| Browser shows certificate warning | Expected — we're on HTTP, not HTTPS | Phase 7 adds TLS. Continue. |
| `dig` resolves but curl times out | LB security group / firewall | the Traefik LB is in public subnets with a default SG; verify `aws ec2 describe-security-groups` allows :80 from `0.0.0.0/0` |
| 200 via LB hostname, 502 via domain | DNS resolving to a stale IP | nuke local DNS cache (`sudo systemctl restart systemd-resolved` on Ubuntu) |
| ArgoCD didn't auto-sync after the values commit | Polling interval (default 3 min) | force: `kubectl -n argocd patch app cloudkitchen --type merge -p '{"operation":{"sync":{}}}'` |

---

## 📋 Phase 5 cheatsheet

```bash
# Grab LB hostname
LB_DNS=$(kubectl -n ingress get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Curl with host header
curl -s "http://$LB_DNS/api/restaurants" -H 'Host: cloudkitchen.example.com' | head

# After CNAME exists
DOMAIN=cloudkitchen.<your-domain>
curl -I "http://$DOMAIN"
dig +short $DOMAIN
```

---

## 🎉 What you accomplished

- ✅ Confirmed the entire deploy works end-to-end through the AWS LB.
- ✅ Created a GoDaddy CNAME so users can type a real URL.
- ✅ Updated `ingress.domain` in Git → ArgoCD synced the IngressRoute → real
  domain serves the app.
- ✅ Ran the full register → order → async event chain against your cloud
  deployment.

➡️ **Next:** [Phase 6 — Monitoring + logging](06-monitoring-and-logging.md)
