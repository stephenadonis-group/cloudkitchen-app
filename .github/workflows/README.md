# CloudKitchen GitHub Actions

CI/CD for the CloudKitchen platform. The pipeline **builds, scans, and pushes**
container images, then **updates image tags in git** for ArgoCD to deploy. It
never runs `helm upgrade` or `kubectl apply` — deployment is ArgoCD's job.

Two cloud-specific pipelines coexist in this repo (same shape, different
registry/auth). Only one is active at a time, controlled by its `on:` trigger.

## Workflows

| File              | Cloud | Trigger                                                                          | Purpose                                                                                       |
| ----------------- | ----- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **`ci-gcp.yaml`** ✅ | GCP   | push to `main`, PRs (on service dirs **or** `helm/cloudkitchen/**`)              | Matrix build of all 9 services → Trivy image scan → push to **Artifact Registry** → bump tags |
| `ci.yaml`         | AWS   | **manual only** (`workflow_dispatch`) — disabled until AWS account is set up     | Matrix build → Trivy → push to **ECR** → bump tags                                            |
| `trivy-fs.yaml`   | —     | pull requests                                                                    | Trivy filesystem + config/IaC scan; uploads SARIF; fails PR on HIGH/CRITICAL                  |

### What triggers `ci-gcp.yaml`

| You changed                                       | `ci-gcp.yaml` runs?                                                |
| ------------------------------------------------- | ------------------------------------------------------------------ |
| Service code (e.g. `auth-service/cmd/main.go`)    | ✅                                                                 |
| Helm chart (e.g. `helm/cloudkitchen/values.yaml`) | ✅ — yes, rebuilds all 9 images even though their contents didn't change. Keeps the workflow simple + predictable. |
| ArgoCD App spec (`argocd/apps/*.yaml`)            | ❌ — applied directly with `kubectl apply`                          |
| Workflow file itself                              | ✅                                                                 |

To **switch the active cloud**: re-enable the `push`/`pull_request` triggers in
the other file's `on:` block, and disable the currently-active one by replacing
its `on:` with `workflow_dispatch: {}`. Don't enable both at once — the
`update-gitops` job in each writes to the same `helm/cloudkitchen/values.yaml`
and last-writer-wins.

### Common job shape (both `ci-gcp.yaml` and `ci.yaml`)

1. **build** — matrix over the 9 services (`auth-service`, `user-service`,
   `restaurant-service`, `menu-service`, `order-service`, `payment-service`,
   `delivery-service`, `notification-service`, `frontend`). Builds run in
   parallel. Each: build image locally → Trivy scan (fail on HIGH/CRITICAL) →
   push `:<short-sha>` and `:latest` to the cloud registry. **PRs build + scan
   only; they do not push.**
2. **update-gitops** (`needs: build`, push to `main` only) — uses `yq` to set
   the full `image:` string for each service in `helm/cloudkitchen/values.yaml`,
   then commits and pushes the change. ArgoCD reconciles the new tags into the
   cluster.

---

## Required configuration — GCP (`ci-gcp.yaml`)

Configure under **Settings → Secrets and variables → Actions**.

### Secrets

| Secret         | Required | Description                                                                                                                                                                                                            |
| -------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GCP_SA_KEY`   | Yes      | Full JSON key file for a service account with `roles/artifactregistry.writer` on the project (push images to AR). Paste the entire JSON, including the `{...}` braces.                                                 |
| `GITOPS_TOKEN` | Optional | PAT with `contents: write` on this repo, used to push the GitOps tag commit. Only needed if branch protection blocks the default `GITHUB_TOKEN`. Falls back to `GITHUB_TOKEN`.                                         |

### Variables

| Variable         | Required | Example                                | Description                                                                                                              |
| ---------------- | -------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `GCP_PROJECT_ID` | Yes      | `project-d31a3358-346c-40e8-bda`       | GCP project hosting the Artifact Registry repo.                                                                          |
| `GCP_REGION`     | Yes      | `us-central1`                          | Region of the Artifact Registry repo. Also used to compute the registry host (`<region>-docker.pkg.dev`).                |
| `AR_REPO`        | Yes      | `cloudkitchen-registry`                | Name of the Artifact Registry **repository** (single repo, multiple images live inside it — one per service).            |

### GCP one-time setup

1. **Create the Artifact Registry repo** (skip if it already exists):
   ```bash
   gcloud artifacts repositories create cloudkitchen-registry \
     --repository-format=docker \
     --location=us-central1 \
     --description="CloudKitchen container images"
   ```
2. **Service account** — either:
   - Reuse an existing SA that has `roles/artifactregistry.writer` (or `roles/owner`), and download its JSON key:
     ```bash
     gcloud iam service-accounts keys create gcp-sa.json \
       --iam-account=cloudkitchen-sa@<project>.iam.gserviceaccount.com
     ```
   - Or create a dedicated, least-privilege CI SA (recommended for shared accounts):
     ```bash
     SA=cloudkitchen-ci
     gcloud iam service-accounts create $SA --display-name="CloudKitchen GitHub Actions"
     gcloud projects add-iam-policy-binding <project> \
       --member="serviceAccount:${SA}@<project>.iam.gserviceaccount.com" \
       --role="roles/artifactregistry.writer"
     gcloud iam service-accounts keys create gcp-sa.json \
       --iam-account=${SA}@<project>.iam.gserviceaccount.com
     ```
3. **Paste the JSON** — open `gcp-sa.json`, copy the entire contents, paste into
   the GitHub Secret `GCP_SA_KEY`. Then delete the local file (or keep it
   gitignored — `.gitignore` already excludes `gcp-sa.json`).

> Security note: static long-lived JSON keys are convenient but should be
> rotated and scoped to AR-only. Workload Identity Federation (OIDC, keyless)
> is the more secure alternative — swap in `google-github-actions/auth@v2`'s
> `workload_identity_provider`/`service_account` inputs when you're ready.

---

## Required configuration — AWS (`ci.yaml`, currently disabled)

| Secret                  | Required | Description                                                                                                                                                              |
| ----------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AWS_ACCESS_KEY_ID`     | Yes      | Access key ID of the IAM user used by CI. Needs ECR push permissions (see policy below).                                                                                 |
| `AWS_SECRET_ACCESS_KEY` | Yes      | Secret access key paired with `AWS_ACCESS_KEY_ID`.                                                                                                                       |
| `GITOPS_TOKEN`          | Optional | Same as above — PAT with `contents: write`. Falls back to `GITHUB_TOKEN`.                                                                                                |

| Variable       | Required | Example                                                  | Description                                                          |
| -------------- | -------- | -------------------------------------------------------- | -------------------------------------------------------------------- |
| `ECR_REGISTRY` | Yes      | `123456789012.dkr.ecr.us-east-1.amazonaws.com`           | ECR registry host. Images push to `<ECR_REGISTRY>/cloudkitchen/<service>`. |

`AWS_REGION` (`us-east-1`) and the ECR image prefix (`cloudkitchen`) are
hard-coded as `env` in `ci.yaml`.

### AWS IAM user prerequisites (one-time)

1. Create a dedicated IAM user for CI (e.g. `cloudkitchen-github-ci`) with
   **programmatic access** (no console login).
2. Attach a policy granting ECR push/pull:
   `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`,
   `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`,
   `ecr:PutImage`, `ecr:BatchGetImage`.
3. Create an access key for that user and store the two values as the GitHub
   Secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
4. Ensure each `cloudkitchen/<service>` ECR repository exists (create them via
   the Terraform `ecr` module in `aws-terraform/`).
5. Re-enable the `push`/`pull_request` triggers in `ci.yaml` (currently commented
   out). At the same time, disable `ci-gcp.yaml` by replacing its `on:` block
   with `workflow_dispatch: {}` so the two don't fight over `values.yaml`.

---

## `values.yaml` image convention

`update-gitops` maps each service directory (`auth-service`) to its **camelCase**
key (`authService`) and sets the full `image:` string in
`helm/cloudkitchen/values.yaml`:

```yaml
authService:
  image: us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/auth-service:<short-sha>
userService:
  image: us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/user-service:<short-sha>
# ... one block per service (+ frontend)
```

This matches the flat, explicit `values.yaml` used by `helm/cloudkitchen`.

---

## Notes

- The GitOps commit message contains `[skip ci]` to avoid an infinite CI loop
  (the tag-bump commit only touches `helm/cloudkitchen/values.yaml`, which is
  outside the `paths` filter, but `[skip ci]` is a belt-and-braces safeguard).
- Pinned action versions (`aquasecurity/trivy-action@0.24.0`,
  `mikefarah/yq@v4.44.3`, `google-github-actions/auth@v2`, etc.) should be
  bumped deliberately.
