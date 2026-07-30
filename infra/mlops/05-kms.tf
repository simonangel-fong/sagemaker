# kms.tf

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
