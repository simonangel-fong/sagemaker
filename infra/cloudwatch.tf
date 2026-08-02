# cloudwatch.tf

# ##############################
# Logs: Train Job
# ##############################
# required by train job
resource "aws_cloudwatch_log_group" "training_jobs" {
  name              = "/aws/sagemaker/TrainingJobs"
  retention_in_days = 7
}

