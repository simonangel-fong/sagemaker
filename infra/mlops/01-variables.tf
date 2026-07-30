# variables.tf

# ##############################
# Metadata
# ##############################
variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "sagemaker"
}

variable "env" {
  description = "Deployment environment (dev, test, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.env)
    error_message = "env must be one of: dev, test, prod."
  }
}

variable "tags" {
  description = "Additional tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

# ##############################
# AWS
# ##############################
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ca-central-1"
}

# ##############################
# VPC
# ##############################
variable "vpc_id" {
  description = "Existing VPC to place SageMaker resources in."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-xxxxxxxx."
  }
}

# Must reach an IGW or NAT: the notebook pulls pip packages and datasets.
variable "public_subnet_ids" {
  description = "Subnets for SageMaker. Must have a route to an IGW or NAT."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids must not be empty."
  }
}

# ##############################
# Sagemaker
# ##############################
variable "notebook_instance_type" {
  description = "EC2 instance type for the SageMaker notebook instance."
  type        = string
  default     = "ml.t3.medium"
}

variable "notebook_volume_size" {
  description = "Size in GB of the notebook instance EBS volume."
  type        = number
  default     = 5

  validation {
    condition     = var.notebook_volume_size >= 5 && var.notebook_volume_size <= 16384
    error_message = "notebook_volume_size must be between 5 and 16384 GB."
  }
}

# ##############################
# Git
# ##############################
variable "git_repository_url" {
  description = "HTTPS URL of the repo cloned into the notebook on start."
  type        = string
}

variable "git_branch" {
  description = "Branch to check out."
  type        = string
  default     = "master"
}
