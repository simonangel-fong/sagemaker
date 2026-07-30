# sagemaker.tf

# ##############################
# IAM: execution role
# ##############################
data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${local.prefix_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# ##############################
# Domain
# ##############################
resource "aws_sagemaker_domain" "this" {
  domain_name = "${local.prefix_name}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
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
