# training-job.tf

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

  # SageMaker attaches an ENI to the training instance. These are the
  # permissions the SDK validates a training role for.
  statement {
    sid    = "TrainingJobNetworking"
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteNetworkInterfacePermission",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
    ]

    resources = ["*"]
  }

  # The namespace-conditioned grant in 07-iam.tf does not satisfy the SDK's
  # role validation, which checks the action unconditionally.
  statement {
    sid       = "TrainingJobMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
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
resource "aws_cloudwatch_log_group" "training_jobs" {
  name              = "/aws/sagemaker/TrainingJobs"
  retention_in_days = 14
}
