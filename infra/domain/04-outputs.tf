# outputs.tf

# Name carries a random suffix, so this cannot be derived by hand.
output "data_bucket" {
  description = "S3 bucket for raw data, features and model artifacts."
  value       = aws_s3_bucket.data.id
}

output "kms_key_arn" {
  description = "KMS key encrypting the data bucket."
  value       = aws_kms_key.this.arn
}

output "domain_id" {
  description = "SageMaker Studio domain."
  value       = aws_sagemaker_domain.this.id
}

output "alice_role_arn" {
  description = "Execution role for the alice profile."
  value       = aws_iam_role.alice.arn
}

output "studio_login_command" {
  description = "CLI command that returns a presigned Studio URL for alice."
  value       = "aws sagemaker create-presigned-domain-url --domain-id ${aws_sagemaker_domain.this.id} --user-profile-name ${aws_sagemaker_user_profile.alice.user_profile_name} --region ${var.aws_region} --query AuthorizedUrl --output text"
}

# Phase 4 adds the S3 data policy. Phase 9 adds bob.
