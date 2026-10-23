# orderbyqr-terraform-eks

Infrastructure as Code for **orderbyqr** (React, Node.js, Redis, MongoDB), built with Terraform on AWS. The goal is a reusable, modular setup that runs the app on Kubernetes (EKS) and can be copied across environments and similar projects.

This is a DevOps practice project. All Terraform modules are written from scratch rather than pulled from the registry, to learn how they are designed.

## Architecture

```
AWS (ap-south-1)
└── VPC
    ├── 3 public subnets  (one per AZ)  -> Internet Gateway, load balancers
    ├── 3 private subnets (one per AZ)  -> EKS worker nodes
    └── 3 NAT gateways    (one per AZ)  -> outbound internet for private subnets

ECR   -> frontend and backend Docker images (pulled by nodes through their IAM role)
EKS   -> control plane + managed node group (2 x t3.medium, private subnets), Kubernetes 1.36
OIDC  -> lets specific Kubernetes service accounts assume specific IAM roles (IRSA),
         used by the EBS CSI driver and the AWS Load Balancer Controller
```

## How the infrastructure as code works

Terraform is the single source of truth for the AWS infrastructure and the required
cluster add-ons. It compares the desired configuration in this repository with the
current Terraform state and AWS resources, then creates or updates only what is
needed.

The dependency flow is:

```text
VPC and subnets
      ↓
EKS cluster and managed node group
      ↓
OIDC provider and IAM roles for service accounts
      ↓
EBS CSI EKS add-on + AWS Load Balancer Controller Helm release
```

The EBS CSI driver is installed as an EKS managed add-on. The AWS Load Balancer
Controller is installed through Terraform's Helm provider. Terraform configures both
controllers with dedicated IAM roles through IRSA, so their Kubernetes service
accounts receive only the permissions they need.

After the initial tool setup, the environment is deployed with `terraform apply`.
There is no separate `helm install`, `kubectl apply`, or manually created service
account required for the infrastructure components in this repository. `kubectl` is
used afterward for access and verification.

## Problems this solves

- **Configuration drift:** Terraform records the intended infrastructure and detects
  changes made outside the configuration.
- **Repeatability:** the same environment can be recreated consistently for another
  development, staging, or production account by changing variables.
- **Ordering errors:** Terraform builds the dependency graph so IAM, EKS, and the
  cluster add-ons are provisioned in the required order.
- **Manual setup mistakes:** add-on settings, service account names, IAM annotations,
  cluster details, and VPC details are defined in code instead of copied into commands.
- **Over-permissioned workloads:** IRSA gives each controller a dedicated IAM role
  instead of requiring broad permissions on the worker-node role.
- **Recovery and teardown:** the environment can be reviewed with `terraform plan`,
  recreated with `terraform apply`, and removed with `terraform destroy`.

## Tech stack

- Terraform (AWS provider ~> 5.0)
- AWS: VPC, ECR, EKS, IAM (OIDC / IRSA)
- Docker and Kubernetes
- Helm provider (Terraform installs the AWS Load Balancer Controller)
- Planned: Jenkins, Prometheus and Grafana, ArgoCD, External Secrets, Ansible
- Tools needed locally: Terraform, AWS CLI, kubectl

## Project structure

```
orderbyqr-terraform-eks/
├── modules/
│   ├── vpc/     # VPC, subnets, IGW, NAT gateways, route tables
│   ├── ecr/     # container image repositories
│   └── eks/     # EKS cluster, node group, OIDC provider, IAM roles for IRSA
│       └── policies/lb-controller-policy.json   # AWS's published LB controller permissions
└── environments/
    └── dev/     # calls the modules with dev values
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars
        └── outputs.tf
```

Modules contain no environment-specific values. Everything specific to an environment comes in through variables, so a new environment is a copy of `environments/dev/` with different values.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials (`aws configure`)
- kubectl (to talk to the cluster)
- Helm CLI is optional; Terraform's Helm provider installs the AWS Load Balancer Controller
- An AWS account and permissions to create VPC, ECR, EKS, and IAM resources

## Start the infrastructure

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

Terraform creates the VPC, ECR repositories, EKS cluster, node group, OIDC provider,
IRSA roles, the EBS CSI managed add-on, and the AWS Load Balancer Controller Helm
release. Both add-ons create their Kubernetes service accounts automatically; no
Kubernetes resources need to be created manually.

After the apply completes, configure `kubectl` and verify the cluster:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name orderbyqr-dev-eks-cluster

kubectl get nodes
kubectl get pods -n kube-system -l app.kubernetes.io/instance=aws-ebs-csi-driver
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
aws eks describe-addon \
  --cluster-name orderbyqr-dev-eks-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1
```

To start the infrastructure again after it has been stopped, run:

```bash
cd environments/dev
terraform apply
aws eks update-kubeconfig --region ap-south-1 --name orderbyqr-dev-eks-cluster
kubectl get nodes
```

To remove everything and stop charges:

```bash
terraform destroy
```

Note: destroying removes everything inside the cluster, including both add-ons. They are
recreated automatically by Terraform after the next `terraform apply`.

### Connect to the cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name orderbyqr-dev-eks-cluster
kubectl get nodes
```

## Post-apply verification (after every fresh `terraform apply`)

Both cluster add-ons are installed automatically by Terraform. No `kubectl apply`,
`helm install`, or manually created Kubernetes service account is required.

### 1. EBS CSI driver (automatic)

The EBS CSI driver is installed by the `aws_eks_addon.ebs_csi` resource. Verify it with:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/instance=aws-ebs-csi-driver
aws eks describe-addon \
  --cluster-name orderbyqr-dev-eks-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1
```

The add-on creates `ebs-csi-controller-sa` in the `kube-system` namespace and uses the
IAM role created by Terraform. Do not create this service account manually.

### 2. AWS Load Balancer Controller (automatic)

The `helm_release.aws_load_balancer_controller` resource installs the chart, creates
the `aws-load-balancer-controller` service account, and applies the IRSA role annotation.
Verify it with:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Cost warning

NAT gateways, the EKS control plane and the EC2 worker nodes are billed per hour while they exist. Run `terraform destroy` when you finish a session.

## Progress

- [x] VPC module (subnets, IGW, NAT per AZ, route tables)
- [x] Dev environment wiring
- [x] ECR module
- [x] EKS module (cluster and node group)
- [x] OIDC provider + IAM roles for EBS CSI driver and AWS Load Balancer Controller (IRSA)
- [x] EBS CSI driver installed as a Terraform-managed EKS add-on
- [x] AWS Load Balancer Controller installed with a Terraform-managed Helm release
- [ ] Dockerfiles and Kubernetes manifests for orderbyqr
- [ ] CI/CD with Jenkins
- [ ] Monitoring (Prometheus and Grafana)
- [ ] GitOps with ArgoCD
- [ ] Secrets management and hardening
- [ ] Remote state (S3 and DynamoDB locking)

## Notes and design decisions

- Own Terraform modules instead of registry modules, to learn how modules are designed.
- One NAT gateway per AZ for high availability. This is more expensive than a single shared NAT.
- Subnet CIDRs are passed in explicitly, not computed, to keep the IP layout visible.
- ECR for images: worker nodes pull through an IAM role, so no registry passwords or pull secrets are needed.
- EKS uses access entries (`authentication_mode = "API"`) instead of the legacy `aws-auth` ConfigMap.
- Worker nodes: 2 x t3.medium on-demand, in private subnets. The API endpoint is public and private so kubectl works from a laptop.
- Running Kubernetes 1.36, configured in `environments/dev/terraform.tfvars`.
- IRSA (IAM Roles for Service Accounts): an OIDC provider is registered for the cluster so specific Kubernetes service accounts, not the whole node, can assume specific IAM roles. Used for the EBS CSI driver (`AmazonEBSCSIDriverPolicy`) and the AWS Load Balancer Controller (custom policy from AWS's published `iam_policy.json`).
- The Load Balancer Controller's IAM policy is downloaded from the `aws-load-balancer-controller` GitHub repo rather than hand-written, since AWS maintains it directly.
- Terraform creates and manages both the EBS CSI EKS add-on and the AWS Load Balancer Controller Helm release, including their IAM role integrations. Both are removed by `terraform destroy` and recreated by the next `terraform apply`.
- Local Terraform state for now. Remote state is planned as a later step.
