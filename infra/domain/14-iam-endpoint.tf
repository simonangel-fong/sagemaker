# iam-endpoint.tf
#
# Phase 8: the role the endpoint runs as.
#
# Not alice. Alice is a person with a Studio session; the endpoint is a
# service that wakes on an invoke, pulls the artifact from S3 and
# decrypts it, with nobody logged in. Same reasoning as the MLflow app
# role in 11-mlflow.tf.
#
# Declared here rather than letting the deploy create one. An
# auto-generated AmazonSageMaker-ExecutionRole-<timestamp> lives outside
# this stack, is not in state, and survives the phase 11 destroy.
#
# The endpoint itself is not here -- the pipeline's deploy step creates
# it, the same way the pipeline definition lives in src/pipeline.py
# rather than in terraform. This file is the durable, permissioned part.

resource "aws_iam_role" "endpoint" {
  name               = "${local.prefix_name}-endpoint-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

data "aws_iam_policy_document" "endpoint_access" {
  # Read-only on the data bucket. The endpoint serves a model; it has no
  # reason to write anything back, which is the difference between this
  # and alice's data policy.
  statement {
    sid    = "S3ReadModelArtifact"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]
  }

  # The artifact is encrypted with the customer key, so serving it means
  # decrypting it on every cold start. Decrypt only -- nothing here
  # produces new ciphertext.
  statement {
    sid    = "KmsDecryptArtifact"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [aws_kms_key.this.arn]
  }

  # Container logs and the invocation metrics the Endpoints console page
  # renders.
  statement {
    sid    = "CloudWatchWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "cloudwatch:PutMetricData",
    ]

    resources = ["*"]
  }

  # Pull the serving container.
  statement {
    sid    = "EcrPullServingImage"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "endpoint_access" {
  name        = "${local.prefix_name}-endpoint-access"
  description = "Serve the registered model: read the artifact, decrypt it, log."
  policy      = data.aws_iam_policy_document.endpoint_access.json
}

resource "aws_iam_role_policy_attachment" "endpoint_access" {
  role       = aws_iam_role.endpoint.name
  policy_arn = aws_iam_policy.endpoint_access.arn
}

# Alice passes this role to the deploy step. Her FullAccess covers
# PassRole broadly, but naming it here documents the handoff and is what
# bob's narrower grant will point at in phase 10.
data "aws_iam_policy_document" "pass_endpoint_role" {
  statement {
    sid       = "PassEndpointRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.endpoint.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "pass_endpoint_role" {
  name        = "${local.prefix_name}-pass-endpoint-role"
  description = "Hand the endpoint role to SageMaker when deploying."
  policy      = data.aws_iam_policy_document.pass_endpoint_role.json
}

resource "aws_iam_role_policy_attachment" "alice_pass_endpoint_role" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.pass_endpoint_role.arn
}
