# CloudKitchen — Local Testing with Docker Compose

This guide explains how to run the **entire CloudKitchen platform on your own machine**
using Docker Compose — no Kubernetes, no AWS. It is the fastest way to verify the app
works before deploying to EKS.

> **Status:** ✅ Verified working end‑to‑end on 2026‑05‑27 (all 12 containers up,
> full order → payment → delivery → notification flow passing).

---

## What "local testing" runs

Docker Compose ([`docker/docker-compose.yml`](../docker/docker-compose.yml))
brings up **12 containers**: the 3 backing services + 8 Go microservices + the React
frontend (which doubles as a local API gateway).

| Container | Image | Host port → container | Purpose |
|-----------|-------|-----------------------|---------|
| postgres | `postgres:16` | `5432` → 5432 | one DB `cloudkitchen`, schema‑per‑service |
| redis | `redis:7` | `6379` → 6379 | cart + menu cache |
| nats | `nats:2.10-alpine` | `4222`, `8222` | JetStream event bus (+ HTTP monitoring) |
| auth | built | `8081` → 8080 | register/login/JWT |
| user | built | `8082` → 8080 | profiles/addresses |
| restaurant | built | `8083` → 8080 | restaurants |
| menu | built | `8084` → 8080 | categories/items/search |
| order | built | `8085` → 8080 | cart + orders |
| payment | built | `8086` → 8080 | mock payments |
| delivery | built | `8087` → 8080 | delivery assignment |
| notification | built | `8088` → 8080 | notification log |
| **frontend** | built (nginx) | **`3000`** → 8080 | **the UI + /api gateway** |

---

## Prerequisites

| Tool | Why | Check |
|------|-----|-------|
| Docker Engine | builds + runs the containers | `docker --version` |
| Docker Compose v2 | orchestrates the stack | `docker compose version` |
| Internet access | pulls base images + Go/npm deps on first build | — |

> **Go and Node are NOT required on your host** — everything compiles *inside* the
> Docker build. (We use a `golang` build stage for the services and a `node` build
> stage for the frontend.)

---

## Quick start

```bash
# from the repo root
docker compose -f docker/docker-compose.yml up --build -d
```

**What this does, flag by flag:**
- `-f docker/docker-compose.yml` — use this compose file (build contexts like
  `../auth-service` are relative to it).
- `up` — create and start all containers.
- `--build` — build the images first (needed the first time and after code changes).
- `-d` — detached (run in the background).

First build takes a few minutes (downloads Go modules, builds 8 services, runs
`npm install` + Vite). Subsequent builds are cached and fast.

### Open the UI

Once it's up: **http://localhost:3000**

The frontend's nginx serves the React app **and** reverse‑proxies `/api/*` to the
right backend (mirroring the Traefik IngressRoute used on Kubernetes), so the whole
app works through that single origin.

---

## Verify it's running

```bash
# all 12 containers should be "running" (postgres/redis/nats show "healthy")
docker compose -f docker/docker-compose.yml ps -a

# health endpoints (each service exposes /healthz, /readyz, /metrics)
for p in 8081 8082 8083 8084 8085 8086 8087 8088; do
  echo "$p -> $(curl -s -o /dev/null -w '%{http_code}' http://localhost:$p/healthz)"
done
```

### Full smoke test (the user journey)

This exercises auth + RBAC, the synchronous REST calls, the Redis cart, and the
asynchronous NATS JetStream event chain.

```bash
J='-H Content-Type:application/json'

# 1. Register + login a customer
curl -s -X POST $J -d '{"email":"cust@ck.io","password":"pass1234","role":"customer"}' \
  http://localhost:3000/api/auth/register
CTOK=$(curl -s -X POST $J -d '{"email":"cust@ck.io","password":"pass1234"}' \
  http://localhost:8081/api/auth/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

# 2. Register a restaurant-admin and create a restaurant
curl -s -X POST $J -d '{"email":"owner@ck.io","password":"pass1234","role":"restaurant-admin"}' \
  http://localhost:8081/api/auth/register
ATOK=$(curl -s -X POST $J -d '{"email":"owner@ck.io","password":"pass1234"}' \
  http://localhost:8081/api/auth/login | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
RID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" \
  -d '{"name":"Spice Hub","city":"Hyderabad","address":"MG Road"}' \
  http://localhost:8083/api/restaurants | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

# 3. Add a category + item
CATID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" -d '{"name":"Biryani"}' \
  http://localhost:8084/api/restaurants/$RID/categories | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
ITEMID=$(curl -s -X POST $J -H "Authorization: Bearer $ATOK" \
  -d "{\"category_id\":\"$CATID\",\"name\":\"Chicken Biryani\",\"price\":250,\"available\":true}" \
  http://localhost:8084/api/restaurants/$RID/items | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

# 4. Customer adds to cart and places the order
curl -s -X POST $J -H "Authorization: Bearer $CTOK" \
  -d "{\"item_id\":\"$ITEMID\",\"name\":\"Chicken Biryani\",\"qty\":2,\"price\":250}" \
  http://localhost:8085/api/cart/items
OID=$(curl -s -X POST $J -H "Authorization: Bearer $CTOK" -d "{\"restaurant_id\":\"$RID\"}" \
  http://localhost:8085/api/orders | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

# 5. Watch the async event flow land (PENDING -> ASSIGNED)
sleep 3
curl -s -H "Authorization: Bearer $CTOK" http://localhost:8085/api/orders/$OID         # order status
curl -s -H "Authorization: Bearer $CTOK" http://localhost:8086/api/payments/order/$OID # payment SUCCESS
curl -s -H "Authorization: Bearer $CTOK" http://localhost:8087/api/deliveries/order/$OID # delivery ASSIGNED
curl -s -H "Authorization: Bearer $CTOK" http://localhost:8088/api/notifications        # notifications
```

**Expected result:** the order moves from `PENDING` to `ASSIGNED`, a payment exists with
status `SUCCESS`, a delivery exists with an assigned agent, and a notification is logged —
proving the `order.placed → payment.completed → delivery.updated` NATS JetStream chain
works (internally published as subjects `cloudkitchen.order.placed`,
`cloudkitchen.payment.completed`, `cloudkitchen.delivery.updated` on the `CLOUDKITCHEN`
stream — the broker prepends `cloudkitchen.` automatically).

### Other UIs

- **NATS HTTP monitoring:** http://localhost:8222 (no auth — there's no web UI like
  RabbitMQ had; you get JSON endpoints such as `/healthz`, `/varz`, `/jsz`, `/streamz`,
  `/connz`). If you have the `nats` CLI installed locally, `nats --server localhost:4222
  stream ls` and `nats --server localhost:4222 consumer ls CLOUDKITCHEN` show the
  JetStream stream and durable consumers.
- **Postgres:** `psql postgresql://cloudkitchen:cloudkitchen@localhost:5432/cloudkitchen`

---

## Everyday commands

```bash
docker compose -f docker/docker-compose.yml ps -a          # container states
docker compose -f docker/docker-compose.yml logs -f auth   # follow one service's logs
docker compose -f docker/docker-compose.yml up --build -d  # rebuild + restart after code changes
docker compose -f docker/docker-compose.yml restart order  # restart one service
docker compose -f docker/docker-compose.yml down           # stop + remove containers (keeps volumes)
docker compose -f docker/docker-compose.yml down -v        # also delete DB/Redis/NATS data
```

---

## Important local-vs-Kubernetes differences

These are intentional adaptations so the stack runs without Kubernetes:

1. **No in‑container healthchecks for the app services.** The images are *distroless*
   (no shell, `wget`, or `curl`), so Compose can't run an HTTP healthcheck inside them.
   We check health from the host instead (the `/healthz` ports above). On Kubernetes the
   kubelet performs the liveness/readiness probes over HTTP, which works fine.
2. **The frontend nginx is the API gateway locally.** On EKS, Traefik routes `/api/*`.
   Locally, [`frontend/nginx.conf`](../frontend/nginx.conf) proxies those same paths to
   the service containers by name.
3. **NATS runs unauthenticated in dev.** The local NATS container accepts client
   connections on `nats://nats:4222` with no auth, and exposes HTTP monitoring on
   `:8222` (JSON only — no web UI). On EKS the same `NATS_URL` is reused; production
   hardening (NKeys/JWT auth, TLS) is out of scope for this guide.
4. **Secrets are dev placeholders** (`JWT_SECRET=local-dev-only-change-me`, DB password
   `cloudkitchen`). Never use these outside local testing.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| A service container keeps **restarting** | DB/NATS not ready, or a migration error | `docker compose ... logs <svc>` to see the error; ensure postgres/nats are `healthy` first |
| `/api/...` returns **404** through `:3000` | wrong path (the service 404s unknown routes) | confirm the exact route exists; health path is `/healthz`, not `/api/<svc>/healthz` |
| Build fails on `go build` (`missing go.sum`) | a service lacks `go.sum` | `docker run --rm -v "$PWD/<svc>":/app -w /app golang:1.23-alpine go mod tidy` |
| Service can't connect to NATS | `NATS_URL` wrong, or nats container not yet healthy | check `NATS_URL=nats://nats:4222` and `curl localhost:8222/healthz` returns `{"status":"ok"}` |
| Port already in use | something else owns 3000/5432/etc. | stop the other process or edit the host ports in the compose file |

---

## Fixes applied while validating local testing

The first end‑to‑end run surfaced (and we fixed) three real issues:

1. **Missing `go.sum`** for all 8 services → generated via a `golang:1.23` container and
   the Dockerfiles now `COPY go.mod go.sum ./`.
2. **Migration runner (auth/user/restaurant/menu)** read SQL from disk instead of the
   embedded filesystem → fixed to use `path.Join(dir, name)` so embedded paths resolve.
3. **Distroless healthcheck** used `wget` (absent) and the frontend couldn't reach the
   backends → removed the in‑container healthcheck and made nginx a local `/api` gateway.
