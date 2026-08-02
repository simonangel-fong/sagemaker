# sagemaker-iam-role.tf


# ##############################
# IAM Role: Sagemaker
# ##############################
resource "aws_iam_role" "sagemaker_assume" {
  name = "${local.prefix_name}-assume-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      },
    ]
  })
}

# full sagemaker 
resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker_assume.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# full bucket
resource "aws_iam_role_policy_attachment" "bucket_full" {
  role       = aws_iam_role.sagemaker_assume.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
