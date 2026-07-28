# Phase 1 — Infrastructure & Jump VM

**Goal:** Create the entire AWS infrastructure with **one `terraform apply`**,
connect to the **bastion (jump VM)** via AWS Systems Manager, install the
DevOps tools on it, and finally connect to the new **EKS cluster** so you can
run `kubectl get nodes`.

**Time:** ~25 minutes (the EKS control plane alone takes ~10).

---

## What you'll build in this phase

```
                            AWS account  (us-east-1)
   ┌──────────────────────────────────────────────────────────────┐
   │                            VPC  (10.10.0.0/16)                │
   │                                                                │
   │   Public subnets  ──► IGW   (3 AZs)                            │
   │      │                                                         │
   │      ▼                                                         │
   │   Bastion EC2 ◀──── you (via AWS SSM, no SSH key needed) ──── │
   │      │                                                         │
   │      ▼                                                         │
   │   Private subnets  ──► NAT GW  (3 AZs)                         │
   │      │                                                         │
   │      ▼                                                         │
   │   EKS managed node group  (2× t3.medium workers)               │
   │      └── kubectl  ←─── from the bastion / your laptop          │
   │                                                                │
   │   ECR (9 repos) · IAM roles · OIDC · EBS CSI · CloudWatch logs │
   └────────────────────────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

| Tool / thing | How to check | Get it |
|---|---|---|
| AWS account + IAM user with `AdministratorAccess` *(easy for learning)* | `aws sts get-caller-identity` | AWS console → IAM → Users |
| **Terraform ≥ 1.5** | `terraform -version` | https://developer.hashicorp.com/terraform/install |
| **AWS CLI v2** | `aws --version` → 2.x | https://docs.aws.amazon.com/cli/latest/userguide/install.html |
| The CloudKitchen repo cloned locally | `ls aws-terraform/main.tf` | `git clone …` |

> 🔑 **Credentials**: run `aws configure` **in your own terminal** (never paste
> secret keys into a chat). Fill in **Access Key ID**, **Secret Access Key**,
> default region `us-east-1`, default output `json`.

---

## Step 1 — Verify AWS access

```bash
aws sts get-caller-identity
```

**What this does:** Calls AWS STS to ask "who am I?". If credentials are
configured, it returns your IAM user/role ARN. If you see
`Unable to locate credentials`, run `aws configure` first.

**Expected output:**
```json
{
  "UserId":  "AIDA…",
  "Account": "123456789012",
  "Arn":     "arn:aws:iam::123456789012:user/yourname"
}
```

Note your **Account ID** — you'll use it in Phase 3 (ECR registry URL).

---

## Step 2 — Provision the infrastructure

Move into the Terraform folder.

```bash
cd terraform
```

### 2.1 — Initialize Terraform

```bash
terraform init
```
**What this does:**
- Downloads the AWS + TLS providers into `.terraform/`.
- Initializes the **local** state backend (a `terraform.tfstate` file in this
  folder — fine for learning; switch to S3 later for team work).
- Resolves all the modules under `modules/`.

You should see *"Terraform has been successfully initialized!"*.

### 2.2 — Preview what will be created

```bash
terraform plan
```
**What this does:** Asks AWS what currently exists, compares it to the code,
and prints **every resource** that will be created/changed/destroyed. **Nothing
is created yet.** The output for a fresh apply is ~70 resources.

> Read the summary line at the end:
> `Plan: 71 to add, 0 to change, 0 to destroy.`
> Those numbers should match (within a couple) what you see. Big surprises =
> stop and investigate.

### 2.3 — Apply (this is where AWS billing starts)

```bash
terraform apply
```
Type `yes` at the prompt.

**What this does:** Creates the VPC, subnets, NAT, IGW, security groups, IAM
roles, the EKS cluster + node group + OIDC provider + addons (`vpc-cni`,
`coredns`, `kube-proxy`, **`aws-ebs-csi-driver`**), the 9 ECR repositories, and
the bastion EC2 — in dependency order.

**Timing:** ~15–20 minutes total. The EKS cluster alone is ~10 minutes.

> ☕ Take a break. When it finishes you'll see a green
> *"Apply complete! Resources: 71 added, 0 changed, 0 destroyed."*

### 2.4 — Capture the outputs

```bash
terraform output
```
**Useful values that get printed:**

| Output | What it is | You'll use it for |
|---|---|---|
| `cluster_name` | e.g. `cloudkitchen-dev` | `aws eks update-kubeconfig` |
| `kubeconfig_command` | the exact command to copy-paste | next step |
| `bastion_public_ip` | bastion's public IP | (informational; we use SSM not SSH) |
| `ecr_repository_urls` | map of `<service>` → ECR repo URL | Phase 3 (push images) |
| `irsa_role_arns` | ARNs for the IRSA-enabled add-ons | Phase 2 / Phase 7 if needed |

To get just one output:
```bash
terraform output ecr_repository_urls
```

---

## Step 3 — Get kubectl talking to the cluster (from your laptop)

The output above includes a `kubeconfig_command`. Run it:

```bash
aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
```
**What this does:** Writes the cluster's endpoint + your IAM-based auth helper
into `~/.kube/config`, then sets it as the **current context**.

**Verify:**
```bash
kubectl get nodes
```
**Expected output:** 2 worker nodes in `Ready` state.
```
NAME                            STATUS   ROLES    AGE   VERSION
ip-10-10-48-x.ec2.internal      Ready    <none>   3m    v1.30.x
ip-10-10-64-y.ec2.internal      Ready    <none>   3m    v1.30.x
```

> 📝 **Why this works without aws-auth gymnastics:** the IAM user/role that
> *created* the EKS cluster automatically gets cluster-admin via the EKS
> "cluster-creator" identity. The bastion's role is different (see Step 4).

---

## Step 4 — Connect to the jump VM (bastion) via SSM

Skip this step if you're happy running kubectl from your laptop. Use the
bastion when you want a small persistent workstation inside AWS (handy if your
laptop's IP changes or you need to reach private resources).

### 4.1 — Find the bastion instance ID

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```
**What this does:** Lists running EC2 instances tagged with "bastion" and prints
their instance IDs. Save the result — let's call it `$BASTION`.

### 4.2 — Open an SSM Session (no SSH key required)

```bash
aws ssm start-session --target $BASTION
```
**What this does:** Opens an interactive shell on the bastion **without SSH**.
AWS Systems Manager routes the connection through its API, so you don't need
port 22 open, a key pair, or even a public IP. Your IAM permissions decide who
can connect.

You should land in a shell as `ssm-user`:
```
sh-5.2$
```

To leave: type `exit` (or `Ctrl-D`).

> 🆘 If `start-session` says "session manager plugin is not installed", get it
> from https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html.

---

## Step 5 — Install the DevOps tools on the bastion

These commands run **on the bastion** (inside the SSM session).

The bastion is Amazon Linux 2023. Become root first, then install.

```bash
sudo su -        # become root for the installs
```

### 5.1 — AWS CLI v2

```bash
yum install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && ./aws/install
aws --version
```
**What this does:** Downloads the official AWS CLI bundle and installs it
under `/usr/local/aws-cli`. `aws --version` should print `aws-cli/2.x`.

### 5.2 — kubectl (matched to the cluster's Kubernetes version)

```bash
curl -sLO "https://dl.k8s.io/release/v1.30.5/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/
kubectl version --client
```
**What this does:** Downloads the `kubectl` binary, makes it executable, drops
it into `/usr/local/bin/`. The `--client` flag means it doesn't try to talk to
a cluster (we'll do that next).

### 5.3 — Helm v3

```bash
curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```
**What this does:** Pulls Helm's official installer script and runs it. Should
print `version.BuildInfo{Version:"v3.x.x", …}`.

> 💡 We deliberately **do not install Docker on the bastion.** Image builds
> happen in CI (Phase 3) using GitHub-hosted runners, not on this small VM.

---

## Step 6 — Point the bastion's kubectl at the EKS cluster

The bastion has an instance profile with `eks:DescribeCluster` (so it can read
EKS) and **AWS Systems Manager** permissions — but **no admin access to the
cluster's Kubernetes API yet**.

Two simple paths to fix that:

### Path A (simplest): Use the same IAM user on the bastion

```bash
aws configure       # paste the same access keys you used locally
```
The IAM user that ran `terraform apply` automatically got
**cluster-creator admin**, so `kubectl` from the bastion authenticated as that
user works immediately:

```bash
aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
kubectl get nodes
```
> ⚠️ Don't leave long-lived IAM keys on a shared bastion. For learning this is
> fine; for production, prefer Path B.

### Path B (cleaner): Add the bastion's IAM role to the cluster

From your **laptop** (where you already have admin):
```bash
BASTION_ROLE=$(terraform -chdir=terraform output -raw bastion_role_arn 2>/dev/null \
  || aws iam get-instance-profile \
       --instance-profile-name cloudkitchen-dev-bastion-profile \
       --query 'InstanceProfile.Roles[0].Arn' --output text)

aws eks create-access-entry \
  --cluster-name cloudkitchen-dev \
  --principal-arn "$BASTION_ROLE" \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name cloudkitchen-dev \
  --principal-arn "$BASTION_ROLE" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```
**What this does:** EKS *access entries* (the modern replacement for the
`aws-auth` ConfigMap) map an IAM principal to a cluster permission. The two
commands say: "the bastion's role is a STANDARD entry, and grants it
cluster-admin." Now the bastion can authenticate without any IAM access keys.

Then on the bastion:
```bash
aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
kubectl get nodes
```

---

## ✅ Verify Phase 1

Run all of these — they should all succeed:

```bash
# 1. AWS access
aws sts get-caller-identity

# 2. Terraform tracked resources
terraform -chdir=terraform state list | wc -l    # >= 60

# 3. EKS API reachable
kubectl get nodes                                 # 2 Ready nodes
kubectl get ns                                    # default, kube-system, ...

# 4. Core EKS add-ons running
kubectl -n kube-system get pods | grep -E 'coredns|kube-proxy|aws-node|ebs-csi'
# Expect coredns, kube-proxy, aws-node (vpc-cni), AND ebs-csi-controller pods Running.

# 5. Bastion reachable via SSM
aws ssm describe-instance-information --query 'InstanceInformationList[].InstanceId'
```

If all 5 pass, **Phase 1 is done** ✅.

---

## 🐛 Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Unable to locate credentials` | `aws configure` not run | run `aws configure` |
| `terraform apply` hangs on EKS | Normal — it takes ~10 min | be patient |
| `error: You must be logged in to the server (Unauthorized)` from kubectl | Different IAM identity than the one that created the cluster | use the same user, or apply the access-entry from Step 6 path B |
| `update-kubeconfig: ResourceNotFound` | Cluster name typo or wrong region | `terraform output cluster_name`; ensure region is `us-east-1` |
| Bastion not visible in SSM | IAM permissions missing or SSM Agent not running | the Terraform bastion module attaches `AmazonSSMManagedInstanceCore` — wait 1–2 minutes after `apply` for the agent to register |
| `kubectl` from bastion says `Unauthorized` | Bastion role not mapped | Step 6 Path A or B |
| EBS CSI controller in `CrashLoopBackOff` | IRSA role not propagated | `kubectl -n kube-system rollout restart deploy ebs-csi-controller` |

---

## 🧹 If you want to stop here for the day

```bash
cd terraform
terraform destroy
```
Type `yes`. ~10 minutes later, everything is gone and billing stops. To resume
later, just re-run `terraform apply`.

---

## 📋 Phase 1 cheatsheet

```bash
# Provision
cd terraform && terraform init && terraform apply

# Kubeconfig (from output)
aws eks update-kubeconfig --region us-east-1 --name cloudkitchen-dev
kubectl get nodes

# Bastion shell (no SSH key needed)
BASTION=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*bastion*" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
aws ssm start-session --target $BASTION

# Destroy when done
terraform destroy
```

---

## 🎉 What you accomplished

- ✅ A real **VPC with private + public subnets** across 3 AZs.
- ✅ A managed **EKS cluster** with workers in private subnets.
- ✅ Core EKS add-ons including the **EBS CSI driver** (needed for PVCs later).
- ✅ **9 ECR repositories** ready to receive container images in Phase 3.
- ✅ A **bastion** you can SSM into without managing SSH keys.
- ✅ **kubectl** talking to your cluster.

➡️ **Next:** [Phase 2 — Traefik ingress controller](02-traefik-ingress.md)
