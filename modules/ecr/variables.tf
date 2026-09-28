variable "project_name" {
  description = "short name used to prefix the repository name"
  type = string
}

variable "environment" {
  description = "environment name used to prefix the repository name"
  type = string
}

variable "repository_names" {
  description = "names of the ECR repositories"
  type = list(string)
}