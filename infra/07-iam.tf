# # iam.tf

# data "aws_iam_policy_document" "sagemaker_assume_role" {
#   statement {
#     effect  = "Allow"
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       identifiers = ["sagemaker.amazonaws.com"]
#     }
#   }
# }

# resource "aws_iam_role" "sagemaker_execution" {
#   name               = "${local.prefix_name}-execution-role"
#   assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
# }

# data "aws_iam_policy_document" "sagemaker_scoped" {
#   statement {
#     sid    = "S3DataBucket"
#     effect = "Allow"

#     actions = [
#       "s3:GetObject",
#       "s3:PutObject",
#       "s3:DeleteObject",
#       "s3:ListBucket",
#       "s3:GetBucketLocation",
#     ]

#     resources = [
#       aws_s3_bucket.data.arn,
#       "${aws_s3_bucket.data.arn}/*",
#     ]
#   }

#   statement {
#     sid    = "CloudWatchLogs"
#     effect = "Allow"

#     actions = [
#       "logs:CreateLogGroup",
#       "logs:CreateLogStream",
#       "logs:PutLogEvents",
#       "logs:DescribeLogStreams",
#     ]

#     resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"]
#   }

#   statement {
#     sid       = "CloudWatchMetrics"
#     effect    = "Allow"
#     actions   = ["cloudwatch:PutMetricData"]
#     resources = ["*"]

#     condition {
#       test     = "StringEquals"
#       variable = "cloudwatch:namespace"
#       values   = ["/aws/sagemaker"]
#     }
#   }

#   statement {
#     sid    = "KmsUse"
#     effect = "Allow"

#     actions = [
#       "kms:Encrypt",
#       "kms:Decrypt",
#       "kms:ReEncrypt*",
#       "kms:GenerateDataKey*",
#       "kms:DescribeKey",
#     ]

#     resources = [aws_kms_key.this.arn]
#   }

#   statement {
#     sid    = "SageMakerSelfDescribe"
#     effect = "Allow"

#     actions = [
#       "sagemaker:DescribeNotebookInstance",
#       "sagemaker:ListTags",
#     ]

#     resources = ["*"]
#   }

#   # Pull the prebuilt framework images.
#   statement {
#     sid    = "EcrPullBuiltInImages"
#     effect = "Allow"

#     actions = [
#       "ecr:GetAuthorizationToken",
#       "ecr:BatchCheckLayerAvailability",
#       "ecr:GetDownloadUrlForLayer",
#       "ecr:BatchGetImage",
#     ]

#     resources = ["*"]
#   }
# }

# resource "aws_iam_policy" "sagemaker_scoped" {
#   name        = "${local.prefix_name}-execution-policy"
#   description = "Least-privilege access for the SageMaker execution role"
#   policy      = data.aws_iam_policy_document.sagemaker_scoped.json
# }

# resource "aws_iam_role_policy_attachment" "sagemaker_scoped" {
#   role       = aws_iam_role.sagemaker_execution.name
#   policy_arn = aws_iam_policy.sagemaker_scoped.arn
# }
