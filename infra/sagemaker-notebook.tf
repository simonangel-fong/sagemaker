# sagemaker-notebook.tf

# ##############################
# Security group
# ##############################
# Egress only: access is via the presigned URL, not inbound network.
resource "aws_security_group" "notebook" {
  name        = "${local.prefix_name}-notebook-sg"
  description = "SageMaker notebook instance"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix_name}-notebook-sg"
  }
}

# ##############################
# Code repository
# ##############################
resource "aws_sagemaker_code_repository" "this" {
  code_repository_name = "${local.prefix_name}-repo"

  git_config {
    repository_url = var.git_repository_url
    branch         = var.git_branch
  }
}

# ##############################
# Notebook instance
# ##############################
resource "aws_sagemaker_notebook_instance" "this" {
  name = "${local.prefix_name}-notebook"

  # instance
  instance_type = var.notebook_instance_type
  volume_size   = var.notebook_volume_size

  # network
  subnet_id              = var.public_subnet_ids[0]
  security_groups        = [aws_security_group.notebook.id]
  direct_internet_access = "Enabled"

  # access
  role_arn    = aws_iam_role.sagemaker_assume.arn
  root_access = "Enabled"
  kms_key_id  = aws_kms_key.this.arn

  # code repo
  default_code_repository = aws_sagemaker_code_repository.this.code_repository_name

  tags = {
    Name = "${local.prefix_name}-notebook"
  }
}
