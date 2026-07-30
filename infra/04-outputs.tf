# outputs.tf

# ##############################
# Sagemaker domain
# ##############################
output "domain_url" {
  description = "Studio landing URL for the domain."
  value       = aws_sagemaker_domain.this.url
}

# ##############################
# Sagemaker notebook
# ##############################
# Command to create login url
output "notebook_login_command" {
  description = "CLI command that returns a presigned login URL."
  value       = "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.this.name} --region ${var.aws_region} --query AuthorizedUrl --output text"
}

# ##############################
# Storage
# ##############################
# Referenced by notebooks/train.ipynb.
output "data_bucket" {
  description = "S3 bucket the notebook can read/write."
  value       = aws_s3_bucket.data.id
}
