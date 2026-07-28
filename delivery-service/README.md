# delivery-service

CloudKitchen microservice. Go + Gin, clean architecture.

## Layout
- `cmd/`                 — entrypoint (`main.go`)
- `internal/handler/`    — Gin HTTP handlers (transport layer)
- `internal/service/`    — business logic
- `internal/repository/` — PostgreSQL data access
- `internal/model/`      — domain structs
- `internal/middleware/` — JWT auth, RBAC, logging, metrics
- `migrations/`          — SQL migrations for this service's schema
- `Dockerfile`           — multi-stage, non-root, distroless

## Run locally
```bash
go mod tidy
SERVICE_NAME=delivery-service PORT=8080 go run ./cmd
curl localhost:8080/healthz
```
