# iam.tf

# ##############################
# IAM: execution role
# ##############################
data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${local.prefix_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

# ##############################
# Sagemaker execution role: KMS policy
# ##############################
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms" {
  # Without this the key becomes unmanageable.
  statement {
    sid       = "AllowAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowSageMakerExecutionRole"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.sagemaker_execution.arn]
    }
  }
}

# ##############################
# Sagemaker execution role: S3 and cloudwatch
# ##############################

data "aws_iam_policy_document" "sagemaker_scoped" {
  statement {
    sid    = "S3DataBucket"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"]
  }

  statement {
    sid       = "CloudWatchMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["/aws/sagemaker"]
    }
  }

  statement {
    sid    = "KmsUse"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.this.arn]
  }

  # Needed by Studio/notebook to read its own config and pull built-in images.
  statement {
    sid    = "SageMakerSelfDescribe"
    effect = "Allow"

    actions = [
      "sagemaker:DescribeNotebookInstance",
      "sagemaker:DescribeDomain",
      "sagemaker:DescribeUserProfile",
      "sagemaker:ListTags",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "EcrPullBuiltInImages"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }

  # Studio launches JupyterLab as an "app" inside a "space"; without these the
  # UI shows a permission banner and no application will open.
  statement {
    sid    = "StudioSpacesAndApps"
    effect = "Allow"

    actions = [
      "sagemaker:CreatePresignedDomainUrl",
      "sagemaker:ListSpaces",
      "sagemaker:DescribeSpace",
      "sagemaker:CreateSpace",
      "sagemaker:UpdateSpace",
      "sagemaker:DeleteSpace",
      "sagemaker:ListApps",
      "sagemaker:DescribeApp",
      "sagemaker:CreateApp",
      "sagemaker:DeleteApp",
    ]

    resources = [
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${aws_sagemaker_domain.this.id}",
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user-profile/${aws_sagemaker_domain.this.id}/*",
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:space/${aws_sagemaker_domain.this.id}/*",
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:app/${aws_sagemaker_domain.this.id}/*",
    ]
  }

  # ListSpaces/ListApps are list operations and cannot be scoped to an ARN.
  statement {
    sid    = "StudioListUnscoped"
    effect = "Allow"

    actions = [
      "sagemaker:ListSpaces",
      "sagemaker:ListApps",
      "sagemaker:ListUserProfiles",
      "sagemaker:ListDomains",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "sagemaker_scoped" {
  name        = "${local.prefix_name}-execution-policy"
  description = "Least-privilege access for the SageMaker execution role"
  policy      = data.aws_iam_policy_document.sagemaker_scoped.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_scoped" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.sagemaker_scoped.arn
}

# ##############################
# KMS: Customer managed key
# ##############################
resource "aws_kms_key" "this" {
  description             = "${local.prefix_name} sagemaker encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.prefix_name}"
  target_key_id = aws_kms_key.this.key_id
}
