# variables of vpc 
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "project_name" {
  description = "Short project name used for tagging/naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}


# variables of ecr
variable "repository_names" {
  description = "Names of the ECR repositories to create"
  type        = list(string)
}