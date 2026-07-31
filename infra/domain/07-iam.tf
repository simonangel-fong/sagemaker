# iam.tf

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

resource "aws_iam_role" "alice" {
  name               = "${local.prefix_name}-alice-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

# ##############################
# Studio access
# ##############################
# Just enough to open Studio and run a space. No data access yet --
# phase 4 attaches S3 as a separate policy.
data "aws_iam_policy_document" "studio_access" {
  # Studio calls these on load to render the launcher.
  statement {
    sid    = "StudioRead"
    effect = "Allow"

    actions = [
      "sagemaker:DescribeDomain",
      "sagemaker:DescribeUserProfile",
      "sagemaker:DescribeSpace",
      "sagemaker:DescribeApp",
      "sagemaker:ListDomains",
      "sagemaker:ListUserProfiles",
      "sagemaker:ListSpaces",
      "sagemaker:ListApps",
      "sagemaker:ListImages",
      "sagemaker:ListTags",
    ]

    resources = ["*"]
  }

  # The Studio UI mints its own presigned URLs for sub-apps once you are
  # inside it, so the execution role needs this -- not just the caller
  # who generated the initial login link.
  statement {
    sid       = "StudioPresignedUrl"
    effect    = "Allow"
    actions   = ["sagemaker:CreatePresignedDomainUrl"]
    resources = ["arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user-profile/${aws_sagemaker_domain.this.id}/*"]
  }

  # Space + app lifecycle, scoped to this domain's resources.
  statement {
    sid    = "StudioSpaceLifecycle"
    effect = "Allow"

    actions = [
      "sagemaker:CreateSpace",
      "sagemaker:UpdateSpace",
      "sagemaker:DeleteSpace",
      "sagemaker:CreateApp",
      "sagemaker:UpdateApp",
      "sagemaker:DeleteApp",
      # Studio stamps its own tags on the app it creates, so CreateApp
      # fails without this even though nothing here asks for tags.
      "sagemaker:AddTags",
    ]

    resources = [
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:space/${aws_sagemaker_domain.this.id}/*",
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:app/${aws_sagemaker_domain.this.id}/*",
      "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user-profile/${aws_sagemaker_domain.this.id}/*",
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

  # Pull the prebuilt JupyterLab images.
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

  # The domain EFS home dir is KMS encrypted; without this the app
  # fails to mount and the space hangs in Pending.
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
}

resource "aws_iam_policy" "studio_access" {
  name        = "${local.prefix_name}-studio-access"
  description = "Open Studio and run spaces. No data access."
  policy      = data.aws_iam_policy_document.studio_access.json
}

resource "aws_iam_role_policy_attachment" "alice_studio_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.studio_access.arn
}
