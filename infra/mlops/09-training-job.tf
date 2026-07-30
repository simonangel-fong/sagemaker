# training-job.tf
#
# Training jobs are created at submit time via the SageMaker API, not declared
# here. This file grants the permissions a submitter needs and gives the job
# somewhere to write.

# ##############################
# Submit permissions
# ##############################
data "aws_iam_policy_document" "training_job" {
  statement {
    sid    = "ManageTrainingJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:ListTrainingJobs",
      "sagemaker:AddTags",
    ]

    resources = ["*"]
  }

  # Submitting a job hands the execution role to SageMaker, which needs an
  # explicit PassRole grant.
  statement {
    sid       = "PassExecutionRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.sagemaker_execution.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "training_job" {
  name        = "${local.prefix_name}-training-job-policy"
  description = "Submit SageMaker training jobs and pass the execution role"
  policy      = data.aws_iam_policy_document.training_job.json
}

resource "aws_iam_role_policy_attachment" "training_job" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.training_job.arn
}

# ##############################
# Job logs
# ##############################
# Created explicitly so retention is bounded; SageMaker would otherwise make
# this group with no expiry.
resource "aws_cloudwatch_log_group" "training_jobs" {
  name              = "/aws/sagemaker/TrainingJobs"
  retention_in_days = 14
}
