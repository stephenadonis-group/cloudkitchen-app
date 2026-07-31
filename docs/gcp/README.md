# Deploying CloudKitchen to GCP GKE — End-to-End Guide

A complete, **beginner-friendly**, hands-on guide that takes you from an empty
GCP project to **CloudKitchen running on GKE with HTTPS** on your own domain.

🎯 **Audience:** freshers / 1–2 years experienced DevOps engineers.
🪜 **Style:** every command explained, every gotcha documented. No
"just trust me" steps.

> This is the **GCP counterpart** of the [EKS guide](../eks/README.md).
> The two guides cover the same architecture and learning outcomes; only
> the underlying cloud differs. Pick the one that matches the cloud you
> have credits for.

---

## Where you'll end up

```
        🌐  https://cloudkitchen.<your-domain>             <- your app UI
        🌐  https://cloudkitchen.<your-domain>/argocd      <- ArgoCD UI
        🌐  https://cloudkitchen.<your-domain>/grafana     <- Grafana dashboards
        🌐  https://cloudkitchen.<your-domain>/prometheus  <- Prometheus UI
                              │
                              ▼
                    ┌──────────────────────┐
                    │ GCP TCP LoadBalancer │  (Traefik Service, single static IP)
                    └─────────┬────────────┘
                              ▼
              ┌────────────────────────────────┐
              │  GKE cluster (us-central1-a)   │
              │                                │
              │  Traefik  →  cloudkitchen ns   │
              │  (HTTPS)     (8 svcs + UI +    │
              │               PG + Redis +     │
              │               NATS)            │
              │                                │
              │  ArgoCD          (GitOps)      │
              │  Prometheus/Grafana (obs)      │
              │  Loki/Promtail   (logs)        │
              │  cert-manager    (TLS)         │
              └────────────────────────────────┘
                             ▲
                             │  GitOps sync
                ┌────────────┴───────────────┐
                │ GitHub repo (this one)     │
                │  CI builds & pushes →      │
                │  Artifact Registry +       │
                │  bumps values.yaml         │
                └────────────────────────────┘
```

---

## The phases

Follow them **in order**. Each phase is self-contained but builds on the
previous one.

| # | Phase                                                    | Goal                                       | Time     | What gets created                                                                                                  |
| - | -------------------------------------------------------- | ------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------------------------ |
| **1** | [Infra & jump VM](01-infra-and-jump-vm.md)           | GCP infra + access to the cluster          | ~20 min  | VPC + NAT, GKE (zonal, private nodes), Artifact Registry, IAM, bastion, kubeconfig                                 |
| **2** | [Traefik ingress controller](02-traefik-ingress.md)  | Public entrypoint into the cluster         | ~5 min   | Traefik pods (in `traefik` ns) + a GCP TCP LoadBalancer + an external IP                                           |
| **3** | [GitHub Actions CI](03-github-actions-cicd.md)       | Build & push images to Artifact Registry   | ~15 min  | GitHub secrets, first green CI run (after Trivy CVE iterations), images in AR with `:<short-sha>` + `:latest` tags |
| **4** | [ArgoCD deploys the app](04-argocd-deploy.md)        | GitOps deployment from this repo           | ~15 min  | ArgoCD installed; UI under `/argocd`; the `cloudkitchen` Application Synced + Healthy; 12 pods Running             |
| **5** | [DNS + GoDaddy](05-dns-and-godaddy.md)               | Point your domain at the LB IP             | ~15 min  | A record at GoDaddy; chart's IngressRoute updated for multi-host (hostname + IP); app reachable by domain         |
| **6** | [Monitoring + logging](06-monitoring-and-logging.md)   | Observability stack                        | ~25 min  | kube-prometheus-stack + Loki/Promtail; ServiceMonitor; 8 per-service Grafana dashboards; PrometheusRule (recording + alerts) |
| **7** | [HTTPS via cert-manager + Let's Encrypt](07-https-letsencrypt-and-routes.md) | Real TLS on the LB | ~15 min  | cert-manager + `letsencrypt-prod` ClusterIssuer; Certificate `cloudkitchen-tls`; HTTP→HTTPS catch-all redirect; all 5 UIs (app + argocd + grafana + prometheus + alertmanager) served over HTTPS |
| **8** | [PostgreSQL database guide](08-postgresql-database-guide.md) | Query the 12 tables / 8 schemas after deploy | ~5 min   | _(reference — no new cluster resources)_ — `kubectl exec` cheatsheet, per-schema queries, dashboard one-liners, optional `port-forward` for DBeaver/TablePlus |

---

## What's the same between EKS and GKE? What's different?

The **architecture is identical** at the Kubernetes layer:
- Same 8 Go microservices + React frontend
- Same NATS JetStream event chain
- Same Postgres schema-per-service
- Same Helm umbrella chart (`helm/cloudkitchen/`)
- Same ArgoCD App-of-Apps manifests (`argocd/`)
- Same GitHub Actions pipeline shape (matrix build → Trivy gate → push → bump values.yaml → ArgoCD detects)

Only the **cloud-specific edges** differ:

| Concern                  | EKS                                            | GKE                                                              |
| ------------------------ | ---------------------------------------------- | ---------------------------------------------------------------- |
| Terraform directory      | `aws-terraform/`                               | `gcp-terraform/`                                                 |
| Image registry           | ECR (9 separate repos)                         | Artifact Registry (1 repo, 9 image names)                        |
| CI auth                  | IAM access key in `secrets.AWS_*`              | SA JSON key in `secrets.GCP_SA_KEY`                              |
| CI workflow file         | `.github/workflows/ci.yaml` (disabled for now) | `.github/workflows/ci-gcp.yaml` (active)                         |
| Bastion access           | AWS SSM Session Manager                        | IAP tunnel (`gcloud compute ssh --tunnel-through-iap`)           |
| StorageClass             | `gp3` (EBS CSI)                                | `standard-rwo` (PD CSI)                                          |
| Default Traefik LB type  | NLB                                            | GCP TCP LoadBalancer                                             |
| Cost (idle cluster)      | ~$73/mo control plane + nodes                  | FREE control plane (first zonal cluster) + nodes                 |

---

## ❌ Don't commit these files

The repo's `.gitignore` already excludes them, but worth knowing:

- `gcp-sa.json`, `*-sa.json`, `*credentials*.json` (GCP SA keys)
- `.env`, `.env.*` (any local environment overrides)
- `**/terraform.tfstate*`, `**/.terraform/` (Terraform state — contains
  sensitive output values)
- `*.pem` (TLS keys)

> Pasting a service-account JSON or any key material into chat is **always**
> a mistake — even on a private repo, chat logs persist longer than you'd
> think. Use shell env vars (`export KEY_FROM_FILE=$(cat ~/secret.json)`) or
> `read -s` instead.

---

## Repo layout (relevant to GCP path)

| Path                          | Purpose                                                                            | Phase(s) |
| ----------------------------- | ---------------------------------------------------------------------------------- | -------- |
| `gcp-terraform/`              | GCP infrastructure (VPC/GKE/AR/IAM/bastion)                                        | 1        |
| `helm/cloudkitchen/`          | Umbrella Helm chart that ArgoCD deploys                                            | 4        |
| `.github/workflows/ci-gcp.yaml` | The active CI pipeline (build → Trivy → push to AR → bump values.yaml)            | 3        |
| `argocd/`                     | AppProject + Applications (App-of-Apps pattern)                                    | 4        |
| `docs/gcp/`                   | This guide                                                                         | all      |
| `docs/eks/`                   | Parallel guide for AWS                                                             | —        |
| `docs/ARCHITECTURE.md`        | Top-level architecture overview (cloud-agnostic, with mermaid diagrams)            | reference |

---

➡️ Start with **[Phase 1 — Infrastructure & Jump VM](01-infra-and-jump-vm.md)**.
