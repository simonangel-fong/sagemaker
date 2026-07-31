# iam-pipeline.tf
#
# Phase 7, policy 3: read job logs, plus the model package group.
#
# This started as the full pipeline grant. Alice getting
# AmazonSageMakerFullAccess in 07-iam.tf made most of it redundant --
# what remains is the CloudWatch read side, which no SageMaker managed
# policy covers.
#
# The pipeline definition itself is not here. Terraform owns the durable,
# permissioned things -- this policy and the model package group below;
# src/pipeline.py owns the DAG. A pipeline definition changes when the
# model changes, not when the infrastructure does, so it lives with the
# training code. Same line phase 2 drew for data: tf provisions, the
# client moves.
#
# aws_sagemaker_pipeline does exist and takes the whole definition as one
# JSON blob. It was not used because that blob is what the SDK generates
# -- image uris, source packaging, step property references -- and any
# pipeline.upsert() from the notebook makes the stored copy stale, so the
# next apply silently reverts it.

# ##############################
# Model package group
# ##############################
# Created here rather than implicitly by the first registration: it is a
# permission boundary, it outlives every pipeline definition that writes
# to it, and phases 8 and 10 both reference it by name.
resource "aws_sagemaker_model_package_group" "bike" {
  model_package_group_name        = "${local.prefix_name}-bike-sharing-rf"
  model_package_group_description = "Bike sharing demand models. Versions land pending approval."
}

# Every sagemaker:* grant this policy used to carry -- pipelines,
# processing jobs, Search, the registry, PassRole -- is inside
# AmazonSageMakerFullAccess, which alice now has (07-iam.tf). They were
# added here one console error at a time, and keeping them would only
# obscure which grants are load-bearing.
#
# What is left is the CloudWatch read surface. FullAccess (v29) does
# carry logs:Describe* and logs:GetLogEvents, so the ListHubs-era
# DescribeLogGroups grant is now redundant -- but it stops there.
# FilterLogEvents and the Insights query pair are not in it, and those
# are what the Studio log viewer uses to search within a stream.
#
# Scoped to /aws/sagemaker rather than "*", since unlike Search these
# actions do take a resource.
#
# Phase 9 gives bob the enumerated version of the rest.
data "aws_iam_policy_document" "pipeline_access" {
  statement {
    sid    = "CloudWatchLogsSearch"
    effect = "Allow"

    actions = [
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:GetQueryResults",
      "logs:StopQuery",
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*:log-stream:*",
    ]
  }
}

resource "aws_iam_policy" "pipeline_access" {
  name        = "${local.prefix_name}-pipeline-access"
  description = "Read job logs back. The SageMaker grants come from AmazonSageMakerFullAccess."
  policy      = data.aws_iam_policy_document.pipeline_access.json
}

resource "aws_iam_role_policy_attachment" "alice_pipeline_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.pipeline_access.arn
}
