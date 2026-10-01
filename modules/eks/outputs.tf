output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 certificate data used to trust the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_role_arn" {
  description = "ARN of the IAM role used by the worker nodes"
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider, used when building IAM roles trusted by specific service accounts"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL without the https:// prefix, used in IAM trust policy conditions"
  value       = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

output "ebs_csi_role_arn" {
  description = "ARN of the IAM role for the EBS CSI driver, used when creating its Kubernetes ServiceAccount"
  value       = aws_iam_role.ebs_csi.arn
}

output "lb_controller_role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller, used when installing it via Helm"
  value       = aws_iam_role.lb_controller.arn
}