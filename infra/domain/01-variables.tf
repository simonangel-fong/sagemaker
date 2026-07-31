# variables.tf

# ##############################
# Metadata
# ##############################
variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "sagemaker-domain"
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
  description = "Existing VPC to place the Studio domain in."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must look like vpc-xxxxxxxx."
  }
}

# Studio apps pull pip packages, so these need an IGW or NAT route.
variable "public_subnet_ids" {
  description = "Subnets for the Studio domain. Must have a route to an IGW or NAT."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids must not be empty."
  }
}

# ##############################
# Studio Space
# ##############################
variable "space_instance_type" {
  description = "Default instance type for the JupyterLab app in a space."
  type        = string
  default     = "ml.t3.medium"
}

variable "space_volume_size" {
  description = "Size in GB of the space EBS volume."
  type        = number
  default     = 5

  validation {
    condition     = var.space_volume_size >= 5 && var.space_volume_size <= 16384
    error_message = "space_volume_size must be between 5 and 16384 GB."
  }
}

# ##############################
# MLflow
# ##############################
variable "mlflow_server_size" {
  description = "Tracking server size. Small is the cheapest and fits a study stack."
  type        = string
  default     = "Small"

  validation {
    condition     = contains(["Small", "Medium", "Large"], var.mlflow_server_size)
    error_message = "mlflow_server_size must be one of: Small, Medium, Large."
  }
}

# ##############################
# Git
# ##############################
variable "git_repository_url" {
  description = "HTTPS URL offered in the JupyterLab clone menu."
  type        = string
}
