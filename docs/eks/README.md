# Deploying CloudKitchen to AWS EKS — End-to-End Guide

A complete, **beginner-friendly**, hands-on guide that takes you from an empty
AWS account to **CloudKitchen running on EKS with HTTPS** on your own domain.

🎯 **Audience:** freshers / 1–2 years experienced DevOps engineers.
🪜 **Style:** every command explained. No "just trust me" steps.

---

## Where you'll end up

```
        🌐  https://cloudkitchen.<your-domain>            <- your app UI
        🌐  https://cloudkitchen.<your-domain>/argocd     <- ArgoCD UI
        🌐  https://cloudkitchen.<your-domain>/grafana    <- Grafana dashboards
        🌐  https://cloudkitchen.<your-domain>/prometheus <- Prometheus UI
                              │
                              ▼
                    ┌──────────────────┐
                    │ AWS Network LB   │  (Traefik service)
                    └────────┬─────────┘
                             ▼
              ┌────────────────────────────┐
              │  EKS cluster (us-east-1)   │
              │                            │
              │  Traefik  →  cloudkitchen ns│
              │  (HTTPS)     (8 svcs + UI + │
              │               PG + Redis +  │
              │               NATS)         │
              │                            │
              │  ArgoCD       (GitOps)     │
              │  Prometheus/Grafana (obs)  │
              │  Loki/Promtail (logs)      │
              │  cert-manager (TLS)        │
              └────────────────────────────┘
                             ▲
                             │  GitOps sync
                ┌────────────┴────────────┐
                │ GitHub repo (this one)  │
                │  CI builds & pushes →   │
                │  ECR + bumps values.yaml│
                └─────────────────────────┘
```

---

## The 7 phases

Follow them **in order**. Each phase is self-contained but builds on the
previous one.

| # | Phase | Goal | Time | What gets created |
|---|-------|------|------|---------|
| **1** | [Infra & jump VM](01-infra-and-jump-vm.md) | AWS infra + access to the cluster | ~25 min | VPC, EKS, ECR, IAM, bastion, kubeconfig |
| **2** | [Traefik ingress controller](02-traefik-ingress.md) | Public entrypoint into the cluster | ~5 min | Traefik pods + an AWS Load Balancer |
| **3** | [GitHub Actions CI](03-github-actions-cicd.md) | Build & push images to ECR | ~10 min | GitHub secrets, first green CI run, ECR images |
| **4** | [ArgoCD deploys the app](04-argocd-deploy.md) | GitOps deployment from this repo | ~10 min | ArgoCD installed; CloudKitchen Application syncing; ~12 pods Running |
| **5** | [Traefik DNS + GoDaddy](05-traefik-dns-and-godaddy.md) | Smoke test + point your domain | ~15 min | App reachable via your domain (HTTP) |
| **6** | [Monitoring + logging](06-monitoring-and-logging.md) | Observability stack | ~15 min | kube-prometheus-stack + Loki/Promtail + ServiceMonitors + PrometheusRules + Grafana dashboards |
| **7** | [HTTPS + path routing](07-https-letsencrypt-and-routes.md) | Real HTTPS + ArgoCD/Grafana/Prometheus on the same domain | ~15 min | cert-manager + Let's Encrypt certificate + sub-path IngressRoutes |

---

## Before you start

| Tool | Why | Quick check |
|------|-----|-------------|
| AWS account | obvious | you can log into the AWS console |
| **IAM user with AdminAccess** (for learning) | Terraform creates many resource types | `aws sts get-caller-identity` after `aws configure` |
| **A domain** (GoDaddy, Route53, etc.) | for the friendly URL + HTTPS | you own it and can edit DNS |
| Terraform ≥ 1.5, AWS CLI v2, kubectl, helm | local CLI work | `--version` on each |
| Git + GitHub account | the repo + Actions runner | this repo pushable to your account |
| About **$5–$10** in AWS credit | EKS isn't free | OK with the bill |

---

## 💸 Cost snapshot

EKS in `us-east-1` for the small footprint this guide uses:

| Item | ~Cost |
|------|-------|
| EKS control plane | $2.40 / day |
| 2× t3.medium nodes | $2 / day |
| NAT gateway | $1.10 / day |
| AWS Load Balancer (Traefik) | $0.50 / day |
| EBS volumes (Postgres/NATS) | a few cents |
| **Total while running** | **~\$6 / day** |

**Stop billing instantly:** `terraform destroy` (Phase 1's folder) tears down
everything in ~10 minutes. Run it whenever you stop working.

---

## How to read each phase doc

Every phase doc has the **same structure**:

1. **What & why** — plain-language intro.
2. **Prerequisites** — what must be true before you start this phase.
3. **Step-by-step** — every command with a "what this does" explanation.
4. **Verify** — exactly how to confirm the phase succeeded (expected output).
5. **Troubleshooting** — a table of common errors + fixes.
6. **Recap & next** — what you just achieved + link to the next phase.

---

## House rules

- ✅ Always run `aws sts get-caller-identity` before any AWS command, to confirm
  *which* account you're talking to.
- ✅ Read `terraform plan` output before `apply` — every time.
- ✅ Run `terraform destroy` when you stop for the day to keep the bill near zero.
- ❌ **Don't commit secrets** — `terraform.tfvars`, `.kube/config`, AWS access
  keys, etc.

---

## Reference: project layout (what gets used by which phase)

| Folder | Purpose | Used by phase |
|--------|---------|---------------|
| `aws-terraform/` | AWS infra (VPC/EKS/ECR/IAM/bastion) | 1 |
| `helm/cloudkitchen/` | the umbrella chart | 4, 5, 7 |
| `.github/workflows/` | CI: build → ECR → bump values.yaml | 3 |
| `argocd/` | ArgoCD Application + AppProject | 4 |
| `monitoring/` | Prometheus/Grafana values + dashboards | 6 |
| `logging/` | Loki + Promtail values | 6 |
| `security/cert-manager/` | ClusterIssuer + Certificate manifests | 7 |

---

➡️ **Ready?** Start with **[Phase 1 — Infra & jump VM](01-infra-and-jump-vm.md)**.
