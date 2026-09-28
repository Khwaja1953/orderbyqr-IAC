variable "project_name" {
    description = "Name of the project"
    type = string
}

variable "environment" {
    description = "Environment (e.g., dev, staging, prod)"
    type = string
}

variable "vpc_cidr" {
    description = "VPC CIDR"
    type = string
}

variable "azs" {
    description = "Availability Zones"
    type = list(string)
}

variable "public_subnet_cidrs" {
    description = "Public Subnet CIDRs"
    type = list(string)
}

variable "private_subnet_cidrs" {
    description = "Private Subnet CIDRs"
    type = list(string)
}