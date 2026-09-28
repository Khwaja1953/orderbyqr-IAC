output "repository_urls" {
  description = "Map of repository name to its URL, used in docker push and Kubernetes manifests"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}