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
  default     = "us-east-1"
}

# ##############################
# VPC
# ##############################
variable "vpc_id" {
  description = "Existing VPC to place SageMaker resources in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets for SageMaker. Must have a route to an IGW or NAT."
  type        = list(string)
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
