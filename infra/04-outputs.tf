# outputs.tf

# ##############################
# Bucket
# ##############################
output "data_bucket" {
  description = "S3 bucket for raw data, features and model artifacts."
  value       = aws_s3_bucket.data.id
}


# ##############################
# Notebook
# ##############################
output "notebook_login_command" {
  description = "CLI command that returns a presigned login URL."
  value       = "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.this.name} --region ${var.aws_region} --query AuthorizedUrl --output text"
}

# ##############################
# Sagemaker
# ##############################
output "sagemaker_execution_role_arn" {
  description = "Role passed to training jobs and the endpoint."
  value       = aws_iam_role.sagemaker_assume.arn
}

output "endpoint_name" {
  description = "Serverless inference endpoint, null when disabled."
  value       = one(aws_sagemaker_endpoint.this[*].name)
}

# ##############################
# API Gateway
# ##############################
output "api_url" {
  description = "Public HTTPS predict URL, null when the endpoint is disabled."
  value       = local.endpoint_enabled ? "${aws_apigatewayv2_stage.default[0].invoke_url}predict" : null
}
