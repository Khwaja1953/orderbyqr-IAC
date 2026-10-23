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

## Start the infrastructure

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

Terraform creates the VPC, ECR repositories, EKS cluster, node group, OIDC provider,
IRSA roles, and the EBS CSI managed add-on. The EBS CSI add-on creates its own
Kubernetes service account; no Kubernetes service account needs to be created manually.

After the apply completes, configure `kubectl` and verify the cluster:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name orderbyqr-dev-eks-cluster

kubectl get nodes
kubectl get pods -n kube-system -l app.kubernetes.io/instance=aws-ebs-csi-driver
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

Note: destroying removes everything inside the cluster, including the EBS CSI add-on
and the manually installed Load Balancer Controller. The EBS CSI add-on is recreated
automatically by Terraform after the next `terraform apply`.

### Connect to the cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name orderbyqr-dev-eks-cluster
kubectl get nodes
```

## Post-apply setup (after every fresh `terraform apply`)

Terraform installs the EBS CSI driver automatically. Only the AWS Load Balancer
Controller still needs to be installed manually because it is installed with Helm.

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

If the add-on was created manually before this Terraform resource was added, import it
into the Terraform state once instead of creating it again:

```bash
cd environments/dev
terraform import \
  module.eks.aws_eks_addon.ebs_csi \
  orderbyqr-dev-eks-cluster,aws-ebs-csi-driver
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
- [x] EBS CSI driver installed as a Terraform-managed EKS add-on
- [ ] AWS Load Balancer Controller installed into the cluster (manual Helm step, see Post-apply setup)
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
- Terraform creates and manages the EBS CSI EKS add-on, including its IAM role integration. The AWS Load Balancer Controller is still installed manually via Helm and is lost on `terraform destroy`.
- Local Terraform state for now. Remote state is planned as a later step.
