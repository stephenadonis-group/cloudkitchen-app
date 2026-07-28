# Phase 4 — Deploy CloudKitchen with ArgoCD on GKE

> **Status:** ✅ Written *as we did it*, on `cloudkitchen-dev-01`. Reflects the
> exact commands that worked, not a theoretical guide.

**Goal:** Move CloudKitchen from a manual `helm install` to a GitOps loop where
**every push to `main` ends up in the cluster automatically**. After this phase:

```
you edit code  →  git push  →  GitHub Actions (build + push to AR + bump values.yaml)
                                          ↓
                              ArgoCD detects the values.yaml change
                                          ↓
                              ArgoCD syncs the chart on the cluster
                                          ↓
                              new pods roll out with the new image tag
```

There is **no manual `helm upgrade` or `kubectl apply`** anywhere in that loop
once it's set up.

This doc is the **GCP counterpart** to [docs/eks/04-argocd-deploy.md](../eks/04-argocd-deploy.md).
The high-level shape is the same; the differences are:

| Concern              | EKS doc                                      | GKE (this doc)                                                |
| -------------------- | -------------------------------------------- | ------------------------------------------------------------- |
| Load balancer        | AWS NLB                                      | GCP TCP LB (single static IP, assigned by Traefik install)    |
| Traefik namespace    | `ingress`                                    | `traefik`                                                     |
| Repo access          | Public HTTPS pull                            | **Private repo — SSH deploy key + k8s Secret**                |
| ArgoCD repo URL kind | `https://github.com/<org>/<repo>`            | `git@github.com:<owner>/<repo>.git` (SSH)                     |
| TLS termination      | cert-manager + Let's Encrypt (Phase 7)       | HTTP-only for this phase; cert-manager comes in Phase 7       |

---

## Prerequisites (already done in earlier phases)

| What                                             | How to check                                                                                          |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| GKE cluster reachable from kubectl               | `kubectl config current-context` returns the cluster's full name                                      |
| Traefik installed (in `traefik` namespace)       | `kubectl -n traefik get svc traefik` shows an external IP                                             |
| GitHub Actions CI pushes images to Artifact Registry & bumps `helm/cloudkitchen/values.yaml` | A recent commit on `main` authored by `cloudkitchen-ci[bot]` titled `ci(gitops): bump image tags to <sha>` |
| `helm` v3 + `kubectl` available locally          | `helm version` and `kubectl version --client`                                                         |

---

## Step 1 — Uninstall the existing manual Helm release

Until now we've been deploying with `helm install/upgrade cloudkitchen`. ArgoCD
is going to **own** that same release going forward, so we delete the manual one
first to avoid two controllers fighting over the same Deployments.

```bash
helm uninstall cloudkitchen -n cloudkitchen
```

**What survives** the uninstall:

| Resource                                                     | State after uninstall |
| ------------------------------------------------------------ | --------------------- |
| Deployments, Services, ConfigMaps, Secrets, HPAs, IngressRoutes | deleted               |
| Postgres + NATS **PVCs** (`data-postgres-0`, `data-nats-0`)  | **preserved**         |
| Namespace `cloudkitchen`                                     | preserved             |

Verify the PVCs:

```bash
kubectl -n cloudkitchen get pvc
# Expect: data-nats-0 and data-postgres-0 both Bound
```

> The volumes are kept because Helm `uninstall` doesn't touch PVCs created by a
> StatefulSet's `volumeClaimTemplates`. So Postgres data + NATS JetStream
> messages survive — when ArgoCD re-creates the StatefulSets they'll attach to
> the existing PVCs and pick up where they left off.

There is a **~1 minute window** between this uninstall and ArgoCD finishing
its first sync where the app is unreachable. That's expected and unavoidable
for a "clean slate" transition.

---

## Step 2 — Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=ClusterIP \
  --set 'configs.params.server\.insecure=true' \
  --set 'configs.params.server\.rootpath=/argocd' \
  --wait --timeout=5m
```

What these flags mean:

| Flag                                                    | Why                                                                                                     |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `server.service.type=ClusterIP`                         | We're putting ArgoCD behind the **existing Traefik LB** via an IngressRoute, not a separate LB. Saves money + one IP to remember. |
| `configs.params.server\.insecure=true`                  | ArgoCD itself serves plain HTTP; Traefik will terminate TLS in Phase 7. Without this, ArgoCD redirects to `https://` and the IngressRoute breaks. |
| `configs.params.server\.rootpath=/argocd`               | Makes the UI work when served under a sub-path. The IngressRoute also strips this prefix. Both must match. |
| `--wait --timeout=5m`                                   | Block until all pods are Ready — saves a separate `kubectl wait` step.                                  |

When this returns, expect 8 ArgoCD pods Running:

```bash
kubectl -n argocd get pods
# argocd-application-controller-0       Running
# argocd-applicationset-controller-...  Running
# argocd-dex-server-...                 Running
# argocd-notifications-controller-...   Running
# argocd-redis-...                      Running
# argocd-repo-server-...                Running
# argocd-server-...                     Running
# argocd-redis-secret-init-...          Completed
```

---

## Step 3 — Expose ArgoCD via Traefik (`/argocd` path)

We're reusing the existing Traefik LoadBalancer (the same one fronting the app)
instead of provisioning a second GCP LB just for ArgoCD. Apply this
IngressRoute into the `argocd` namespace:

```yaml
# /tmp/argocd-ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - web              # plain HTTP for now (port 80). Phase 7 will add TLS via websecure.
  routes:
    - match: PathPrefix(`/argocd`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
```

```bash
kubectl apply -f /tmp/argocd-ingressroute.yaml
kubectl get ingressroute -n argocd
kubectl describe ingressroute argocd -n argocd
```

**Why no `StripPrefix` middleware?**
We installed ArgoCD with `configs.params.server.rootpath=/argocd`. With
`rootpath` set, ArgoCD assumes every request arrives with the `/argocd`
prefix and rewrites its own HTML (`<base href>`, asset paths, login redirects)
accordingly. Stripping the prefix here would actually *break* the UI because
the backend would receive `/` and re-emit links pointing at `/argocd/...`
that don't match what reached Traefik.

**Verify the IngressRoute is reachable**:
```bash
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -sI -o /dev/null -w "/argocd  -> HTTP %{http_code}\n"  "http://${LB_IP}/argocd"
curl -sI -o /dev/null -w "/argocd/ -> HTTP %{http_code}\n"  "http://${LB_IP}/argocd/"
# Expect: /argocd -> 307 (ArgoCD redirects to add trailing slash)
#         /argocd/ -> 200 (login page)
```

### 3a — Open the ArgoCD UI in a browser

Build the full URL from the LB IP and open it:

```bash
# 1. Grab the LB IP (the same IP fronting your app)
LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. Print the ArgoCD URL  (trailing slash matters — without it you get a 307 redirect)
echo "ArgoCD UI:  http://${LB_IP}/argocd/"
```

In a browser, paste that URL exactly. You should see the **ArgoCD login
page** (dark theme, "Argo CD" logo, username + password fields).

### 3b — Get the initial admin password

ArgoCD provisions a random one-shot admin password as a Kubernetes Secret
called `argocd-initial-admin-secret` in the `argocd` namespace. Print it:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
# Sample output: B3YMfE1WHNOpFInP
```

> 💡 **Want one command that gives you everything?** This prints the URL +
> credentials together:
> ```bash
> LB_IP=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> echo "URL:      http://${LB_IP}/argocd/"
> echo "Username: admin"
> echo -n "Password: " ; kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
> ```

### 3c — Log in

| Field | Value |
| --- | --- |
| **Username** | `admin` |
| **Password** | the value from 3b |

After login you land on the **Applications** dashboard (empty for now —
Steps 4 + 5 below add the `cloudkitchen` Application that will populate it).

### 3d — (optional) Alternative access: port-forward

If your LB isn't reachable yet (DNS not set up, behind a corporate proxy, etc.)
you can also reach the UI directly from your laptop:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

Then open **http://localhost:8080/argocd/** (same trailing-slash rule). Stop
with `Ctrl+C`. This is fine for one-off debugging but you'll usually want
the IngressRoute for daily use — port-forward dies when your terminal
closes.

### 3e — Lock down the initial admin password (do this once)

The bootstrap secret stays in the cluster forever unless you delete it.
**After your first successful login**, change the password from the UI and
remove the secret:

```bash
# 1. In the ArgoCD UI: top-right user menu (👤 admin) → "Update Password"
#    Enter the current (bootstrap) password + a new strong one. Save.

# 2. Once you've verified the new password works, delete the bootstrap secret:
kubectl -n argocd delete secret argocd-initial-admin-secret
```

Not urgent for day-1 — but don't forget to do it before any DNS/HTTPS phase
makes the UI public-reachable.

---

## Step 4 — Grant ArgoCD access to the private repo (HTTPS + classic PAT)

ArgoCD's `argocd-repo-server` Pod has no host keys, no SSH agent, no GitHub
identity. To clone a private repo it needs credentials embedded in a
namespaced Secret. We use **HTTPS + a GitHub classic PAT**; ArgoCD treats the
PAT as the HTTP-basic-auth password.

> We tried a **fine-grained PAT** first and it returned **HTTP 404** when
> ArgoCD tried to fetch the repo. Reason: fine-grained tokens require you to
> explicitly tick each repository they're allowed to access during creation,
> and `cloudkitchen-app` was missing from that list. Switching to a classic
> PAT with the parent `repo` scope worked immediately because classic tokens
> see every repo your account can. See the Troubleshooting section below.

### 4a — Generate the PAT on GitHub

1. Open https://github.com/settings/tokens (classic — *not* the fine-grained
   `personal-access-tokens` URL).
2. **Generate new token (classic)**.
3. Note: `argocd-cloudkitchen` (or anything memorable).
4. Expiration: your choice. "No expiration" is acceptable for a learning
   project you'll tear down soon.
5. Scopes: tick **only `repo`** (the parent box; it auto-selects the 5
   sub-scopes). ArgoCD needs nothing else.
6. **Generate token**. Copy the `ghp_...` value — GitHub shows it only once.

### 4b — Create the k8s Secret

```bash
GH_PAT='ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cloudkitchen-repo
  namespace: argocd
  labels:
    # This label is what argocd-repo-server uses to auto-discover repo creds.
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/vijaygiduthuri/cloudkitchen-app.git
  username: vijaygiduthuri
  password: ${GH_PAT}
EOF
```

### 4c — Verify

A quick API probe (200 = the PAT can read the repo):
```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $GH_PAT" \
  https://api.github.com/repos/vijaygiduthuri/cloudkitchen-app
```

Confirm the Secret has the right label (without printing the PAT itself):
```bash
kubectl -n argocd get secret cloudkitchen-repo \
  -o jsonpath='{.metadata.labels}{"\n"}'
# Expect: {"argocd.argoproj.io/secret-type":"repository"}
```

---

## Step 5 — Apply the AppProject + cloudkitchen Application

The repo already contains the manifests at `argocd/project.yaml` and
`argocd/apps/app-cloudkitchen.yaml`. Two things to know about
`app-cloudkitchen.yaml`:

1. **`source.repoURL` must be HTTPS** (matching the Secret we just created),
   not `git@github.com:...`. The chart's path inside the repo is
   `helm/cloudkitchen`.
2. **`ignoreDifferences` for StatefulSet `volumeClaimTemplates` is required**
   — see Troubleshooting below for why. The manifest in this repo already
   has it.

Apply both manifests:

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/apps/app-cloudkitchen.yaml
```

The Application has `syncPolicy.automated.{prune,selfHeal}` enabled, so
ArgoCD starts cloning + reconciling immediately — no manual `argocd app sync`
needed.

**Expected boot timeline** (~60–90 s end to end):

```
0s   ArgoCD discovers the Application, clones the repo
5s   Helm chart rendered; 51 manifests planned
10s  All 51 resources applied
15s  Postgres + NATS PVCs reattached (same data as before helm uninstall)
20s  postgres-0 + nats-0 Running
20s  Go services start; many fail first attempt — Postgres DNS not resolvable yet
40s  Postgres readiness probe passes; CoreDNS resolves `postgres` → 10.x
40s  Services restart via fail-fast (the os.Exit(1) we added earlier), now connect
60s  All 12 pods Running 1/1
```

The first ~20s of CrashLoopBackOff is **expected and correct** — the
fail-fast broker init we added to auth/user/restaurant in Phase 2 deliberately
exits the process if Postgres or NATS isn't ready, instead of running with
silent dependencies. The kubelet restarts the Pod, and on retry 3 or 4
everything comes up cleanly.

**Verify**:
```bash
kubectl -n argocd get app cloudkitchen
# NAME           SYNC STATUS   HEALTH STATUS
# cloudkitchen   Synced        Healthy

kubectl -n cloudkitchen get pods
# All 12 pods should be Running 1/1 (give it ~90s after the apply)
```

---

## Step 5b — Populate the demo restaurant catalogue (optional)

At this point ArgoCD has deployed all 12 pods with **empty** databases.
If you open the customer UI now you'll see a blank "No restaurants"
screen — because no owner has registered anything yet.

To skip the manual restaurant + menu registration flow and jump straight
to browsing / ordering, apply the pre-built seed:

```bash
kubectl -n cloudkitchen cp scripts/seed-restaurants.sql postgres-0:/tmp/seed.sql
kubectl -n cloudkitchen exec postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen -f /tmp/seed.sql
```

Expected output at the bottom:

```
     tbl     | rows
-------------+------
 restaurants |   20
 categories  |   41
 menu_items  |   99
(3 rows)
```

This inserts **20 restaurants across 7 Indian cities and ~99 menu items**,
all owned by a synthetic "demo owner" UUID so any real user signups are
untouched. The seed is **idempotent** — safe to re-run any time, it
deletes prior demo data before re-inserting. Source:
[scripts/seed-restaurants.sql](../../scripts/seed-restaurants.sql).

**Skip this step** if you want to walk through the real restaurant-owner
signup flow (Sign up → role: owner → register restaurant → add categories
→ add menu items). The seed is purely a shortcut for demos + smoke tests.

---

## Step 6 — Verify the GitOps loop end-to-end

The full loop:

```
 1. edit a file in any service (e.g. add a comment)
 2. git push origin main
 3. .github/workflows/ci-gcp.yaml triggers
       → builds image  → Trivy scan  → pushes to AR with tag :<7-char-sha>
       → update-gitops job runs `yq` to rewrite helm/cloudkitchen/values.yaml
       → commits & pushes as cloudkitchen-ci[bot]  ("ci(gitops): bump image tags to <sha> [skip ci]")
 4. ArgoCD's repo poller (default 3 min) detects the commit on main
       — OR you click "Refresh" on the ArgoCD UI to make it immediate
 5. ArgoCD diffs cluster vs git, sees the new image tag, marks OutOfSync
 6. syncPolicy.automated.selfHeal = true → ArgoCD applies the new
       Deployment spec  → kubelet rolls the pods
 7. New pods come up running the just-built image. Done.
```

Quick smoke test once everything's green: run the in-cluster end-to-end test
documented in [docs/LOCAL-TESTING.md](../LOCAL-TESTING.md) (or the smoke
script in chat history): register a customer, place an order, advance it
through the delivery state machine as a delivery-agent user, see it reach
`DELIVERED`. That exercises every service and every NATS subject.

---

## Troubleshooting

| Symptom                                                                                                                    | Likely cause                                                                                                                                                            | Fix                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ArgoCD app condition `ComparisonError: ... SSH agent requested but SSH_AUTH_SOCK not-specified`                            | The Application's `source.repoURL` is `git@github.com:...` (SSH form) but the Secret holds an HTTPS PAT (no SSH key in the cluster).                                    | Patch `app-cloudkitchen.yaml` and `project.yaml` to use `https://github.com/<owner>/<repo>.git` everywhere. Re-apply.                                                                                                              |
| GitHub API returns `HTTP 404` for `/repos/<owner>/<repo>` even with a working PAT                                          | Fine-grained PAT was created without that specific repo in its "Repository access" allowlist. Token is valid; it just can't see that one resource.                      | Either (a) edit the existing PAT and add the repo, or (b) switch to a classic PAT with `repo` scope (sees all repos by default). Easier path for personal projects is (b).                                                         |
| App is `SYNC=OutOfSync, HEALTH=Healthy` permanently with the only differences being `StatefulSet/postgres` and `StatefulSet/nats` | `spec.volumeClaimTemplates` is immutable on a StatefulSet after creation. ArgoCD can't reconcile it, so the diff is permanent.                                          | Add an `ignoreDifferences` block on the Application targeting `apps/StatefulSet` `/spec/volumeClaimTemplates`, plus `RespectIgnoreDifferences=true` in `syncOptions`. The manifest in this repo already does this.                 |
| 8 service pods are `CrashLoopBackOff` immediately after a fresh `helm install` or ArgoCD sync                              | Services started before CoreDNS could resolve `postgres` — the fail-fast broker/db init exits the process if those deps aren't reachable.                               | **Expected.** Wait ~60s; kubelet restarts → retry 3 succeeds. If a pod is *still* crashing after 2 minutes, check `kubectl logs <pod> --previous` — real bug.                                                                       |
| ArgoCD UI loads but assets 404 / page is blank                                                                             | `configs.params.server.rootpath` was not set during helm install, OR the IngressRoute strips the `/argocd` prefix.                                                      | `helm upgrade argocd argo/argo-cd -n argocd --reuse-values --set 'configs.params.server\.rootpath=/argocd'`. Do **not** add a `StripPrefix` middleware to the IngressRoute when `rootpath` is set.                                  |
| App shows `Unknown / Unable to connect to repository` indefinitely                                                         | The repository Secret is missing the `argocd.argoproj.io/secret-type=repository` label, or its `url` doesn't byte-match the Application's `source.repoURL`.             | `kubectl -n argocd get secret cloudkitchen-repo -o jsonpath='{.metadata.labels}'` should show the label. The `url` and the `source.repoURL` must match including trailing `.git` and casing.                                       |
| `update-gitops` step in CI failing on `git push` with permission denied                                                    | Default `GITHUB_TOKEN` lacks `contents:write`, or branch protection on `main` blocks bot pushes.                                                                        | Settings → Actions → General → Workflow permissions = **"Read and write"**. Or set `secrets.GITOPS_TOKEN` to a PAT with `contents:write`.                                                                                          |
