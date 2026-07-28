# CloudKitchen GitOps (ArgoCD)

This directory holds the **App-of-Apps** GitOps configuration for the CloudKitchen
platform. ArgoCD is the single source of truth for what runs in the cluster.
CI/CD (GitHub Actions) **never** deploys directly — it only commits updated image
tags to `helm/cloudkitchen/values.yaml`, and ArgoCD reconciles the change.

## Layout

```
argocd/
├── project.yaml              # AppProject "cloudkitchen" (repo/namespace/kind guardrails)
├── root-app.yaml             # Root Application (App-of-Apps) -> watches argocd/apps
├── apps/
│   ├── app-cloudkitchen.yaml # Umbrella Helm chart (microservices) -> ns cloudkitchen
│   ├── app-traefik.yaml      # Ingress controller            -> ns ingress
│   ├── app-cert-manager.yaml # TLS certificate management    -> ns ingress
│   ├── app-monitoring.yaml   # kube-prometheus-stack         -> ns monitoring
│   └── app-logging.yaml      # Loki + Promtail               -> ns logging
└── README.md
```

The root Application points at `argocd/apps/`. Every Application file there is
discovered and managed automatically, so adding a new add-on is just a new file.

## Before you start

Replace the placeholder repo URL in these files with your real Git repository:

- `argocd/project.yaml` (`sourceRepos`)
- `argocd/root-app.yaml` (`source.repoURL`)
- `argocd/apps/app-cloudkitchen.yaml` (`source.repoURL`)

(Search the tree for `https://github.com/cloudkitchen/cloudkitchen` — every
occurrence is flagged with a `<-- REPLACE` comment.)

## Bootstrap

```bash
# 1. Create the argocd namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Wait for the control plane to be ready
kubectl -n argocd rollout status deploy/argocd-server

# 3. Apply the AppProject guardrails, then the root App-of-Apps
kubectl apply -n argocd -f argocd/project.yaml
kubectl apply -n argocd -f argocd/root-app.yaml

# 4. (Optional) log in to the UI/CLI and trigger an initial sync
#    Get the initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
#    Then either watch automated sync, or force it:
argocd app sync cloudkitchen-root
```

Because every Application has `syncPolicy.automated` (prune + selfHeal),
ArgoCD continuously reconciles the cluster to match git — no manual `sync`
is normally required after the initial bootstrap.

## How deployments flow

1. Developer merges to `main`.
2. GitHub Actions builds + scans + pushes images to ECR, then commits the new
   image strings into `helm/cloudkitchen/values.yaml`.
3. ArgoCD detects the git change on the `cloudkitchen` Application and rolls
   out the new images into the `cloudkitchen` namespace.

## Multiple environments

This setup renders the chart directly from `helm/cloudkitchen/values.yaml` (no
per-env value files). To run a separate staging/prod environment, deploy this
repo to a different cluster/branch, or fork the chart values. Consider disabling
`automated` sync for prod and using manual/gated promotion.
