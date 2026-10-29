terraform {
  required_version = ">=1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# module of vpc
module "vpc" {
  source               = "../../modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# Automatically cleans up any out-of-band ALBs, ENIs, and security groups
# created by Kubernetes before Terraform attempts to delete subnets and VPC.
# By making module.eks depend on this resource, Terraform guarantees that
# module.eks (and all worker nodes) are 100% destroyed BEFORE this cleanup runs,
# and this cleanup completes BEFORE module.vpc is destroyed.
resource "terraform_data" "k8s_alb_cleanup" {
  triggers_replace = [
    module.vpc.vpc_id,
    var.aws_region
  ]

  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      VPC_ID="${self.triggers_replace[0]}"
      REGION="${self.triggers_replace[1]}"

      echo "=== [Auto-Cleanup] Starting pre-VPC destruction cleanup for VPC: $VPC_ID ==="

      # 1. Delete all ALBs / NLBs in this VPC
      ALB_ARNS=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || true)

      if [ -n "$ALB_ARNS" ] && [ "$ALB_ARNS" != "None" ]; then
        for arn in $ALB_ARNS; do
          echo "[Auto-Cleanup] Deleting Load Balancer: $arn"
          aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" || true
        done

        echo "[Auto-Cleanup] Waiting for Load Balancer ENIs to detach..."
        for attempt in $(seq 1 30); do
          ENI_COUNT=$(aws ec2 describe-network-interfaces \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB *" \
            --query "length(NetworkInterfaces)" --output text 2>/dev/null || echo "0")

          if [ "$ENI_COUNT" = "0" ] || [ -z "$ENI_COUNT" ]; then
            echo "[Auto-Cleanup] All Load Balancer ENIs detached."
            break
          fi
          echo "[Auto-Cleanup] Waiting for $ENI_COUNT ENI(s)... ($attempt/30)"
          sleep 5
        done
      fi

      # 2. Delete all Target Groups in this VPC
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text 2>/dev/null || true)

      if [ -n "$TG_ARNS" ] && [ "$TG_ARNS" != "None" ]; then
        for tg in $TG_ARNS; do
          echo "[Auto-Cleanup] Deleting Target Group: $tg"
          aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg" || true
        done
      fi

      # 3. Wait for any remaining ENIs in the VPC to detach / release
      echo "[Auto-Cleanup] Checking for any active ENIs in the VPC..."
      for attempt in $(seq 1 20); do
        ACTIVE_ENIS=$(aws ec2 describe-network-interfaces \
          --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query "NetworkInterfaces[?Status!='available'].NetworkInterfaceId" \
          --output text 2>/dev/null || true)

        if [ -z "$ACTIVE_ENIS" ] || [ "$ACTIVE_ENIS" = "None" ]; then
          break
        fi
        echo "[Auto-Cleanup] Waiting for active ENIs to clear... ($attempt/20)"
        sleep 5
      done

      # Delete any unattached/available ENIs
      AVAILABLE_ENIS=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
        --output text 2>/dev/null || true)

      for eni in $AVAILABLE_ENIS; do
        if [ -n "$eni" ] && [ "$eni" != "None" ]; then
          echo "[Auto-Cleanup] Deleting available ENI: $eni"
          aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
        fi
      done

      # 4. Delete all non-default Security Groups in this VPC
      # Loop with rule-revocation to resolve circular security group references
      echo "[Auto-Cleanup] Deleting non-default security groups in VPC..."
      for attempt in $(seq 1 10); do
        SGS=$(aws ec2 describe-security-groups \
          --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query "SecurityGroups[?GroupName!='default'].GroupId" \
          --output text 2>/dev/null || true)

        if [ -z "$SGS" ] || [ "$SGS" = "None" ]; then
          echo "[Auto-Cleanup] All non-default security groups removed."
          break
        fi

        for sg in $SGS; do
          # Strip ingress rules to break circular dependencies
          aws ec2 revoke-security-group-ingress \
            --region "$REGION" \
            --group-id "$sg" \
            --protocol all \
            --source-group "$sg" 2>/dev/null || true

          aws ec2 delete-security-group \
            --region "$REGION" \
            --group-id "$sg" 2>/dev/null || true
        done
        sleep 3
      done

      echo "=== [Auto-Cleanup] Completed successfully. VPC is clean. ==="
    EOT
  }

  depends_on = [module.vpc]
}

# module of ecr
module "ecr" {
  source           = "../../modules/ecr"
  project_name     = var.project_name
  environment      = var.environment
  repository_names = var.repository_names
}

# module of eks
module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  environment     = var.environment
  cluster_version = var.cluster_version

  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  node_desired_size = var.node_desired_size
  node_min_size     = var.node_min_size
  node_max_size     = var.node_max_size

  depends_on = [terraform_data.k8s_alb_cleanup]
}

# Install the AWS Load Balancer Controller through Terraform-managed Helm.
# The chart creates the Kubernetes service account and applies the IRSA role
# annotation, so no kubectl or Helm commands are required after apply.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.1"
  namespace  = "kube-system"

  wait    = true
  atomic  = true
  timeout = 600

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lb_controller_role_arn
  }

  depends_on = [module.eks]
}
