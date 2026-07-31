# iam-pipeline.tf
#
# Phase 7, policy 3: author and run pipelines, and register the result.
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

data "aws_iam_policy_document" "pipeline_access" {
  # Authoring and running. Describe/List are what the Studio Pipelines UI
  # calls to render the DAG and its execution history.
  statement {
    sid    = "PipelineLifecycle"
    effect = "Allow"

    actions = [
      "sagemaker:CreatePipeline",
      "sagemaker:UpdatePipeline",
      "sagemaker:DeletePipeline",
      "sagemaker:DescribePipeline",
      "sagemaker:DescribePipelineDefinitionForExecution",
      "sagemaker:ListPipelines",
      "sagemaker:StartPipelineExecution",
      "sagemaker:StopPipelineExecution",
      "sagemaker:DescribePipelineExecution",
      "sagemaker:ListPipelineExecutions",
      "sagemaker:ListPipelineExecutionSteps",
      "sagemaker:ListPipelineParametersForExecution",
      # upsert() tags the pipeline, and the console stamps its own tags
      # on executions.
      "sagemaker:AddTags",
      "sagemaker:ListTags",
    ]

    resources = ["*"]
  }

  # The Studio Pipelines UI does not call ListPipelines -- it queries the
  # Search API, which is how the console enumerates every resource type.
  # Without this the panel renders an error instead of the dag, even
  # though the pipeline exists and runs fine from the sdk.
  #
  # Search takes no resource scope: it is account-wide by design, and the
  # results are filtered by what the caller can otherwise see.
  statement {
    sid    = "StudioResourceSearch"
    effect = "Allow"

    actions = [
      "sagemaker:Search",
      "sagemaker:GetSearchSuggestions",
    ]

    resources = ["*"]
  }

  # Phase 4 granted training jobs only. The preprocess and evaluate steps
  # run as processing jobs, which are a separate action family -- without
  # this the pipeline fails on its first step.
  statement {
    sid    = "ProcessingJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateProcessingJob",
      "sagemaker:DescribeProcessingJob",
      "sagemaker:StopProcessingJob",
      "sagemaker:ListProcessingJobs",
    ]

    resources = ["*"]
  }

  # The register step creates a Model and a versioned package under the
  # group above.
  statement {
    sid    = "ModelRegistry"
    effect = "Allow"

    actions = [
      "sagemaker:CreateModel",
      "sagemaker:DescribeModel",
      "sagemaker:DeleteModel",
      "sagemaker:CreateModelPackage",
      "sagemaker:DescribeModelPackage",
      "sagemaker:UpdateModelPackage",
      "sagemaker:ListModelPackages",
      "sagemaker:CreateModelPackageGroup",
      "sagemaker:DescribeModelPackageGroup",
      "sagemaker:ListModelPackageGroups",
    ]

    resources = ["*"]
  }

  # Every step runs as a SageMaker-managed container that assumes alice's
  # role. Policy 1 already grants this for training jobs; the condition is
  # on the service, not the job type, so it covers processing and the
  # pipeline itself too. Repeated here only so this phase's grant reads
  # completely on its own -- IAM unions the two, it is not a conflict.
  statement {
    sid       = "PassRoleToPipelineSteps"
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

resource "aws_iam_policy" "pipeline_access" {
  name        = "${local.prefix_name}-pipeline-access"
  description = "Author and run SageMaker pipelines, and register model versions."
  policy      = data.aws_iam_policy_document.pipeline_access.json
}

resource "aws_iam_role_policy_attachment" "alice_pipeline_access" {
  role       = aws_iam_role.alice.name
  policy_arn = aws_iam_policy.pipeline_access.arn
}
