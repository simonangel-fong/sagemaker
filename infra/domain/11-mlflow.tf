# mlflow.tf
#
# Phase 6: managed MLflow, as a serverless MLflow app.
#
# The compute and the backend metadata store live in the SageMaker
# service account. Only the artifact store is in this account, under
# mlflow-app/ in the data bucket.
#
# App, not tracking server. AWS steers new work to the app: it starts in
# ~2 minutes instead of ~25, scales itself, and carries no hourly charge
# -- the tracking server billed by the hour for as long as it existed,
# which made "stop it between sessions" a standing chore. The app is
# also the Studio-facing resource; default_domain_id_list is what puts
# it in this domain's sidebar.

# ##############################
# MLflow app role
# ##############################
# Assumed by the app itself, not by alice. It needs to read and write the
# artifact prefix and the KMS key that encrypts it.
resource "aws_iam_role" "mlflow" {
  name               = "${local.prefix_name}-mlflow-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

data "aws_iam_policy_document" "mlflow_artifacts" {
  statement {
    sid    = "S3ListArtifactBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.data.arn]
  }

  statement {
    sid    = "S3ReadWriteArtifactPrefix"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.data.arn}/${local.mlflow_prefix}*"]
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

  # Needed only when model registration is on. Phase 7 flips
  # model_registration_mode; keeping the grant here means that is a
  # one-line change.
  statement {
    sid    = "ModelRegistry"
    effect = "Allow"

    actions = [
      "sagemaker:CreateModelPackageGroup",
      "sagemaker:CreateModelPackage",
      "sagemaker:DescribeModelPackage",
      "sagemaker:DescribeModelPackageGroup",
      "sagemaker:ListModelPackages",
      "sagemaker:UpdateModelPackage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "mlflow_artifacts" {
  name        = "${local.prefix_name}-mlflow-artifacts"
  description = "MLflow app access to the artifact store."
  policy      = data.aws_iam_policy_document.mlflow_artifacts.json
}

resource "aws_iam_role_policy_attachment" "mlflow_artifacts" {
  role       = aws_iam_role.mlflow.name
  policy_arn = aws_iam_policy.mlflow_artifacts.arn
}

# ##############################
# MLflow app
# ##############################
# The ARN is the tracking URI -- there is no separate URL attribute.
# mlflow.set_tracking_uri() takes it directly.
resource "aws_sagemaker_mlflow_app" "this" {
  name               = "${local.prefix_name}-mlflow-app"
  role_arn           = aws_iam_role.mlflow.arn
  artifact_store_uri = "s3://${aws_s3_bucket.data.id}/${local.mlflow_prefix}"

  default_domain_id_list = [aws_sagemaker_domain.this.id]

  # Phase 7 switches this to AutoModelRegistrationEnabled.
  model_registration_mode = "AutoModelRegistrationDisabled"
}
