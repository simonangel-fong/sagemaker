# iam-mlflow.tf
#
# Phase 6, policy 2: alice's access to the MLflow app.
#
# Two service prefixes are involved. sagemaker:* covers the control plane
# (describe the app, mint a UI url); sagemaker-mlflow:* covers the MLflow
# REST API itself (experiments, runs, metrics).

data "aws_iam_policy_document" "mlflow_access" {
  # The Studio sidebar enumerates apps before opening one, and List* has
  # no resource to scope to.
  #
  # Trailing wildcard: CreatePresignedMlflowAppUrl ends in Url, not App,
  # so an anchored "*MlflowApp" misses it.
  statement {
    sid    = "MlflowAppControlPlane"
    effect = "Allow"

    actions = ["sagemaker:*MlflowApp*"]

    resources = ["*"]
  }

  # The MLflow REST surface is wide (experiments, runs, metrics, params,
  # tags, registered models) and the action names track upstream MLflow
  # rather than AWS. Scoping to this one app ARN is the meaningful
  # boundary here, not enumerating actions that shift between releases.
  statement {
    sid     = "MlflowDataPlane"
    effect  = "Allow"
    actions = ["sagemaker-mlflow:*"]

    resources = [aws_sagemaker_mlflow_app.this.arn]
  }
}

resource "aws_iam_policy" "mlflow_access" {
  name        = "${local.prefix_name}-mlflow-access"
  description = "Log and read experiments on the MLflow app."
  policy      = data.aws_iam_policy_document.mlflow_access.json
}

resource "aws_iam_role_policy_attachment" "alice_mlflow_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.mlflow_access.arn
}
