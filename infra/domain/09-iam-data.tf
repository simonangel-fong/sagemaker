# iam-data.tf
#
# Phase 4, policy 1: data access.
# Kept separate from the studio-access policy so each phase's grant is
# visible on its own. Attaches to alice only; bob gets a scoped copy in
# phase 9.

data "aws_iam_policy_document" "data_access" {
  # ListBucket is a bucket-level action, the rest are object-level.
  statement {
    sid    = "S3ListDataBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.data.arn]
  }

  statement {
    sid    = "S3ReadWriteDataBucket"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.data.arn}/*"]
  }

  # Notebook-driven training jobs run as a separate SageMaker-managed
  # container that assumes this same role.
  statement {
    sid    = "SageMakerTrainingJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:ListTrainingJobs",
    ]

    resources = ["*"]
  }

  # CreateTrainingJob hands this role to the training container.
  statement {
    sid       = "PassRoleToTrainingJob"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.alice.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "data_access" {
  name        = "${local.prefix_name}-data-access"
  description = "Read/write the data bucket and run training jobs."
  policy      = data.aws_iam_policy_document.data_access.json
}

resource "aws_iam_role_policy_attachment" "alice_data_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.data_access.arn
}
