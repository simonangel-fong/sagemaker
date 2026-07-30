# outputs.tf

# Notebook instance is disabled in 08-sagemaker-notebook.tf.
# output "notebook_login_command" {
#   description = "CLI command that returns a presigned login URL."
#   value       = "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.this.name} --region ${var.aws_region} --query AuthorizedUrl --output text"
# }

output "data_bucket" {
  description = "S3 bucket the notebook can read/write."
  value       = aws_s3_bucket.data.id
}

output "execution_role_arn" {
  description = "Role passed to SageMaker training jobs."
  value       = aws_iam_role.sagemaker_execution.arn
}

output "training_input_uri" {
  description = "S3 prefix used as the training channel."
  value       = "s3://${aws_s3_bucket.data.id}/raw/mnist/"
}

output "training_output_uri" {
  description = "S3 prefix where job artifacts land."
  value       = "s3://${aws_s3_bucket.data.id}/models/"
}

output "endpoint_name" {
  description = "Serverless inference endpoint, null when disabled."
  value       = one(aws_sagemaker_endpoint.this[*].name)
}
