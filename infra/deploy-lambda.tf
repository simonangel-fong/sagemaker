# lambda.tf

# ##############################
# IAM Role: Lambda
# ##############################
resource "aws_iam_role" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  name = "${local.prefix_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

data "aws_iam_policy_document" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  statement {
    sid       = "InvokeThisEndpointOnly"
    effect    = "Allow"
    actions   = ["sagemaker:InvokeEndpoint"]
    resources = [aws_sagemaker_endpoint.this[0].arn]
  }

  statement {
    sid       = "KmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.api_lambda[0].arn}:*"]
  }
}

resource "aws_iam_policy" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  name        = "${local.prefix_name}-api-policy"
  description = "Least-privilege access for the predict API Lambda"
  policy      = data.aws_iam_policy_document.api_lambda[0].json
}

resource "aws_iam_role_policy_attachment" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  role       = aws_iam_role.api_lambda[0].name
  policy_arn = aws_iam_policy.api_lambda[0].arn
}

# ##############################
# Function
# ##############################
# Lambda package
data "archive_file" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/../lambda/predict"
  output_path = "${path.module}/.terraform/tmp/predict-lambda.zip"
  excludes    = ["__pycache__"]
}

resource "aws_lambda_function" "api" {
  count = local.endpoint_enabled ? 1 : 0

  function_name = "${local.prefix_name}-predict"
  role          = aws_iam_role.api_lambda[0].arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = data.archive_file.api_lambda[0].output_path
  source_code_hash = data.archive_file.api_lambda[0].output_base64sha256

  # Serverless inference cold-starts; the default 3s would time out first.
  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      ENDPOINT_NAME = aws_sagemaker_endpoint.this[0].name # sagemaker endpoint
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_lambda,
    aws_cloudwatch_log_group.api_lambda,
  ]
}

# Log
resource "aws_cloudwatch_log_group" "api_lambda" {
  count = local.endpoint_enabled ? 1 : 0

  name              = "/aws/lambda/${local.prefix_name}-predict"
  retention_in_days = 14
}
