# Local Deployment (docker-compose)

Spin up the entire CloudKitchen stack locally: PostgreSQL, Redis, NATS (JetStream), all
8 Go microservices, and the React frontend.

## Prerequisites
- Docker + Docker Compose v2 (`docker compose`)
- Run commands from the **repo root** (build contexts are `../<service>`)

## Start

```sh
# from repo root
docker compose -f docker/docker-compose.yml up --build
```

Add `-d` to run detached. Stop with `docker compose -f docker/docker-compose.yml down`
(add `-v` to also drop the postgres/redis/nats volumes).

## Service URLs

| Component      | URL                      | Notes |
|----------------|--------------------------|-------|
| Frontend       | http://localhost:3000    | React app (nginx) |
| auth           | http://localhost:8081    | `/healthz` `/readyz` `/metrics` |
| user           | http://localhost:8082    | |
| restaurant     | http://localhost:8083    | |
| menu           | http://localhost:8084    | |
| order          | http://localhost:8085    | |
| payment        | http://localhost:8086    | |
| delivery       | http://localhost:8087    | |
| notification   | http://localhost:8088    | |
| PostgreSQL     | localhost:5432           | cloudkitchen / cloudkitchen |
| Redis          | localhost:6379           | |
| NATS client    | localhost:4222           | no auth (dev) |
| NATS monitor   | http://localhost:8222    | HTTP JSON endpoints (`/healthz`, `/varz`, `/streamz`) — no web UI |

> Each backend container listens on **8080** internally; the host ports above
> map to that. Inside the compose network services reach each other by name
> (e.g. `http://order:8080`, `postgres:5432`, `redis:6379`, `nats:4222`).

## Startup ordering

Backing services expose healthchecks; the backend services `depend_on` them
with `condition: service_healthy`, and the frontend depends on the core
services being healthy. Compose therefore brings things up in the right order.

## Test it

```sh
# health of every backend service
for p in 8081 8082 8083 8084 8085 8086 8087 8088; do
  echo "port $p:"; curl -s localhost:$p/healthz; echo
done

# seed demo data (users, restaurant, menu, an order) — see scripts/seed.sh
./scripts/seed.sh
```

## Environment

Defaults are baked into `docker-compose.yml` for convenience. To override, copy
`security/.env.example` to `.env` at the repo root and edit; compose will pick
it up. The local `JWT_SECRET` and DB credentials are throwaway dev values — do
not reuse them anywhere real.
