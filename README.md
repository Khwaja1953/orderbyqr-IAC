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
EKS   -> control plane + managed node group (2 x t3.medium, private subnets), Kubernetes 1.34
OIDC  -> lets specific Kubernetes service accounts assume specific IAM roles (IRSA),
         used by the EBS CSI driver and the AWS Load Balancer Controller
```

## Tech stack

- Terraform (AWS provider ~> 5.0)
- AWS: VPC, ECR, EKS, IAM (OIDC / IRSA)
- Docker and Kubernetes
- Helm (for the AWS Load Balancer Controller)
- Planned: Jenkins, Prometheus and Grafana, ArgoCD, External Secrets, Ansible
- Tools needed locally: Terraform, AWS CLI, kubectl, Helm

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
- Helm (to install the AWS Load Balancer Controller)
- An AWS account and permissions to create VPC, ECR, EKS, and IAM resources

## Usage

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

To remove everything and stop charges:

```bash
terraform destroy
```

Note: destroying removes everything inside the cluster too, including the add-ons installed below. They are not tracked by Terraform and must be reinstalled after a fresh apply.

### Connect to the cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name orderbyqr-dev-eks-cluster
kubectl get nodes
```

## Post-apply setup (after every fresh `terraform apply`)

Terraform only creates the AWS-side infrastructure and the IAM roles. Two add-ons still need to be installed into the cluster itself, manually, since they run as Kubernetes workloads rather than AWS resources.

### 1. EBS CSI driver (lets MongoDB/Redis get real disks)

```bash
terraform output -raw ebs_csi_role_arn
```

```bash
aws eks create-addon \
  --cluster-name orderbyqr-dev-eks-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn <paste-the-arn> \
  --region ap-south-1
```

Verify:

```bash
kubectl get pods -n kube-system | grep ebs-csi
```

### 2. AWS Load Balancer Controller (exposes the app via Ingress/ALB)

```bash
terraform output -raw lb_controller_role_arn
terraform output vpc_id
```

Create the ServiceAccount, annotated with the IAM role:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: <paste-lb_controller_role_arn>
EOF
```

Install via Helm:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=orderbyqr-dev-eks-cluster \
  --set region=ap-south-1 \
  --set vpcId=<paste-vpc_id> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:

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
- [ ] EBS CSI driver and AWS Load Balancer Controller installed into the cluster (manual step, see Post-apply setup)
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
- Running Kubernetes 1.34, still in standard support; left as-is rather than bumping to 1.35/1.36.
- IRSA (IAM Roles for Service Accounts): an OIDC provider is registered for the cluster so specific Kubernetes service accounts, not the whole node, can assume specific IAM roles. Used for the EBS CSI driver (`AmazonEBSCSIDriverPolicy`) and the AWS Load Balancer Controller (custom policy from AWS's published `iam_policy.json`).
- The Load Balancer Controller's IAM policy is downloaded from the `aws-load-balancer-controller` GitHub repo rather than hand-written, since AWS maintains it directly.
- Terraform creates the IAM roles only. The add-ons themselves (EBS CSI driver, Load Balancer Controller) are installed manually via `aws eks create-addon` and Helm, and are lost on `terraform destroy`.
- Local Terraform state for now. Remote state is planned as a later step.