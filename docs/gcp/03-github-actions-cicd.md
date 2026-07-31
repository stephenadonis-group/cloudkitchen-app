# Phase 3 — GitHub Actions CI: Build Images & Bump Values (GCP)

**Goal:** Push this repo to GitHub, configure secrets + variables, and let the
CI pipeline (`.github/workflows/ci-gcp.yaml`) build all 9 container images,
scan them with Trivy, push them to **Artifact Registry**, and **commit the
new image tags back** into `helm/cloudkitchen/values.yaml`. ArgoCD (Phase 4)
takes it from there.

**Time:** ~15 minutes (~3 min CI per run; first run usually takes 2-3 iterations to clear all CVE gates — see Troubleshooting).

This is the **GCP counterpart** of [docs/eks/03-github-actions-cicd.md](../eks/03-github-actions-cicd.md).
The pipeline shape is identical; only the auth + registry steps differ:

| Concern              | EKS (`ci.yaml`, currently disabled)                          | GKE (`ci-gcp.yaml`, active)                                                                  |
| -------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| Auth                 | `aws-actions/configure-aws-credentials` + IAM access key     | `google-github-actions/auth@v2` + SA JSON key in `secrets.GCP_SA_KEY`                        |
| Registry login       | `aws-actions/amazon-ecr-login@v2`                            | `gcloud auth configure-docker us-central1-docker.pkg.dev`                                    |
| Image path           | `<acct>.dkr.ecr.us-east-1.amazonaws.com/cloudkitchen/<svc>:<sha>` | `us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/<svc>:<sha>`                |

---

## What & why

We separate **CI** (build & publish images) from **CD** (deploy to the
cluster). CI's only "deploy" action is a **git commit** of the new image
tags; ArgoCD reconciles that commit into the cluster. That's true **GitOps**.

```
       ┌───── git push to main ─────┐
       │                             │
       ▼                             │
  GitHub Actions matrix              │
  (build all 9 services in parallel) │
       │                             │
       ▼                             │
  Trivy image scan (HIGH/CRITICAL)   │
       │                             │
       ▼                             │
  Push to GCP Artifact Registry  ◀── AR repo (created by Terraform in Phase 1)
       │
       ▼
  yq bumps  helm/cloudkitchen/values.yaml  ──► commits back to main
                                                 │
                                                 ▼
                                       ArgoCD detects the commit  (Phase 4)
```

---

## ✅ Prerequisites

| Need                                                               | How to check / get                                                                                                            |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Phase 1 done (Terraform applied, AR repo exists)                   | `gcloud artifacts repositories describe cloudkitchen-registry --location=us-central1` returns the repo                        |
| The repo cloned + tracked in git                                   | `git status` works in the project root                                                                                        |
| A GitHub account + an empty repository created on GitHub.com       | https://github.com/new → owner: you, name: `cloudkitchen-app`, visibility: private (or public if you prefer), no README/license/.gitignore (we already have them) |
| GCP project ID handy                                               | `gcloud config get-value project`                                                                                             |

---

## Step 1 — Push the repo to GitHub

If you haven't already, link the local repo to the empty GitHub repo and push
`main`. Use whatever auth method you prefer (SSH key or HTTPS+PAT).

```bash
cd <repo-root>

# Initialize, configure identity, and connect to the empty GitHub repo
git init -b main
git config user.name "Your Name"
git config user.email "you@example.com"
git remote add origin git@github.com:<your-handle>/cloudkitchen-app.git

# .gitignore already protects gcp-sa.json, terraform state, .env, *.pem — verify:
git status   # gcp-sa.json should NOT appear

# Stage + commit + push
git add -A
git commit -m "Initial commit: CloudKitchen platform"
git push -u origin main
```

> ⚠️ **Before pushing the first commit**, eyeball `git ls-files --cached
> | grep -iE 'sa\.json$|tfstate|credentials|\.env$|\.pem$'` to be sure no
> secrets snuck in. The `.gitignore` in this repo covers the common cases,
> but it's worth one final check — secrets pushed to GitHub get indexed by
> bots within minutes, even on a private repo.

---

## Step 2 — Create a CI service account in GCP

The CI pipeline needs a credential to push images to Artifact Registry.
**Don't reuse your developer SA** — keep blast-radius small.

### Option A — Dedicated least-privilege SA (recommended)

```bash
PROJECT=<your-project-id>
SA=cloudkitchen-ci

# 1. Create the SA
gcloud iam service-accounts create ${SA} \
  --display-name="CloudKitchen GitHub Actions" \
  --project=${PROJECT}

# 2. Grant ONLY the role it needs: push to Artifact Registry
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# 3. Download a JSON key
gcloud iam service-accounts keys create gcp-ci-sa.json \
  --iam-account=${SA}@${PROJECT}.iam.gserviceaccount.com

# 4. cat the JSON — you'll paste this into the GitHub Secret in Step 3
cat gcp-ci-sa.json

# 5. (After Step 3) delete the local copy so it can't be leaked
shred -u gcp-ci-sa.json
```

If the key ever leaks, an attacker can **only push images to your AR repo**.
They can't delete clusters, read other GCS buckets, change IAM, etc.

### Option B — Reuse an existing Owner-role SA (acceptable for tear-down projects)

If you're running on a sandbox project you're going to delete soon, you can
reuse the same `gcp-sa.json` Terraform uses. Save 30 seconds, accept that the
key has Owner — high blast radius. Don't do this in prod.

---

## Step 3 — Configure GitHub Secrets + Variables

Open **Settings → Secrets and variables → Actions** on the GitHub repo.

### Secrets tab

| Secret         | Required | Value                                                                                                                                                                                                                        |
| -------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GCP_SA_KEY`   | Yes      | **Paste the entire `gcp-ci-sa.json` contents** — including the outer `{` and `}`, every line. GitHub stores it encrypted. Don't paste a base64-wrapped version; the auth action expects raw JSON.                            |
| `GITOPS_TOKEN` | Optional | PAT with `contents:write` if branch protection blocks `GITHUB_TOKEN`'s default push (we don't have protection enabled here, so omit this).                                                                                  |

### Variables tab

| Variable         | Value                                  | Example                                                                                                       |
| ---------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `GCP_PROJECT_ID` | Your GCP project                       | `project-d31a3358-346c-40e8-bda`                                                                              |
| `GCP_REGION`     | Region of the AR repo                  | `us-central1`                                                                                                 |
| `AR_REPO`        | Name of the Artifact Registry repo    | `cloudkitchen-registry`                                                                                       |

The workflow composes the final registry host as `${GCP_REGION}-docker.pkg.dev`
and the full image prefix as
`${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO}/<service>:<sha>`.

---

## Step 4 — Configure repo workflow permissions

By default GitHub Actions can read repo contents but **cannot push**. The
`update-gitops` job needs to push the values.yaml bump as a bot commit, so:

**Settings → Actions → General → Workflow permissions → Read and write**

(Alternatively, set `secrets.GITOPS_TOKEN` to a fine-grained PAT with
`contents:write` and skip this step — but the project default is simpler.)

---

## Step 5 — Trigger the first run

The workflow has `paths:` filters on the service directories. To trigger,
either:

1. Push a change to **any service** directory or to
   `.github/workflows/ci-gcp.yaml`, OR
2. Manually trigger via **Actions → CI (GCP / Artifact Registry) → Run workflow**.

```bash
# Trivial change to drive the loop:
echo "// trigger ci" >> auth-service/cmd/main.go
git add auth-service/cmd/main.go
git commit -m "trigger ci"
git push origin main
```

Then watch https://github.com/<your-handle>/cloudkitchen-app/actions.

---

## Step 6 — What a green run looks like

A successful run produces:

1. **9 build jobs** (one per service), each ~90 s. Steps inside:
   - Checkout source
   - `Compute short SHA` (7-char tag for the image)
   - Authenticate to GCP using `GCP_SA_KEY`
   - `gcloud auth configure-docker us-central1-docker.pkg.dev`
   - `docker buildx build` → image loaded locally
   - **Trivy scan** — fails if any HIGH/CRITICAL CVE with a known fix is present
   - `docker push` to `<host>/<project>/cloudkitchen-registry/<svc>:<sha>` + `:latest`
2. **1 `update-gitops` job** that runs *after all 9 builds succeed*:
   - Checks out `main` with write token
   - Installs `yq`
   - For each service, sets the `image:` field in `helm/cloudkitchen/values.yaml`
     using the camelCase key pattern (`auth-service` → `authService`)
   - Commits as `cloudkitchen-ci[bot]` with message
     `ci(gitops): bump image tags to <sha> [skip ci]`
   - Pushes back to `main`

After the run you should see:
- The bot commit on the repo's history
- Fresh image tags in Artifact Registry:
  ```bash
  gcloud artifacts docker images list \
    us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/auth-service \
    --limit=3
  ```
- ArgoCD (next phase) detecting the bot commit and rolling pods

> ⏱️ **Real timing from `cloudkitchen-dev-01`:** trigger commit at `t=0`,
> 9 parallel builds finish at `t=~110s`, bot commit lands at `t=~120s`,
> ArgoCD-detected + pod rolled by `t=~150s`. Total **~2.5 min**
> push-to-rolled-pod.

---

## How the journey actually went on `cloudkitchen-dev-01` (so you skip our mistakes)

Our first 4 CI runs failed in increasingly subtle ways before we got green.
This is a real sequence — not theoretical — and worth knowing about so you
recognize each symptom:

| # | Failed step                  | Root cause                                                                                                                       | Fix that worked                                                                                                                                                                                                            |
| - | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | "Set up job"                 | `aquasecurity/trivy-action@0.24.0` — version pin without the `v` prefix. That tag never existed.                                 | Bump to `@v0.36.0`. The action's repo uses `v0.XX.X`, not bare `0.XX.X`.                                                                                                                                                   |
| 2 | "Trivy image scan" (all 9)   | Go stdlib CVEs (`CVE-2026-39836`, `CVE-2026-42499`) baked into binaries built with `golang:1.23-alpine`.                         | Bump the build base in all 8 Go Dockerfiles to `golang:1.26-alpine`. (`go.mod` stays `go 1.23` — it's a min-features pin, not a toolchain pin.) Also bumped `node:20-alpine` → `node:22-alpine` for the frontend.            |
| 3 | "Trivy image scan" (all 8 Go) | `golang.org/x/crypto` v0.31.0 had a known ssh DoS CVE (`CVE-2025-22869`). Frontend had `libxml2` HIGH in `nginx:alpine` base.    | Inside each service: `go get golang.org/x/crypto@v0.35.0 && go mod tidy` (run inside `golang:1.26-alpine` so the result matches CI). For frontend: add `RUN apk update && apk upgrade --no-cache` in the runtime stage.   |
| 4 | "Trivy image scan" (all 8 Go) | Two more direct-dep CVEs surfaced: golang-jwt v5.2.1 (excessive memory in header parse) and pgx v5.7.1 (memory-safety).         | `go get github.com/golang-jwt/jwt/v5@v5.2.2 github.com/jackc/pgx/v5@v5.9.0 && go mod tidy`. Pre-pushed verification: `go build ./cmd` inside `golang:1.26-alpine` on all 8 (caught no breaking API change from pgx 5.7→5.9). |
| ✅ | (all green)                  | —                                                                                                                                | Build matrix green, update-gitops bumped values.yaml, ArgoCD picked it up.                                                                                                                                                 |

Lesson: when adding a brand-new Trivy gate to a project, expect the first
1–2 runs to be red and treat each finding as a real backlog item. Once the
CVE list converges to zero, **keep it converging** — every dependency bump
from now on goes through this same gate.

---

## Troubleshooting

| Symptom                                                                                            | Likely cause                                                                                                                            | Fix                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Error: Unable to resolve action ...trivy-action@0.24.0, unable to find version '0.24.0'`           | Action tag doesn't exist. The `aquasecurity/trivy-action` repo uses `v0.XX.X` (with `v`) — bare `0.24.0` was never a tag.                | Pin to `aquasecurity/trivy-action@v0.36.0` (or whatever the current latest is).                                                                                                                                                    |
| `google-github-actions/auth` step fails with `failed to retrieve credentials ... invalid character` | `GCP_SA_KEY` was pasted base64-encoded, or with leading/trailing whitespace, or only partial JSON.                                       | Re-paste raw JSON exactly as `cat gcp-sa.json` produces it, including the outer `{` and `}`. No `base64 ... | pbcopy` indirection.                                                                                                  |
| `denied: Permission "artifactregistry.repositories.uploadArtifacts" denied`                        | CI SA missing `roles/artifactregistry.writer` on the project.                                                                            | `gcloud projects add-iam-policy-binding <project> --member="serviceAccount:<ci-sa>@..." --role="roles/artifactregistry.writer"`                                                                                                    |
| `denied: requested access to the resource is denied` (after a successful login)                    | The AR repository name in `vars.AR_REPO` doesn't match what actually exists in GCP.                                                      | `gcloud artifacts repositories list --location=<region>` — make sure the name + region match the variables.                                                                                                                        |
| Trivy reports HIGH/CRITICAL CVEs                                                                   | A dependency in `go.sum`, a Go stdlib version, or a base OS package has a known vuln with a fix.                                          | Read the CVE detail. If it's stdlib → bump `golang:X-alpine`. If it's `go.sum` → `go get <mod>@<fixed-ver> && go mod tidy`. If it's an OS package → `RUN apk upgrade --no-cache` in the runtime stage.                            |
| `update-gitops` step → `remote: Permission to ...: Resource not accessible by integration`        | Workflow permissions set to "Read only", so the default `GITHUB_TOKEN` can't push.                                                       | Settings → Actions → General → Workflow permissions = **Read and write**. (Or set `secrets.GITOPS_TOKEN` to a PAT with `contents:write`.)                                                                                          |
| Bot commit lands but ArgoCD doesn't roll the pod                                                   | Either ArgoCD's repo poller hasn't fired yet (default 3 min interval), or `path:` filter on the Application doesn't include `helm/cloudkitchen/values.yaml` | Click "Refresh" on the ArgoCD UI to force a sync immediately. If still nothing — check the Application's `source.path` is `helm/cloudkitchen`.                                                                                    |
| The same image tag is being pushed every run                                                       | `cancel-in-progress` cancelled the previous run mid-build, leaving a stale `:latest` tag                                                  | Normal. The `:<sha>` tag is what ArgoCD watches, and that's always fresh. `:latest` is informational.                                                                                                                              |

---

➡️ **Next:** [Phase 4 — ArgoCD Deploy](04-argocd-deploy.md)
