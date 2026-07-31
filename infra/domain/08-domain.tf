# domain.tf

# ##############################
# Domain
# ##############################
resource "aws_sagemaker_domain" "this" {
  domain_name = "${local.prefix_name}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.public_subnet_ids

  # Studio apps pull packages from PyPI, so they need egress.
  app_network_access_type = "PublicInternetOnly"

  kms_key_id = aws_kms_key.this.arn

  default_user_settings {
    execution_role = aws_iam_role.alice.arn
  }

  # Study stack: drop the EFS volume on destroy so it stops costing.
  retention_policy {
    home_efs_file_system = "Delete"
  }
}

# ##############################
# User profile -- alice (admin)
# ##############################
resource "aws_sagemaker_user_profile" "alice" {
  domain_id         = aws_sagemaker_domain.this.id
  user_profile_name = "alice"

  user_settings {
    execution_role = aws_iam_role.alice.arn
  }
}
