# sagemaker-domain.tf

# Permissions are attached in 08-iam.tf via a scoped customer managed policy.

# ##############################
# Domain
# ##############################
resource "aws_sagemaker_domain" "this" {
  domain_name = "${local.prefix_name}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.public_subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }

  # remove efs when destroy
  retention_policy {
    home_efs_file_system = "Delete"
  }
}

# ##############################
# User profile
# ##############################
resource "aws_sagemaker_user_profile" "this" {
  user_profile_name = "${local.prefix_name}-user"
  domain_id         = aws_sagemaker_domain.this.id

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }
}
