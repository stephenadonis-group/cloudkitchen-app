# Security

Security posture for the CloudKitchen platform across build, deploy, and
runtime.

## Contents

| Path                          | Purpose |
|-------------------------------|---------|
| `cert-manager/clusterissuer.yaml` | Let's Encrypt staging + prod ClusterIssuers (HTTP-01 via Traefik) |
| `cert-manager/certificate.yaml`   | TLS cert for `cloudkitchen.example.com` -> `cloudkitchen-tls` Secret |
| `network-policies.yaml`       | default-deny + scoped allow rules for the `cloudkitchen` ns |
| `pod-security.md`             | Restricted PSS labels + compliant `securityContext` example |
| `trivy.md`                    | CI scanning gate + optional trivy-operator |
| `secret.example.yaml`         | Example Secret shape + External Secrets / Sealed Secrets notes |
| `.env.example`                | Local-dev env template (copy to gitignored `.env`) |

## Posture summary

### 1. Non-root, hardened containers
All services run under the **restricted** Pod Security Standard: `runAsNonRoot`,
dropped capabilities, no privilege escalation, `RuntimeDefault` seccomp, and a
read-only root filesystem. Images are minimal (distroless/scratch). See
`pod-security.md`.

### 2. IRSA (IAM Roles for Service Accounts)
Workloads that talk to AWS (S3 for Loki chunks, Secrets Manager via External
Secrets, ECR, etc.) authenticate with **IRSA** — no long-lived AWS keys in the
cluster. Each ServiceAccount is annotated with its scoped IAM role ARN; the EKS
OIDC provider brokers short-lived credentials.

### 3. Secrets management
No real secrets are committed. Locally, `.env` (gitignored) is used. In-cluster,
secrets come from **External Secrets Operator** (backed by AWS Secrets Manager
via IRSA) or **Sealed Secrets**. `secret.example.yaml` documents the shape only.

### 4. Network policies
The `cloudkitchen` namespace is **default-deny** for ingress and egress. Explicit
allow rules permit: DNS, ingress from Traefik to `:8080`, intra-namespace
service-to-service REST, and egress to PostgreSQL/Redis/NATS. See
`network-policies.yaml`.

### 5. TLS everywhere at the edge
cert-manager issues and auto-renews Let's Encrypt certificates via the HTTP-01
challenge solved by Traefik. The public domain `cloudkitchen.example.com` is
served over HTTPS using the `cloudkitchen-tls` Secret. Validate against the
**staging** issuer first, then flip to `letsencrypt-prod`.

### 6. Image scanning
Every image is scanned with **Trivy** in CI (HIGH/CRITICAL with a fix blocks the
ECR push) and optionally re-scanned at runtime by **trivy-operator**. See
`trivy.md`.

## Apply order (cluster)

Namespaces are auto-created by ArgoCD (`syncOptions: CreateNamespace=true`)
and by each `helm install … --create-namespace`, so no manual namespace
manifest is needed. If you want **restricted Pod Security Standards** on the
`cloudkitchen` namespace (recommended for prod), label it after creation:

```sh
kubectl label namespace cloudkitchen \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted --overwrite
```

Then apply the security manifests:

```sh
kubectl apply -f security/cert-manager/clusterissuer.yaml
kubectl apply -f security/cert-manager/certificate.yaml
kubectl apply -f security/network-policies.yaml
# secrets come from External Secrets / Sealed Secrets, not committed manifests
```
