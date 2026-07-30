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
# Endpoint
# ##############################
# Output of a training job, e.g.
# s3://<bucket>/models/mnist-logreg-<ts>/output/model.tar.gz
variable "model_artifact_uri" {
  description = "S3 URI of the model.tar.gz to serve. Empty disables the endpoint."
  type        = string
  default     = ""
}

variable "inference_image" {
  description = "ECR URI of the serving container."
  type        = string
  default     = "341280168497.dkr.ecr.ca-central-1.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
}

variable "serverless_memory_mb" {
  description = "Memory for serverless inference."
  type        = number
  default     = 2048

  validation {
    condition     = contains([1024, 2048, 3072, 4096, 5120, 6144], var.serverless_memory_mb)
    error_message = "serverless_memory_mb must be one of 1024, 2048, 3072, 4096, 5120, 6144."
  }
}

variable "serverless_max_concurrency" {
  description = "Concurrent invocations before throttling."
  type        = number
  default     = 2
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
