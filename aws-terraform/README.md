# CloudKitchen — Terraform (AWS EKS Infrastructure)

This folder provisions **all the AWS infrastructure** CloudKitchen needs:
a VPC, an EKS cluster with private worker nodes, ECR repositories, IAM/IRSA
roles, a bastion host, and the EBS CSI driver. Everything is one `terraform
apply` away.

> 🎯 Designed to be **simple enough for freshers / 1–2 years experienced
> engineers** to learn from. One flat root, one `terraform.tfvars` to edit, no
> per-environment folders to juggle.

---

## What is Terraform?

Terraform is an **Infrastructure-as-Code** tool: you describe the AWS resources
you want in `.tf` files, and Terraform figures out **how** to create / update /
delete them by calling AWS APIs. Instead of clicking 50 times in the AWS
console, you run `terraform apply`.

Every change is **planned first** (`terraform plan` shows you exactly what will
change), tracked in a **state file**, and **idempotent** (re-running with no
changes is a no-op).

---

## Why use Terraform for this project?

| Advantage | What it means in plain terms |
|-----------|------------------------------|
| **Reproducible** | One command rebuilds the entire EKS environment from scratch |
| **Reviewable** | Infrastructure changes are pull requests, not Slack messages |
| **Modular** | The `modules/` you see here are reusable building blocks |
| **Multi-cloud-able** | Same workflow on AWS/GCP/Azure (we use AWS here) |
| **Destroy-able** | `terraform destroy` removes EVERYTHING this code created (so the bill stops) |
| **State-tracked** | Terraform knows what it created vs. what you want — drift is detectable |

---

## What this code deploys

| AWS resource | Purpose |
|---|---|
| **VPC** | A private network with 3 public + 3 private subnets across 3 AZs |
| **Internet Gateway + NAT Gateway** | Public LBs reach the internet; private workers egress via NAT |
| **Security Groups** | bastion, control plane, worker nodes |
| **EKS Cluster (control plane)** | Managed Kubernetes API in `us-east-1` |
| **EKS Managed Node Group** | Worker EC2 nodes (run in **private** subnets) |
| **OIDC provider** | Enables IRSA (IAM Roles for ServiceAccounts) |
| **EKS Addons** | `vpc-cni`, `coredns`, `kube-proxy`, **`aws-ebs-csi-driver`** |
| **CloudWatch log group** | Control-plane logs with retention (so they don't pile up forever) |
| **IAM roles** | EKS cluster role, node role + IRSA roles for ALB-controller, external-dns, cert-manager, EBS CSI |
| **9 × ECR repositories** | One per microservice + frontend (private container registries) |
| **Bastion EC2** | Small jump host in a public subnet (SSM / SSH access for debugging) |

---

## 📂 Folder layout

```
aws-terraform/
├── README.md            # this file
├── provider.tf          # terraform + AWS provider + state backend config
├── variables.tf         # variable DECLARATIONS (types, descriptions, defaults)
├── terraform.tfvars     # variable VALUES — YOU EDIT THIS
├── main.tf              # root module — calls the child modules below
├── outputs.tf           # values printed after `terraform apply`
└── modules/             # reusable building blocks
    ├── vpc/             # VPC, subnets, IGW, NAT, route tables
    ├── security-groups/ # bastion / worker / control-plane SGs
    ├── eks/             # EKS cluster, node group, OIDC, addons, log group
    ├── iam/             # cluster/node roles + IRSA roles
    ├── ecr/             # 9 ECR repos (one per service)
    └── bastion/         # bastion EC2 instance + IAM profile
```

Each `module/` is just a folder with its own `main.tf` / `variables.tf` /
`outputs.tf`. Think of a module as a Lego brick the root `main.tf` snaps
together.

---

## 💸 Cost reality (read this before applying)

Roughly **\$4–\$8 per day** while the cluster is running, in `us-east-1`:

| Resource | Approx. cost |
|---|---|
| EKS control plane | $0.10 / hr ≈ **$2.40 / day** |
| 2× t3.medium EC2 (workers) | ~$0.04/hr each ≈ **$2 / day** |
| NAT Gateway (single) | $0.045/hr + data ≈ **$1.10 / day** |
| EBS volumes (PVCs for Postgres/NATS) | tiny |
| LoadBalancer (created by Traefik later) | ~**$0.50 / day** |

➡️ **Run `terraform destroy` when you're done learning** to stop the bill.

---

## ✅ Prerequisites

| Tool | Why | Install hint |
|------|-----|--------------|
| **Terraform ≥ 1.5** | runs this code | https://developer.hashicorp.com/terraform/install |
| **AWS CLI v2** | configures credentials | `apt install awscli` / Homebrew |
| **kubectl** | talks to the cluster after creation | https://kubernetes.io/docs/tasks/tools/ |
| **AWS account + IAM credentials** | so Terraform can create things | run `aws configure` once |

Verify with:
```bash
aws sts get-caller-identity   # must succeed
terraform -version            # >= 1.5
```

---

## 🚀 Quick start (the 4 commands)

From inside this `aws-terraform/` folder:

```bash
# 1. Download providers (aws, tls) + initialize state
terraform init

# 2. Preview what WILL be created (no AWS changes yet)
terraform plan

# 3. Create everything (takes ~15–20 min for EKS)
terraform apply

# 4. Point kubectl at the new cluster (command also printed by `apply` output)
aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
kubectl get nodes
```

When you're done:
```bash
terraform destroy   # tears every resource down — bill stops
```

---

## Complete command reference

### 1. `terraform init`

```bash
terraform init
```
**What it does:** Downloads the AWS + TLS providers into `.terraform/`,
initializes the state backend (LOCAL by default — state file lives in this
folder), and prepares all modules. **Run once** when you clone the repo, and
again any time you change provider versions or the backend.

### 2. `terraform fmt`

```bash
terraform fmt -recursive
```
**What it does:** Rewrites your `.tf` files into the canonical formatting style.
Run before committing so diffs are clean.

### 3. `terraform validate`

```bash
terraform validate
```
**What it does:** Static check of the configuration — finds syntax errors and
unresolved references. **Doesn't talk to AWS**, doesn't need credentials.

### 4. `terraform plan`

```bash
terraform plan
```
**What it does:** Refreshes state from AWS and prints a **dry-run diff**: every
resource that will be created / updated / destroyed and why. **Nothing is
changed.** Always read this output before applying.

```bash
terraform plan -out=plan.tfplan
```
Saves the plan so `terraform apply plan.tfplan` applies exactly what you saw.

### 5. `terraform apply`

```bash
terraform apply
```
**What it does:** Runs `plan` again, asks *"are you sure?"*, then **executes** —
creating the AWS resources. EKS control plane alone takes ~10 minutes; full
apply ≈ 15–20 min. **This is where AWS starts billing.**

```bash
terraform apply -auto-approve            # CI / automation — skips the prompt
terraform apply -target=module.ecr       # apply only one module (useful for fixes)
```

### 6. `terraform output`

```bash
terraform output                 # all outputs
terraform output cluster_name    # one specific output
terraform output -json           # machine-readable
```
**What it does:** Shows the values from `outputs.tf` — cluster name, kubeconfig
command, ECR repo URLs, bastion IP, IRSA role ARNs.

### 7. `terraform state`

```bash
terraform state list                                   # everything Terraform knows about
terraform state show module.eks.aws_eks_cluster.this   # details of one resource
```
**What it does:** Read-only views of what Terraform thinks the world looks like.
Useful when debugging "is this resource really there?".

### 8. `terraform destroy`

```bash
terraform destroy
```
**What it does:** **Deletes every resource this code created.** Always run this
when you finish learning — otherwise EKS keeps billing.

```bash
terraform destroy -target=module.bastion   # destroy just one module
```

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
terraform output              # cluster name, ECR URLs, kubeconfig cmd …
terraform state list          # what Terraform manages

# Cleanup
terraform destroy             # remove EVERYTHING, stop the bill
```

---

## After `terraform apply` succeeds — what's next?

1. **Point kubectl at the new cluster:**
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
   kubectl get nodes
   ```
2. **Build + push the 9 service images to ECR** (use the URLs from
   `terraform output ecr_repository_urls`).
   *(EKS auto-provides a default `gp2` StorageClass — used by the chart via CSI
   migration. No StorageClass manifest needed.)*
3. **Install the Helm chart:**
   ```bash
   kubectl create namespace cloudkitchen
   helm install cloudkitchen ../helm/cloudkitchen -n cloudkitchen
   ```

A full step-by-step (every command explained) will live in
`docs/EKS-DEPLOYMENT.md` once we write it.

---

## How to deploy a second environment (staging / prod)

The flat layout doesn't have `environments/` folders — switch **workspaces** or
use a different `tfvars` file:

```bash
# Workspaces (isolated state per env in the same backend):
terraform workspace new staging
terraform workspace select staging
terraform apply -var="environment=staging"

# Or: a separate tfvars file
terraform apply -var-file=prod.tfvars
```

For real multi-env work consider switching to the **S3 backend** (uncomment the
block in `provider.tf` and create the bucket + DynamoDB table first) so state
isn't on one engineer's laptop.

---

## Things to tighten before a real production deploy

- Set `single_nat_gateway = false` for HA (one NAT per AZ).
- Restrict `endpoint_public_access_cidrs` and `bastion_allowed_cidrs` to your
  office / VPN egress, not `0.0.0.0/0`.
- Switch ECR `image_tag_mutability` to `IMMUTABLE` in `main.tf`.
- Use the S3 backend (versioning + encryption + DynamoDB locking).
- Pin Kubernetes addon versions in `modules/eks/main.tf` via `addon_versions`.
- Rotate AWS access keys; ideally move CI to **OIDC** instead of static keys.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Unable to locate credentials` | AWS CLI not configured | `aws configure` |
| EKS cluster "takes forever" to create | Normal — first apply takes 15–20 min | be patient ☕ |
| `addon: aws-ebs-csi-driver: not authorized` | IRSA role not wired | check `terraform output irsa_role_arns` |
| PVC stuck `Pending` after deploy | EBS CSI driver not ready | `kubectl -n kube-system get pods -l app=ebs-csi-controller` |
| `Cycle` error on `terraform plan` | A new resource created a module loop | the EBS CSI addon is intentionally at the **root**, not inside the eks module — keep it there |
