# bob.tf
#
# Phase 9: the second persona.
#
# Alice is the domain admin and carries AmazonSageMakerFullAccess. Bob is
# a data scientist: enumerated policies, S3 scoped to his own prefix, and
# no path to the managed policy. The contrast between the two roles is
# the point of this phase -- the isolation is only demonstrable because
# one side is actually narrow.
#
# Everything bob needs lives in this one file rather than being spread
# across numbered policy files the way alice's was. Alice's grants were
# split that way because each phase added one; bob arrives complete.

# ##############################
# Role
# ##############################
resource "aws_iam_role" "bob" {
  name               = "${local.prefix_name}-bob-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

# The enumerated Studio floor from phase 3. This is what it was kept for
# after alice moved to the managed policy: it is the minimum to open
# Studio and run a space, and it grants no data access at all.
resource "aws_iam_role_policy_attachment" "bob_studio_access" {
  role       = aws_iam_role.bob.name
  policy_arn = aws_iam_policy.studio_access.arn
}

# ##############################
# Data access -- scoped
# ##############################
# Alice's equivalent (09-iam-data.tf) grants the whole bucket. Bob gets
# his own prefix for writes and read-only on the shared raw data.
data "aws_iam_policy_document" "bob_data_access" {
  # ListBucket is bucket-level, so the scoping has to be expressed as a
  # condition on the key prefix rather than in the resource ARN.
  # Without the condition bob could enumerate alice's objects even though
  # he cannot read them.
  statement {
    sid       = "S3ListOwnPrefixAndRaw"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"

      values = [
        "${local.bob_prefix}*",
        "raw/*",
        # The console sends an empty prefix when opening the bucket root.
        "",
      ]
    }
  }

  statement {
    sid       = "S3GetBucketLocation"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.data.arn]
  }

  # Read the shared training data. Bob trains on the same raw/ alice does
  # -- phase 10 has him fitting a variant of her model.
  statement {
    sid       = "S3ReadRaw"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/raw/*"]
  }

  # Read and write his own prefix.
  statement {
    sid    = "S3ReadWriteOwnPrefix"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.data.arn}/${local.bob_prefix}*"]
  }

  # An explicit Deny on the prefixes alice writes to.
  #
  # Redundant on paper -- nothing above allows them, and IAM denies by
  # default. It is here because phase 9's verify step is "bob is denied
  # on alice's prefix", and a default deny and an explicit deny are
  # indistinguishable from the error message. This makes the boundary a
  # stated rule rather than an absence, and it survives someone later
  # attaching a broader policy to bob.
  statement {
    sid    = "DenyAliceOutputs"
    effect = "Deny"

    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.data.arn}/featured/*",
      "${aws_s3_bucket.data.arn}/model/*",
      "${aws_s3_bucket.data.arn}/${local.mlflow_prefix}*",
    ]
  }

  # The data bucket is SSE-KMS, so reading any object at all needs the
  # key. Encrypt is included because writing to his own prefix has to
  # produce ciphertext.
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

  # Same training-job grant alice got in phase 4. Bob trains a variant in
  # phase 10; without this he can open Studio but not fit anything on
  # managed compute.
  statement {
    sid    = "SageMakerTrainingJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:ListTrainingJobs",
    ]

    resources = ["*"]
  }

  statement {
    sid       = "PassOwnRoleToTrainingJob"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.bob.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "bob_data_access" {
  name        = "${local.prefix_name}-bob-data-access"
  description = "Read raw data, read/write only bob's own prefix."
  policy      = data.aws_iam_policy_document.bob_data_access.json
}

resource "aws_iam_role_policy_attachment" "bob_data_access" {
  role       = aws_iam_role.bob.name
  policy_arn = aws_iam_policy.bob_data_access.arn
}

# ##############################
# Profile and space
# ##############################
resource "aws_sagemaker_user_profile" "bob" {
  domain_id         = aws_sagemaker_domain.this.id
  user_profile_name = "bob"

  user_settings {
    # The domain's default_user_settings point at alice's role. Setting
    # it here is what actually separates the two personas -- without it
    # bob would inherit alice's execution role and the whole isolation
    # test would pass for the wrong reason.
    execution_role = aws_iam_role.bob.arn
  }
}

resource "aws_sagemaker_space" "bob" {
  domain_id  = aws_sagemaker_domain.this.id
  space_name = "bob-jupyterlab"

  space_sharing_settings {
    sharing_type = "Private"
  }

  ownership_settings {
    owner_user_profile_name = aws_sagemaker_user_profile.bob.user_profile_name
  }

  space_settings {
    app_type = "JupyterLab"

    jupyter_lab_app_settings {
      default_resource_spec {
        instance_type        = var.space_instance_type
        lifecycle_config_arn = aws_sagemaker_studio_lifecycle_config.clone_repo.arn
      }

      code_repository {
        repository_url = var.git_repository_url
      }
    }

    space_storage_settings {
      ebs_storage_settings {
        ebs_volume_size_in_gb = var.space_volume_size
      }
    }
  }
}
