# Phase 3 — GitHub Actions CI: Build Images & Bump Values

**Goal:** Push this repo to GitHub, configure secrets, and let the
**CI pipeline** (`.github/workflows/ci.yaml`) build all 9 container images,
scan them with Trivy, push them to ECR, and **commit the new image tags back**
into `helm/cloudkitchen/values.yaml`. ArgoCD (Phase 4) takes it from there.

**Time:** ~10 minutes (most of it waiting for the first CI run).

---

## What & why

We separate **CI** (build & publish images) from **CD** (deploy to the
cluster). CI's only "deploy" action is a **git commit** of the new image tags;
ArgoCD reconciles that commit into the cluster. That's true **GitOps**.

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
  Push to AWS ECR  ◀──── ECR repos (created by Terraform in Phase 1)
       │
       ▼
  yq bumps  helm/cloudkitchen/values.yaml  ──► commits back to main
                                                 │
                                                 ▼
                                       ArgoCD detects the commit  (Phase 4)
```

---

## ✅ Prerequisites

| Need | How to check / get |
|------|--------------------|
| Phase 1 done (Terraform applied) | `terraform -chdir=terraform output ecr_repository_urls` lists 9 repos |
| The repo cloned and tracked in Git | `git status` works in the project root |
| A GitHub account | https://github.com |
| AWS Account ID handy | `aws sts get-caller-identity --query Account --output text` |

---

## Step 1 — Create a GitHub repo and push the code

On https://github.com → **New repository** → name it (e.g. `cloudkitchen`),
**private**, no README/.gitignore (the local repo already has its own).

Then in your local project root:

```bash
# Only if this isn't a git repo yet:
git init && git add . && git commit -m "initial import"

# Point at the new GitHub repo (change the URL to yours):
git branch -M main
git remote add origin https://github.com/<your-username>/cloudkitchen.git
git push -u origin main
```
**What this does:** Pushes your local `main` branch to GitHub. After this,
every push to `main` triggers `.github/workflows/ci.yaml`.

---

## Step 2 — Create a dedicated IAM user for CI

You *could* reuse your own access keys, but it's cleaner to have a least-privilege
CI user. In the AWS console (or CLI):

```bash
# 1. Create the user
aws iam create-user --user-name cloudkitchen-ci

# 2. Attach the policy that allows ECR push/pull
cat > /tmp/cloudkitchen-ci-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF
aws iam put-user-policy --user-name cloudkitchen-ci \
  --policy-name cloudkitchen-ci-ecr --policy-document file:///tmp/cloudkitchen-ci-policy.json

# 3. Create an access key (PRINT-AND-COPY — won't be shown again)
aws iam create-access-key --user-name cloudkitchen-ci
```
**What this does:**
- Creates an IAM user `cloudkitchen-ci` that can do **only** ECR push/pull.
- `put-user-policy` attaches an inline policy with the minimum ECR actions the
  CI workflow needs (matches the `Action` block in the workflow's IAM
  prerequisites doc).
- `create-access-key` returns `AccessKeyId` + `SecretAccessKey`. **Copy them
  now** — AWS doesn't show the secret again.

---

## Step 3 — Add the secrets/variables to GitHub

In your GitHub repo: **Settings → Secrets and variables → Actions**.

### Secrets (encrypted, never echoed to logs)

Click **New repository secret** for each:

| Name | Value |
|------|-------|
| `AWS_ACCESS_KEY_ID` | the `AccessKeyId` from Step 2 |
| `AWS_SECRET_ACCESS_KEY` | the `SecretAccessKey` from Step 2 |
| `GITOPS_TOKEN` *(optional)* | a fine-grained PAT with `contents: write` on this repo. Only needed if branch protection blocks the default `GITHUB_TOKEN` from pushing. |

### Variables (plain, visible in logs)

Click the **Variables** tab → **New repository variable**:

| Name | Value | Example |
|------|-------|---------|
| `ECR_REGISTRY` | `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com` | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |

> ℹ️ `AWS_REGION` (`us-east-1`) and `IMAGE_PREFIX` (`cloudkitchen`) are
> hard-coded in `.github/workflows/ci.yaml`. Change them there if you ever need
> a different region/prefix.

---

## Step 4 — Trigger the first CI run

Make a trivial commit on `main` to force a run (the workflow path filter only
runs on changes under `*-service/`, `frontend/`, or `.github/workflows/ci.yaml`):

```bash
git commit --allow-empty -m "ci: trigger first build"
git push
```

In GitHub → **Actions** tab → click the running workflow → watch the **build**
job: 9 jobs run **in parallel** (one per service), each does:
1. Checkout the code
2. Compute a short SHA (the image tag)
3. AWS login via the keys you added
4. ECR login
5. `docker buildx` build (with cache)
6. **Trivy scan** — fails the job on HIGH/CRITICAL CVEs that have a fix
7. Push to ECR (only on `main`)

After all 9 succeed, the `update-gitops` job runs once: it `yq`-patches each
service's `image:` in `helm/cloudkitchen/values.yaml`, then commits & pushes
with a `[skip ci]` message.

---

## Step 5 — Verify

### 5.1 — ECR has the images

```bash
aws ecr describe-images \
  --repository-name cloudkitchen/auth-service \
  --query 'sort_by(imageDetails,& imagePushedAt)[-3:].imageTags' \
  --output table
```
**What this does:** Lists the 3 most recently pushed image tags for the
`auth-service` ECR repo. You should see a short-SHA tag and `latest`.

Repeat for any of the 9 service names if you want.

### 5.2 — values.yaml was bumped

```bash
git pull
grep -A1 '^authService:' helm/cloudkitchen/values.yaml | head -3
```
**What this does:** Pulls the auto-commit from CI back to your local checkout,
then prints the `authService` block. The `image:` line should now contain the
short SHA you just built (not `:latest`).

### 5.3 — CI run is green

GitHub Actions → ✅ green check on the latest run. If a service failed Trivy:
that's the gate working. Either fix the CVE (update base image), or temporarily
adjust the scan severity in `ci.yaml` (not recommended in real life).

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Workflow doesn't trigger at all | Path filter didn't match | edit a `*-service/` file OR use `git commit --allow-empty` |
| `not authorized to perform: ecr:GetAuthorizationToken` | IAM policy missing | re-run the policy block from Step 2 |
| `denied: requested access to the resource is denied` on push | ECR repo doesn't exist | Terraform must have applied successfully; check `aws ecr describe-repositories` lists `cloudkitchen/<service>` |
| Trivy job fails on HIGH/CRITICAL | Real vuln in the base image | update base image (`golang:1.23-alpine` → newer) or `Dockerfile` — *don't* silently lower severity in CI |
| `update-gitops` fails to push | Branch protection blocks default token | add `GITOPS_TOKEN` PAT secret (`contents: write` on this repo) |
| The auto-commit retriggers CI in a loop | Missing `[skip ci]` in commit msg | already present in `ci.yaml`; if you customized the message, add `[skip ci]` back |

---

## 📋 Phase 3 cheatsheet

```bash
# Push code first
git push -u origin main

# Trigger a build
git commit --allow-empty -m "ci: rebuild" && git push

# Tail the latest CI run from CLI (needs `gh` CLI)
gh run watch

# Confirm new image in ECR
aws ecr describe-images --repository-name cloudkitchen/auth-service \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags'

# Confirm values.yaml bumped
git pull && grep image: helm/cloudkitchen/values.yaml | head
```

---

## 🎉 What you accomplished

- ✅ Code lives in **GitHub**, every push to `main` builds it.
- ✅ Images are built **in parallel**, scanned by Trivy, and pushed to **ECR**.
- ✅ `helm/cloudkitchen/values.yaml` is **auto-updated** with the new image tags
  — the GitOps "source of truth" is current.
- ✅ Zero `helm upgrade` or `kubectl apply` in CI — deployment is purely
  ArgoCD's job (next phase).

➡️ **Next:** [Phase 4 — ArgoCD deploys the app](04-argocd-deploy.md)
