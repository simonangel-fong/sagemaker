# outputs.tf

output "notebook_login_command" {
  description = "CLI command that returns a presigned login URL."
  value       = "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.this.name} --region ${var.aws_region} --query AuthorizedUrl --output text"
}

output "data_bucket" {
  description = "S3 bucket the notebook can read/write."
  value       = aws_s3_bucket.data.id
}

output "execution_role_arn" {
  description = "Role passed to SageMaker training jobs."
  value       = aws_iam_role.sagemaker_execution.arn
}
