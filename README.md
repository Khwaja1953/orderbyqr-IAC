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

ECR   -> stores frontend and backend Docker images
EKS   -> runs the containers (planned)
```

## Tech stack

- Terraform (AWS provider ~> 5.0)
- AWS: VPC, ECR, EKS
- Docker and Kubernetes
- Planned: Jenkins, Prometheus and Grafana, ArgoCD, External Secrets, Ansible

## Project structure

```
orderbyqr-terraform-eks/
├── modules/
│   ├── vpc/     # VPC, subnets, IGW, NAT gateways, route tables
│   ├── ecr/     # container image repositories
│   └── eks/     # EKS cluster, node group, IAM roles (planned)
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

## Cost warning

NAT gateways and (later) the EKS control plane and worker nodes are billed per hour while they exist. Run `terraform destroy` when you finish a session.

## Progress

- [x] VPC module (subnets, IGW, NAT per AZ, route tables)
- [x] Dev environment wiring
- [ ] ECR module (written, being applied)
- [ ] EKS module
- [ ] Dockerfiles and Kubernetes manifests for orderbyqr
- [ ] CI/CD with Jenkins
- [ ] Monitoring (Prometheus and Grafana)
- [ ] GitOps with ArgoCD
- [ ] Secrets management and hardening
- [ ] Remote state (S3 and DynamoDB locking)

## Notes and design decisions

- One NAT gateway per AZ for high availability. This is more expensive than a single shared NAT.
- Local Terraform state for now. Remote state is planned as a later step.
- Subnet CIDRs are passed in explicitly, not computed, to keep the IP layout visible.