# mlflow.tf
#
# Phase 6: managed MLflow tracking server.
#
# The compute and the backend metadata store live in the SageMaker
# service account. Only the artifact store is in this account, under
# mlflow/ in the data bucket.

# ##############################
# Tracking server role
# ##############################
# Assumed by the tracking server itself, not by alice. It needs to read
# and write the artifact prefix and the KMS key that encrypts it.
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

  # Needed only when automatic_model_registration is on. Phase 7 turns it
  # on; keeping the grant here means that flip is a one-line change.
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
  description = "Tracking server access to the artifact store."
  policy      = data.aws_iam_policy_document.mlflow_artifacts.json
}

resource "aws_iam_role_policy_attachment" "mlflow_artifacts" {
  role       = aws_iam_role.mlflow.name
  policy_arn = aws_iam_policy.mlflow_artifacts.arn
}

# ##############################
# Tracking server
# ##############################
resource "aws_sagemaker_mlflow_tracking_server" "this" {
  tracking_server_name = "${local.prefix_name}-mlflow"
  role_arn             = aws_iam_role.mlflow.arn
  artifact_store_uri   = "s3://${aws_s3_bucket.data.id}/${local.mlflow_prefix}"

  # Smallest size. This bills hourly while the server exists, so stop or
  # destroy it between study sessions.
  tracking_server_size = var.mlflow_server_size

  # Phase 7 flips this on to auto-register models from pipeline runs.
  automatic_model_registration = false
}

# ##############################
# MLflow app
# ##############################
# The tracking server alone is reachable by ARN but does not appear in
# the Studio sidebar. The MLflow *app* is the Studio-facing resource, and
# default_domain_id_list is what binds it to this domain's UI.
resource "aws_sagemaker_mlflow_app" "this" {
  name               = "${local.prefix_name}-mlflow-app"
  role_arn           = aws_iam_role.mlflow.arn
  artifact_store_uri = "s3://${aws_s3_bucket.data.id}/${local.mlflow_prefix}"

  default_domain_id_list = [aws_sagemaker_domain.this.id]

  # Phase 7 switches this to AutoModelRegistrationEnabled.
  model_registration_mode = "AutoModelRegistrationDisabled"
}
