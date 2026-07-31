# iam-mlflow.tf
#
# Phase 6, policy 2: alice's access to the tracking server.
#
# Two service prefixes are involved. sagemaker:* covers the control plane
# (describe the server, mint a UI url); sagemaker-mlflow:* covers the
# MLflow REST API itself (experiments, runs, metrics).

data "aws_iam_policy_document" "mlflow_access" {
  statement {
    sid    = "MlflowControlPlane"
    effect = "Allow"

    actions = [
      "sagemaker:DescribeMlflowTrackingServer",
      "sagemaker:ListMlflowTrackingServers",
      "sagemaker:CreatePresignedMlflowTrackingServerUrl",
    ]

    resources = [aws_sagemaker_mlflow_tracking_server.this.arn]
  }

  # The Studio sidebar enumerates apps before opening one, and List* has
  # no resource to scope to.
  #
  # Wildcarded rather than enumerated: the MLflow app API postdates aws
  # cli 2.19.1, so the exact action names could not be confirmed here and
  # IAM rejects unknown action names outright at policy-creation time.
  # This matches Mlflow{App,Apps} on the sagemaker prefix only.
  statement {
    sid    = "MlflowAppDiscovery"
    effect = "Allow"

    actions = [
      "sagemaker:*MlflowApp",
      "sagemaker:*MlflowApps",
    ]

    resources = ["*"]
  }

  # The MLflow REST surface is wide (experiments, runs, metrics, params,
  # tags, registered models) and the action names track upstream MLflow
  # rather than AWS. Scoping to this one server ARN is the meaningful
  # boundary here, not enumerating actions that shift between releases.
  statement {
    sid     = "MlflowDataPlane"
    effect  = "Allow"
    actions = ["sagemaker-mlflow:*"]

    resources = [
      aws_sagemaker_mlflow_tracking_server.this.arn,
      aws_sagemaker_mlflow_app.this.arn,
    ]
  }
}

resource "aws_iam_policy" "mlflow_access" {
  name        = "${local.prefix_name}-mlflow-access"
  description = "Log and read experiments on the tracking server."
  policy      = data.aws_iam_policy_document.mlflow_access.json
}

resource "aws_iam_role_policy_attachment" "alice_mlflow_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.mlflow_access.arn
}
