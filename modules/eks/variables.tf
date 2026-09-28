variable "project_name" {
  description = "Short name used to prefix resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster, e.g. \"1.34\""
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where the worker nodes run"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs, registered with the cluster for load balancers"
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the Kubernetes API endpoint is reachable from the internet"
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "EC2 instance types for the worker nodes"
  type        = list(string)
  default     = ["c7i-flex.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Disk size in GB for each worker node"
  type        = number
  default     = 20
}

variable "node_desired_size" {
  description = "Number of worker nodes to run normally"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}