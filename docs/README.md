# CloudKitchen Documentation

Index of project documentation. Start here, then dive into the area you need.

## Architecture
- [Phase 1 Architecture](architecture/PHASE-1.md) — high-level design, flat repo
  layout, sync REST + async NATS JetStream communication, CI/CD, and GitOps flow.

## Platform area guides
- [Local deployment (docker-compose)](../docker/README.md) — run the whole
  stack on your machine.
- [Monitoring (Prometheus + Grafana)](../monitoring/README.md) — metrics and
  dashboards.
  - [Grafana dashboards](../monitoring/grafana/dashboards/README.md)
- [Logging (Loki + Promtail)](../logging/README.md) — centralized JSON logs.
- [Security](../security/README.md) — TLS, network policies, PSS, IRSA, secrets,
  image scanning.
- [Scripts](../scripts/) — `build-images.sh`, `seed.sh`, `port-forward-*.sh`,
  `kubeconfig.sh`.

## Top-level
- [Project README](../README.md) — overview, tech stack, quickstart, deployment.

## Conventions
- Every Go service listens on `:8080` and exposes `/metrics`, `/healthz`,
  `/readyz`, with structured JSON logs to stdout.
- Domain: `cloudkitchen.example.com` (placeholder). Region: AWS `us-east-1`.
- Namespaces: `cloudkitchen`, `monitoring`, `logging`, `ingress`, `argocd`.
