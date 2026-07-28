# CloudKitchen — Terraform (Google Cloud / GKE Infrastructure)

This folder provisions **all the GCP infrastructure** CloudKitchen needs:
a VPC with Cloud NAT, a **GKE cluster** with private nodes + Workload Identity,
**Artifact Registry** repos, Service Accounts, firewall rules, and a
Compute Engine **bastion** reachable via IAP. Everything is one
`terraform apply` away.

> 🎯 Designed for **freshers / 1–2 years experienced** engineers. One flat
> root, one `terraform.tfvars` to edit, no per-environment folders.
> 🪞 Parallel to `../aws-terraform/` (AWS/EKS) — same structure, GCP-flavoured.

---

## What is Terraform?

Terraform is an **Infrastructure-as-Code** tool: you describe the cloud
resources you want in `.tf` files, and Terraform figures out **how** to
create / update / delete them by calling provider APIs (here: Google Cloud).

Every change is **planned first** (`terraform plan`), tracked in a state
file, and idempotent.

---

## Why GCP for this project?

| Reason | Detail |
|---|---|
| **$300 free credit** for new GCP accounts (90 days) | Easily covers a few weeks of EKS-equivalent learning |
| **GKE free tier** | The control plane for one zonal cluster is included (~$74.40/month credit). |
| **Workload Identity built in** | GCP's IRSA equivalent — simpler than configuring an OIDC provider |
| **GCE PD CSI built into GKE** | PVCs work out of the box; no extra addon to install |
| **IAP tunneling** | SSH the bastion without a public IP, SSH key, or open port 22 |

---

## What this code deploys

| GCP resource | Purpose |
|---|---|
| **VPC** + GKE subnet | Custom VPC, regional subnet with secondary ranges for Pods + Services |
| **Cloud Router + Cloud NAT** | Egress to the internet for private nodes (no public IPs on nodes) |
| **Firewall rules** | allow-internal, allow-iap-ssh (bastion), allow-health-checks |
| **GKE cluster (private, zonal)** | Managed Kubernetes API + nodes in `us-central1-a` |
| **Managed node pool** | 2× `e2-medium` workers, autoscale 2–3, auto-upgrade, auto-repair |
| **Workload Identity** | Enabled on cluster — bind a KSA to a GCP SA later (Phase 6/7) |
| **GCE PD CSI driver** | Built-in — PVCs use the default `standard-rwo` StorageClass |
| **9 × Artifact Registry repos** | One private Docker repo per microservice + frontend |
| **Compute Engine bastion** | `e2-small` VM, no public IP, IAP-accessible, kubectl/helm pre-installed |

---

## 📂 Folder layout

```
gcp-terraform/
├── README.md             # this file
├── provider.tf           # terraform + google provider + state backend
├── variables.tf          # variable DECLARATIONS
├── terraform.tfvars      # variable VALUES — YOU EDIT THIS (project_id!)
├── main.tf               # root module — wires the child modules below
├── outputs.tf            # values printed after `terraform apply`
└── modules/              # reusable building blocks
    ├── vpc/              # VPC, subnet (secondary ranges), Cloud NAT
    ├── firewall/         # internal / IAP-SSH / health-check rules
    ├── gke/              # GKE cluster + node pool + Workload Identity
    ├── artifact-registry/# 9 Docker repos (one per service)
    └── bastion/          # Compute Engine VM (IAP only)
```

> 💡 **IAM note (intentionally simple):** there is NO custom `iam/` module —
> both GKE nodes and the bastion use the project's **default Compute Engine
> Service Account** (which has `roles/editor`) with the `cloud-platform`
> OAuth scope. Effective: full project access from inside the VMs. Great for
> learning; for production, swap to least-privilege custom SAs + Workload
> Identity bindings.

---

## 💸 Cost reality

Roughly **\$3–\$6 per day** while running (cheaper than EKS thanks to the
GKE free-tier credit on the first zonal cluster):

| Resource | ~Cost |
|---|---|
| GKE control plane (one zonal cluster) | **$0** under free tier credit |
| 2× e2-medium nodes | ~$1.60 / day |
| Cloud NAT | ~$1 / day + tiny per-GB |
| GCP LoadBalancer (created by Traefik later) | ~$0.50 / day |
| Persistent Disks (PVCs) | a few cents |
| **Total while running** | **~\$3–\$5 / day** |

➡️ **Stop the bill:** `terraform destroy` removes everything (~5 min).

---

## ✅ Prerequisites

| Tool | Why | Install hint |
|------|-----|-------------|
| **Terraform ≥ 1.5** | runs this code | https://developer.hashicorp.com/terraform/install |
| **gcloud CLI** | auth + GKE access | https://cloud.google.com/sdk/docs/install |
| **kubectl** + `gke-gcloud-auth-plugin` | talks to GKE | `gcloud components install gke-gcloud-auth-plugin` |
| **A GCP project** with billing enabled | obvious | `gcloud projects create my-cloudkitchen-12345` then link a billing account |
| **A service-account JSON key** *or* `gcloud` ADC | Terraform's credentials | see "Authenticate" below |

### Enable the required GCP APIs (one-time, per project)

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=<your-project-id>
```

### Authenticate Terraform

Two equally valid options — pick **one**:

**Option A — Service Account JSON key (what we'll use)**
1. In GCP Console → IAM → Service Accounts → Create.
2. Grant `roles/owner` (easy for learning; tighten later).
3. Keys → Add Key → JSON. Save the file.
4. In your terminal:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/key.json
   ```

**Option B — gcloud user credentials (also fine)**
```bash
gcloud auth application-default login
gcloud config set project <your-project-id>
```

Verify:
```bash
gcloud auth list
gcloud config get-value project
```

---

## 🚀 Quick start (the 4 commands)

From inside this `gcp-terraform/` folder:

```bash
# 0. (one-time) edit terraform.tfvars and set:  project_id = "your-project-id"

# 1. Download the google + google-beta providers + init local state
terraform init

# 2. Preview what WILL be created (no GCP changes yet)
terraform plan

# 3. Create everything (~15 min for GKE)
terraform apply

# 4. Point kubectl at the new cluster (command also printed by `apply`)
gcloud container clusters get-credentials cloudkitchen-dev \
  --zone us-central1-a --project <your-project-id>
kubectl get nodes
```

When you're done:
```bash
terraform destroy   # tears every resource down — bill stops
```

---

## Complete command reference

### `terraform init`
```bash
terraform init
```
Downloads the **google** + **google-beta** providers, initializes the local
state backend, and prepares all modules.

### `terraform fmt`
```bash
terraform fmt -recursive
```
Canonicalises HCL formatting. Run before committing.

### `terraform validate`
```bash
terraform validate
```
Syntax / reference check. **No GCP calls**, no credentials needed.

### `terraform plan`
```bash
terraform plan
```
**Dry-run diff** of every resource that will be created / changed /
destroyed. Always read this before `apply`. The first run shows ~30 resources.

```bash
terraform plan -out=plan.tfplan
```

### `terraform apply`
```bash
terraform apply
```
Prompts for `yes`, then **creates the GCP resources**. GKE control plane
alone is ~10 min; total apply ~15 min. **Billing starts here.**

```bash
terraform apply -auto-approve         # CI / automation
terraform apply -target=module.gke    # apply only one module
```

### `terraform output`
```bash
terraform output                          # all outputs
terraform output kubeconfig_command       # one specific output
terraform output -json artifact_registry_urls   # machine-readable
```

### `terraform state`
```bash
terraform state list                                          # everything we manage
terraform state show module.gke.google_container_cluster.this
```

### `terraform destroy`
```bash
terraform destroy
```
**Deletes every GCP resource this code created.** Run when you stop learning.

---

## Quick reference card

```bash
# Daily flow
terraform init                # one-time
terraform fmt -recursive      # before commit
terraform validate            # syntax check
terraform plan                # preview changes
terraform apply               # create / update

# Inspection
terraform output              # cluster name, AR URLs, kubeconfig cmd …
terraform state list          # what we manage

# Cleanup
terraform destroy             # remove EVERYTHING, stop the bill
```

---

## After `terraform apply` succeeds — what's next?

1. **Kubeconfig**
   ```bash
   gcloud container clusters get-credentials cloudkitchen-dev \
     --zone us-central1-a --project <your-project-id>
   kubectl get nodes
   ```
2. **(Optional) IAP-tunnel to the bastion** (kubectl + helm pre-installed):
   ```bash
   gcloud compute ssh cloudkitchen-dev-bastion \
     --zone us-central1-a --tunnel-through-iap --project <your-project-id>
   ```
3. **Build & push the 9 images to Artifact Registry**
   ```bash
   REGION=us-central1
   PROJECT=$(gcloud config get-value project)
   gcloud auth configure-docker ${REGION}-docker.pkg.dev
   # build + push each from its Dockerfile
   ```
   *(URLs are emitted by `terraform output artifact_registry_urls`.)*
4. **Install the Helm chart** — same chart as AWS, with two tiny value changes:
   ```yaml
   postgres:  { storageClass: standard-rwo }
   nats:      { storageClass: standard-rwo }
   imageRegistry: us-central1-docker.pkg.dev/<your-project-id>/cloudkitchen
   ```
   *(GKE auto-creates `standard-rwo` via the GCE PD CSI driver.)*

A complete GCP deployment runbook will live in `docs/gke/` (parallel to
`docs/eks/`).

---

## Multi-environment (staging / prod)

The flat layout doesn't have `environments/` folders — switch **workspaces**
or use a different tfvars file:

```bash
terraform workspace new staging
terraform apply -var="environment=staging"

# OR
terraform apply -var-file=prod.tfvars
```

For real teamwork, switch to the **GCS backend** in `provider.tf` so state
isn't on one laptop.

---

## Things to tighten before a real production deploy

- Use a **regional** cluster (`location = var.region`) for HA.
- Restrict `master_authorized_cidrs` to your office / VPN egress.
- Enable Cloud Armor on the LB (Phase 5/7).
- Migrate state to the **GCS backend** (versioned + uniform bucket access).
- Replace `roles/owner` on the Terraform SA with least-privilege roles.
- Rotate SA keys; ideally move CI to **Workload Identity Federation** instead.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Permission … denied on project` | Missing API or weak SA role | re-run the `gcloud services enable …` block; grant Owner |
| `Quota 'CPUS' exceeded` | New projects have low quotas | request a quota increase in Console → IAM & Admin → Quotas |
| GKE cluster takes 10+ minutes | Normal | be patient |
| PVC stuck `Pending` | Wrong StorageClass name | the GKE default is `standard-rwo` — set chart `storageClass` accordingly |
| `gcloud compute ssh … --tunnel-through-iap` fails | User not in `iap_allowed_users` | add `user:you@gmail.com` to that tfvars list, re-apply |
| `terraform apply` errors on Artifact Registry quota | New project quota | open a quota increase in Console |
