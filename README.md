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
EKS   -> control plane + managed node group (2 x t3.medium, private subnets)
```

## Tech stack

- Terraform (AWS provider ~> 5.0)
- AWS: VPC, ECR, EKS
- Docker and Kubernetes
- Planned: Jenkins, Prometheus and Grafana, ArgoCD, External Secrets, Ansible
- Tools needed locally: Terraform, AWS CLI, kubectl

## Project structure

```
orderbyqr-terraform-eks/
├── modules/
│   ├── vpc/     # VPC, subnets, IGW, NAT gateways, route tables
│   ├── ecr/     # container image repositories
│   └── eks/     # EKS cluster, managed node group, IAM roles
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
- An AWS account and permissions to create VPC, ECR, and EKS resources

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

### Connect to the cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name orderbyqr-dev
kubectl get nodes
```

## Cost warning

NAT gateways, the EKS control plane and the EC2 worker nodes are billed per hour while they exist. Run `terraform destroy` when you finish a session.

## Progress

- [x] VPC module (subnets, IGW, NAT per AZ, route tables)
- [x] Dev environment wiring
- [x] ECR module
- [ ] EKS module (cluster and node group written, not yet verified with kubectl)
- [ ] EKS add-ons: OIDC provider, EBS CSI driver, AWS Load Balancer Controller
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
- Local Terraform state for now. Remote state is planned as a later step.