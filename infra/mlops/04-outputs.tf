# outputs.tf

output "notebook_login_command" {
  description = "CLI command that returns a presigned login URL."
  value       = "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name ${aws_sagemaker_notebook_instance.this.name} --region ${var.aws_region} --query AuthorizedUrl --output text"
}

# Name carries a random suffix, so this cannot be derived by hand.
output "data_bucket" {
  description = "S3 bucket for data, models and inference code."
  value       = aws_s3_bucket.data.id
}

output "execution_role_arn" {
  description = "Role passed to training jobs and the endpoint."
  value       = aws_iam_role.sagemaker_execution.arn
}

output "endpoint_name" {
  description = "Serverless inference endpoint, null when disabled."
  value       = one(aws_sagemaker_endpoint.this[*].name)
}

# Public, unauthenticated. Anyone with this URL can spend inference.
output "api_url" {
  description = "Public HTTPS predict URL, null when the endpoint is disabled."
  value       = local.endpoint_enabled ? "${aws_apigatewayv2_stage.default[0].invoke_url}/predict" : null
}
