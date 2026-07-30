# endpoint.tf
#
# Serverless inference: scales to zero, so nothing bills between requests.
# Set model_artifact_uri to a training job output to enable; leave it empty
# and no endpoint is created.

locals {
  endpoint_enabled = var.model_artifact_uri != ""
}

# ##############################
# Inference code
# ##############################
# The serving container fetches this tarball and imports inference.py from it.
data "archive_file" "inference_code" {
  count = local.endpoint_enabled ? 1 : 0

  type        = "tar.gz"
  source_dir  = "${path.module}/../../src"
  output_path = "${path.module}/.terraform/tmp/sourcedir.tar.gz"
}

resource "aws_s3_object" "inference_code" {
  count = local.endpoint_enabled ? 1 : 0

  bucket = aws_s3_bucket.data.id
  key    = "code/sourcedir-${data.archive_file.inference_code[0].output_md5}.tar.gz"
  source = data.archive_file.inference_code[0].output_path
  etag   = data.archive_file.inference_code[0].output_md5
}

# ##############################
# Model
# ##############################
resource "aws_sagemaker_model" "this" {
  count = local.endpoint_enabled ? 1 : 0

  name               = "${local.prefix_name}-model-${substr(data.archive_file.inference_code[0].output_md5, 0, 8)}"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image          = var.inference_image
    model_data_url = var.model_artifact_uri

    environment = {
      SAGEMAKER_PROGRAM             = "inference.py"
      SAGEMAKER_SUBMIT_DIRECTORY    = "s3://${aws_s3_bucket.data.id}/${aws_s3_object.inference_code[0].key}"
      SAGEMAKER_CONTAINER_LOG_LEVEL = "20"
      SAGEMAKER_REGION              = var.aws_region
    }
  }
}

# ##############################
# Endpoint
# ##############################
resource "aws_sagemaker_endpoint_configuration" "this" {
  count = local.endpoint_enabled ? 1 : 0

  name        = "${local.prefix_name}-endpoint-config-${substr(data.archive_file.inference_code[0].output_md5, 0, 8)}"
  kms_key_arn = aws_kms_key.this.arn

  production_variants {
    variant_name = "AllTraffic"
    model_name   = aws_sagemaker_model.this[0].name

    serverless_config {
      memory_size_in_mb = var.serverless_memory_mb
      max_concurrency   = var.serverless_max_concurrency
    }
  }
}

resource "aws_sagemaker_endpoint" "this" {
  count = local.endpoint_enabled ? 1 : 0

  name                 = "${local.prefix_name}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this[0].name
}
