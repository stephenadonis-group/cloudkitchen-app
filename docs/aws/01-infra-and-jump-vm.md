# Phase 1 — Infrastructure & Jump VM (GCP)

**Goal:** Provision the entire GCP infrastructure with **one `terraform apply`**,
connect to the **bastion VM** via IAP (Identity-Aware Proxy) tunnel, install
the DevOps tools on it, and finally connect to the new **GKE cluster** so you
can run `kubectl get nodes`.

**Time:** ~20 minutes (the GKE control plane alone takes ~6–8 min — faster
than EKS).

This is the **GCP counterpart** of [docs/eks/01-infra-and-jump-vm.md](../eks/01-infra-and-jump-vm.md).
Same idea, different cloud:

| Concern               | EKS                             | GKE (this doc)                                                |
| --------------------- | ------------------------------- | ------------------------------------------------------------- |
| Compute               | EC2 nodes (`t3.medium`)         | Compute Engine nodes (`e2-standard-4` or `e2-medium`)         |
| Bastion access        | AWS SSM Session Manager         | **IAP tunnel** (`gcloud compute ssh --tunnel-through-iap`)    |
| Image registry        | ECR (9 separate repos)          | **Artifact Registry** (ONE repo `cloudkitchen-registry`, 9 image names inside) |
| Kubeconfig fetch      | `aws eks update-kubeconfig`     | `gcloud container clusters get-credentials`                   |
| Storage class for PVCs | `gp3` (EBS CSI)                | `standard-rwo` (PD CSI, GKE default)                          |
| LB for ingress        | NLB                             | GCP TCP LoadBalancer (single static IP)                       |
| Terraform directory   | `aws-terraform/`                | **`gcp-terraform/`** (kept separate so both clouds coexist)   |
| Control-plane cost    | $73/mo per cluster              | **First zonal cluster FREE** (GKE free tier — $74/mo credit)  |

---

## What you'll build in this phase

```
                            GCP project  (us-central1)
   ┌──────────────────────────────────────────────────────────────┐
   │                            VPC  (cloudkitchen-dev-vpc)        │
   │                                                                │
   │   Subnet 10.10.0.0/20  ─────────────────────────────────────  │
   │      ├── Pods range     10.20.0.0/16                          │
   │      └── Services range 10.30.0.0/20                          │
   │                                                                │
   │   Cloud NAT + Cloud Router ──► outbound internet              │
   │                                                                │
   │   Firewall rules: IAP SSH (35.235.240.0/20), internal,        │
   │                   GCP health-checks                           │
   │                                                                │
   │   Bastion  ◀── you (gcloud compute ssh --tunnel-through-iap)  │
   │   (e2-small VM, no public IP)                                 │
   │      │                                                         │
   │      ▼                                                         │
   │   GKE cluster (zonal, private nodes, Workload Identity on)    │
   │   └── node pool: 2x e2-standard-4 (auto-scale 2–3)            │
   │      └── kubectl  ←── from the bastion / your laptop          │
   │                                                                │
   │   Artifact Registry — ONE repo "cloudkitchen-registry"        │
   │   (9 logical image names live inside it, one per service)     │
   └────────────────────────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

| Tool / thing                                            | How to check                                            | Where to get it                                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| GCP account + project with billing enabled              | `gcloud projects describe <project-id>`                 | https://console.cloud.google.com/projectcreate                                                   |
| Service account JSON key with `roles/owner` *(easy for learning)* | `cat gcp-sa.json` (gitignored in this repo)             | console → IAM → Service Accounts → Create key                                                    |
| **Terraform ≥ 1.5**                                     | `terraform -version`                                    | https://developer.hashicorp.com/terraform/install                                                |
| **gcloud CLI**                                          | `gcloud --version` → 470+                               | https://cloud.google.com/sdk/docs/install                                                        |
| `kubectl`                                               | `kubectl version --client`                              | `gcloud components install kubectl` or your distro's package                                     |
| CloudKitchen repo cloned locally                        | `ls gcp-terraform/main.tf`                              | `git clone git@github.com:vijaygiduthuri/cloudkitchen-app.git`                                   |

> 🔑 **Authenticating Terraform.** Place your SA JSON at `gcp-sa.json` in the
> repo root (already in `.gitignore`) and export it:
> ```bash
> export GOOGLE_APPLICATION_CREDENTIALS=/home/vijay/Desktop/cloudkitchen-app/gcp-sa.json
> ```
> Never paste the JSON into chat — it gets logged. Generate a fresh key + delete it after you tear the project down.

---

## Enable the required GCP APIs (one-time per project)

Terraform expects these to already be enabled — otherwise the first `apply`
fails with `API ... not enabled` errors.

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  cloudresourcemanager.googleapis.com \
  servicenetworking.googleapis.com \
  --project=<your-project-id>
```

This takes ~30 s and is idempotent.

---

## Tour of `gcp-terraform/`

```
gcp-terraform/
├── main.tf                  # wires 5 modules together (vpc → firewall → gke → AR → bastion)
├── variables.tf             # all input names + types + defaults
├── outputs.tf               # cluster endpoint, AR registry host, bastion name
├── provider.tf              # google + google-beta provider config
├── terraform.tfvars         # the only file you edit (project_id, region, machine types, …)
└── modules/
    ├── vpc/                 # VPC + subnet with secondary ranges + Cloud NAT/Router
    ├── firewall/            # rules: IAP SSH allow, internal allow, health-check allow
    ├── gke/                 # cluster + node pool (private, Workload Identity)
    ├── artifact-registry/   # ONE Docker repo with 9 logical image names
    └── bastion/             # e2-small VM, no public IP, reachable only via IAP
```

The architecture is intentionally simple: both GKE nodes and the bastion use
the project's **default Compute Engine service account** with the broad
`cloud-platform` OAuth scope. That gives them everything they need (pull from
AR, write logs, etc.) without managing a fleet of custom SAs. **Tighten this
for production** — least-privilege SAs + Workload Identity bindings.

---

## Step 1 — Edit `terraform.tfvars`

Open [gcp-terraform/terraform.tfvars](../../gcp-terraform/terraform.tfvars).
Only one value **must** change: `project_id` (your GCP project). Everything
else has a sensible default. The defaults are tuned for a small,
cost-friendly learning deployment:

| Knob                       | Default                       | What it controls                                                                          |
| -------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------- |
| `project_id`               | *(no default — set yours)*    | Which GCP project receives everything                                                     |
| `region`                   | `us-central1`                 | Region for the regional resources (subnet, AR, NAT)                                       |
| `zone`                     | `us-central1-a`               | Zone for the zonal GKE cluster + bastion VM                                               |
| `subnet_cidr`              | `10.10.0.0/20`                | Subnet for node IPs                                                                       |
| `pods_cidr` / `services_cidr` | `10.20.0.0/16` / `10.30.0.0/20` | Secondary ranges for Pod/Service IPs (GKE VPC-native)                                  |
| `master_authorized_cidrs`  | `["0.0.0.0/0"]`               | Who may hit the GKE control plane. **Tighten** for real use.                              |
| `kubernetes_version`       | `1.30`                        | GKE minor; chart targets 1.29+                                                            |
| `release_channel`          | `REGULAR`                     | RAPID / REGULAR / STABLE — controls how aggressively GKE auto-upgrades minors             |
| `node_machine_type`        | `e2-medium`                   | Bump to `e2-standard-4` if you'll run NATS + Postgres + 8 services on the cluster comfortably |
| `node_count` / `node_min_count` / `node_max_count` | 2 / 2 / 3       | Autoscaling bounds                                                                        |
| `bastion_machine_type`     | `e2-small`                    | `e2-micro` is free-tier-eligible; `e2-small` is more comfortable                          |
| `iap_allowed_users`        | `[]` *(empty!)*               | **Add your gcloud-auth user** here (`["user:you@gmail.com"]`) or you can't SSH the bastion |

> 💡 We had a real cost-vs-CPU surprise on `e2-medium` (2 vCPU, 4 GB) — 8 Go
> services + Postgres + NATS + Redis kept hitting CPU throttling. The fix was
> upgrading to `e2-standard-4` (4 vCPU, 16 GB). If you run the full app + ArgoCD
> + monitoring stack, just start there.

---

## Step 2 — Initialize and apply

```bash
cd gcp-terraform

# Download the providers and module sources. Idempotent.
terraform init

# Preview the plan (~120 resources for the full stack).
terraform plan -out=tfplan

# Provision. GKE control plane takes ~6-8 min — the slowest step.
terraform apply tfplan
```

### Apply by module (recommended)

> 📌 **Don't edit `main.tf` to skip modules.** Use targeted applies instead:
> ```bash
> terraform apply -target=module.vpc
> terraform apply -target=module.firewall
> terraform apply -target=module.gke
> terraform apply -target=module.artifact_registry
> terraform apply -target=module.bastion
> ```
> This is the right pattern when you only want to (re)create part of the
> infrastructure or debug a failure in one module — modifying the wiring in
> `main.tf` to comment things out is a footgun (you'll forget to put it back).

### Useful outputs after apply

```bash
terraform output

# Sample (the outputs that gcp-terraform/outputs.tf actually exports):
# artifact_registry_urls = {
#   "auth-service"         = "us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/auth-service"
#   "user-service"         = "us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/user-service"
#   ... (one per service)
# }
# bastion_name        = "cloudkitchen-dev-bastion"
# bastion_ssh_command = "gcloud compute ssh cloudkitchen-dev-bastion --zone us-central1-a --tunnel-through-iap --project <project>"
# cluster_endpoint    = "<sensitive>"     # control-plane IP (hidden by default)
# cluster_name        = "cloudkitchen-dev"
# kubeconfig_command  = "gcloud container clusters get-credentials cloudkitchen-dev --zone us-central1-a --project <project>"
# project_id          = "<project>"
# region              = "us-central1"
# vpc_name            = "cloudkitchen-dev-vpc"
```

> 💡 The two `*_command` outputs are **ready-to-run gcloud commands** —
> Terraform builds them from your variables so you don't have to remember
> the `--zone`/`--project` flags:
> ```bash
> # Connect kubectl to the new cluster:
> eval "$(terraform output -raw kubeconfig_command)"
>
> # SSH the bastion via IAP:
> eval "$(terraform output -raw bastion_ssh_command)"
> ```

---

## Step 3 — Connect to the bastion via IAP

The bastion has **no public IP** and there's no SSH key to manage. You reach
it through IAP, which authenticates with your `gcloud` identity:

```bash
gcloud compute ssh cloudkitchen-dev-bastion \
  --tunnel-through-iap \
  --zone=us-central1-a \
  --project=<your-project-id>
```

First connection takes ~10 s (gcloud generates a one-off ssh key under
`~/.ssh/google_compute_engine`). After that it's instant.

**If you see `Permission denied` here**, you forgot to add yourself to
`iap_allowed_users` in `terraform.tfvars`. Fix it, then:
```bash
terraform apply -target=module.bastion
```
and retry the ssh.

---

## Step 4 — Install DevOps tools on the bastion (one-time)

The bastion ships with stock Debian. Install the platform tools:

```bash
# On the bastion:
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release ca-certificates apt-transport-https

# kubectl
gcloud components install kubectl

# helm 3
curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update && sudo apt-get install -y helm

# git + jq (handy for everything else)
sudo apt-get install -y git jq

# Confirm
kubectl version --client
helm version
```

You'll usually drive the cluster from **your laptop**, not the bastion —
the bastion is the safety net for when you need to debug from inside the
VPC (kubectl access via private endpoint).

---

## Step 5 — Get a kubeconfig

```bash
# From the bastion OR your laptop:
gcloud container clusters get-credentials cloudkitchen-dev \
  --zone=us-central1-a \
  --project=<your-project-id>

# Confirm
kubectl config current-context
# Expect: gke_<project>_us-central1-a_cloudkitchen-dev

kubectl get nodes
# Expect 2 Ready nodes, e.g.:
# NAME                                              STATUS   ROLES    AGE    VERSION
# gke-cloudkitchen-dev-default-pool-...-aaaa        Ready    <none>   5m     v1.30.x-gke.x
# gke-cloudkitchen-dev-default-pool-...-bbbb        Ready    <none>   5m     v1.30.x-gke.x
```

If the cluster is **private**, your laptop must be in the
`master_authorized_cidrs` list (or go through the bastion). The dev default
is `["0.0.0.0/0"]` for ease — tighten this for real environments.

---

## Step 6 — Smoke-test that the AR repo is reachable

The next phase (CI/CD) pushes images to Artifact Registry. Verify
authentication works from your laptop:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

docker pull busybox:1.36
docker tag busybox:1.36 us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/smoke-test:latest
docker push us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/smoke-test:latest

# Cleanup
gcloud artifacts docker images delete \
  us-central1-docker.pkg.dev/<project>/cloudkitchen-registry/smoke-test \
  --quiet
```

Pushing 4 MB takes a few seconds. If you get `denied: requested access ...`,
your SA isn't bound to `roles/artifactregistry.writer` or your Docker config
points at the wrong registry — `gcloud auth configure-docker` again with the
correct host.

---

## Step 7 — Destroy when done (cost discipline)

GKE control plane on a **zonal** cluster is free tier (1 zonal cluster per
billing account). Costs come from the **nodes** (~$50/mo for 2x e2-standard-4
running 24/7) and the **NAT** (~$45/mo for 1 NAT + 32 GB egress).

Tear it all down with a single command when you're not actively using it:

```bash
cd gcp-terraform
terraform destroy
```

This deletes the VPC, GKE cluster, nodes, AR repo (and the images inside!),
bastion, NAT, and firewall rules. Bringing it back up later is just
`terraform apply` again.

---

## Troubleshooting

| Symptom                                                                       | Likely cause                                                                                                       | Fix                                                                                                                            |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `Error 403: ... API has not been used in project ... before or it is disabled.` | One of the required APIs isn't enabled in this project                                                             | Re-run the `gcloud services enable ...` block above. Wait 30s; re-apply.                                                       |
| `Error: googleapi: Error 400: Master CIDR is not unique to the network`        | The `master_ipv4_cidr` overlaps with another peering in the same VPC                                               | Pick a different `/28` (e.g. `172.16.0.16/28`) in `terraform.tfvars` and apply.                                                |
| `gcloud compute ssh ...` → `Permission denied (publickey)` via IAP            | Your gcloud identity isn't in `iap_allowed_users` in `terraform.tfvars`                                            | Edit tfvars (`iap_allowed_users = ["user:you@gmail.com"]`), `terraform apply -target=module.bastion`, retry SSH.               |
| Nodes stuck in `NotReady`                                                     | Pod IP range exhausted, or Cloud NAT not provisioned (egress for the node container runtime blocked)               | `kubectl describe node` for the kubelet/conntrack errors. Confirm `cloud-nat-...` Operator exists in the same region.          |
| `kubectl get nodes` from laptop → connection refused                          | Cluster is private and your laptop's egress IP isn't in `master_authorized_cidrs`                                  | Either widen the CIDR or run kubectl through the bastion.                                                                      |
| `denied: ... insufficient_scope` pulling images from AR on the cluster        | Node SA missing the `cloud-platform` OAuth scope                                                                   | Check `gcloud container node-pools describe` — `oauthScopes` must include `https://www.googleapis.com/auth/cloud-platform`.    |
| First `terraform apply` hangs at `module.gke.google_container_cluster ... Still creating...` for >10 min | Normal — GKE control plane provisioning takes 6–8 min on a good day, longer on a busy region | Just wait. If it exceeds 15 min, check the GKE page in the console for an explicit error.                                       |

---

➡️ **Next:** [Phase 2 — Traefik Ingress](02-traefik-ingress.md)



# Phase 1 — Infrastructure & Jump VM (AWS / EKS)

**Goal:** Provision the entire AWS infrastructure with **one `terraform apply`**,
connect to the **bastion** (SSM or SSH), install the DevOps tools, and finally
connect to the new **EKS cluster** so you can run `kubectl get nodes`.

**Time:** ~25–35 minutes (EKS control plane is usually the slowest step).

This is the **AWS counterpart** of [docs/gcp/01-infra-and-jump-vm.md](../gcp/01-infra-and-jump-vm.md).
Same idea, different cloud:

| Concern                | GKE                                      | EKS (this doc)                                              |
| ---------------------- | ---------------------------------------- | ----------------------------------------------------------- |
| Compute                | GCE nodes (`e2-medium` / `e2-standard-4`)| EC2 nodes (`t3.medium` or similar)                          |
| Bastion access         | IAP tunnel                               | **SSM Session Manager** and/or public SSH                   |
| Image registry         | Artifact Registry (one repo)             | **ECR** (one repo per service under `cloudkitchen-dev/`)    |
| Kubeconfig fetch       | `gcloud container clusters get-credentials` | `aws eks update-kubeconfig`                              |
| Storage class for PVCs | `standard-rwo`                           | **`gp2` / `gp3`** (EBS CSI)                                 |
| LB for ingress         | GCP TCP LB                               | **NLB** (via AWS LB Controller + Traefik Service)           |
| Terraform directory    | `gcp-terraform/`                         | **`aws-terraform/`**                                        |
| Control-plane cost     | First zonal cluster free tier            | ~$73/mo per cluster                                         |

---

## What you'll build in this phase

AWS account  (us-east-1)
┌──────────────────────────────────────────────────────────────┐
│                            VPC                                │
│                                                                │
│   Public subnets  ── NAT GW / IGW ──► internet                 │
│   Private subnets ── EKS nodes (no public IPs)                 │
│                                                                │
│   Bastion  ◀── you (SSM Session Manager or SSH)                │
│      │                                                         │
│      ▼                                                         │
│   EKS cluster (cloudkitchen-dev)                               │
│   └── managed node group                                       │
│      └── kubectl  ←── from laptop or bastion                   │
│                                                                │
│   ECR — cloudkitchen-dev/{auth,user,restaurant,...}            │
│   IRSA roles — ALB controller, external-dns, cert-manager, EBS │
└────────────────────────────────────────────────────────────────┘


---

## ✅ Prerequisites

| Tool / thing                         | How to check                          | Where to get it                                      |
| ------------------------------------ | ------------------------------------- | ---------------------------------------------------- |
| AWS account                          | `aws sts get-caller-identity`         | https://aws.amazon.com                               |
| AWS CLI v2 configured                | `aws configure list`                  | https://docs.aws.amazon.com/cli                      |
| **Terraform ≥ 1.5**                  | `terraform -version`                  | https://developer.hashicorp.com/terraform/install    |
| `kubectl`                            | `kubectl version --client`            | https://kubernetes.io/docs/tasks/tools/              |
| `helm` v3                            | `helm version`                        | https://helm.sh/docs/intro/install/                  |
| `session-manager-plugin` (for SSM)   | `session-manager-plugin`              | AWS Session Manager plugin docs                      |
| CloudKitchen repo cloned             | `ls aws-terraform/`                   | your fork of the repo                                |

```bash
export AWS_REGION=us-east-1
# or: aws configure set region us-east-1

aws-terraform/
├── main.tf                  # wires VPC, EKS, ECR, IRSA, bastion, …
├── variables.tf
├── outputs.tf               # cluster name, ECR URLs, bastion IP, kubeconfig cmd
├── provider.tf
├── terraform.tfvars         # the file you edit (region, node size, …)
└── modules/
    ├── vpc/
    ├── eks/
    ├── ecr/
    ├── irsa/                # ALB controller, external-dns, cert-manager, EBS CSI
    └── bastion/

Step 1 — Edit terraform.tfvars
Open aws-terraform/terraform.tfvars and set at least:

Knob,Example,Notes
region,us-east-1,Must match where you want the cluster
cluster_name,cloudkitchen-dev,Used by kubeconfig + tags
node_instance_type,t3.medium or larger,Bump if running full app + monitoring
node_desired_size / min / max,2 / 2 / 3,Autoscaling bounds

Step 2 — Initialize and apply

cd aws-terraform
`````
terraform init
terraform plan -out=tfplan
terraform apply tfplan
`````

`````
Useful outputs after apply
Bash
terraform output
`````

bastion_public_ip   = "x.x.x.x"
cluster_name        = "cloudkitchen-dev"
cluster_endpoint    = "https://....eks.amazonaws.com"
ecr_repository_urls = {
  "auth" = "<account>.dkr.ecr.us-east-1.amazonaws.com/cloudkitchen-dev/auth"
  
}

kubeconfig_command  = "aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev"
irsa_role_arns      = {
  "aws_load_balancer_controller" = "arn:aws:iam::...:role/..."
  "external_dns"                 = "arn:aws:iam::...:role/..."
  "cert_manager"                 = "arn:aws:iam::...:role/..."
  "ebs_csi_driver"               = "arn:aws:iam::...:role/..."
}

Step 3 — Connect to the bastion
Option A — SSM (preferred):
Bashaws ssm start-session --target <bastion-instance-id> --region us-east-1
Option B — SSH:
Bashssh -i ~/.ssh/<your-key>.pem ec2-user@<bastion_public_ip>

Step 4 — Install DevOps tools (laptop or bastion)


# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

kubectl version --client
helm version
aws --version

Step 5 — Get a kubeconfig

aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev

# or:
# eval "$(terraform output -raw kubeconfig_command)"

kubectl config current-context
kubectl get nodes

Step 6 — Smoke-test ECR

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $$   {ACCOUNT_ID}.dkr.ecr.   $${REGION}.amazonaws.com

docker pull busybox:1.36
docker tag busybox:1.36 \
  $$   {ACCOUNT_ID}.dkr.ecr.   $${REGION}.amazonaws.com/cloudkitchen-dev/auth:smoke
docker push \
  $$   {ACCOUNT_ID}.dkr.ecr.   $${REGION}.amazonaws.com/cloudkitchen-dev/auth:smoke


Step 7 — StorageClass (important for later phases)
Bash

kubectl get storageclass

Make gp2 default if needed: or gp3

kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

Use storageClassName: gp2 for Postgres, NATS, Loki, Prometheus PVCs.
Do not use GKE’s standard-rwo on EKS.

Step 8 — What Terraform prepared for later phases

Component,Purpose,Next use
AWS Load Balancer Controller IRSA,Creates NLB/ALB,Traefik Service type=LoadBalancer
external-dns IRSA,Auto Route53 records,Annotate Services / Ingresses
cert-manager IRSA,TLS / Let's Encrypt,Phase 7
EBS CSI IRSA,Dynamic volumes,All PVCs
ECR repos,Per-service images,CI push + GitOps tags

Step 9 — Destroy when done
Bash
cd aws-terraform
terraform destroy

Symptom,Likely cause,Fix
Unable to connect to the server,Wrong region/name or SG,aws eks describe-cluster --name cloudkitchen-dev
Nodes NotReady,CNI / IAM / subnet tags,kubectl describe node; check aws-node logs
PVC Pending,Empty or wrong StorageClass,Use gp2; set default StorageClass
ECR push denied,Auth / wrong registry,Re-run docker login with ECR password
Traefik EXTERNAL-IP pending,LB controller / IRSA / subnets,Check aws-load-balancer-controller logs

Mapping to the rest of the AWS path
Phase,What you do
1,Infra + kubectl (this doc)
2,Traefik + NLB
3,CI → ECR + GitOps bump of values.yaml
4,ArgoCD Application sync
5,Route 53 Alias → Traefik NLB
6+,"Monitoring, logging (gp2), TLS"

Mapping to the rest of the AWS path