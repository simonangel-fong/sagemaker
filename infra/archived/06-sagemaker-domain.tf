# sagemaker-domain.tf
#
# ARCHIVED -- not part of the active stack.
#
# Studio domain kept for reference. A domain is an independent product from the
# notebook instance, not a prerequisite for it, and the notebook alone covers
# this project. Restoring it also needs the Studio spaces/apps IAM statements
# and the domain-scoped outputs that were removed from mlops/.

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
