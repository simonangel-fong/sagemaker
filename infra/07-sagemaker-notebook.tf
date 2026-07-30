# sagemaker-notebook.tf

# ##############################
# Security group
# ##############################
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
# Notebook instance
# ##############################
resource "aws_sagemaker_notebook_instance" "this" {
  name          = "${local.prefix_name}-notebook"
  role_arn      = aws_iam_role.sagemaker_execution.arn
  instance_type = var.notebook_instance_type
  volume_size   = var.notebook_volume_size

  subnet_id              = var.public_subnet_ids[0]
  security_groups        = [aws_security_group.notebook.id]
  direct_internet_access = "Enabled"
  root_access            = "Enabled"
  kms_key_id             = aws_kms_key.this.arn

  tags = {
    Name = "${local.prefix_name}-notebook"
  }
}
