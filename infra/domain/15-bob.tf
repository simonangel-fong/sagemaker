# bob.tf
#
# Phase 9: the second persona.
#
# Alice is the domain admin and carries AmazonSageMakerFullAccess. Bob is
# a data scientist: enumerated policies rather than the managed one.
#
# The line is not "bob can do less of everything". He does the same work
# alice does -- reads the shared data, runs jobs and pipelines, tracks
# experiments in MLflow, registers model versions. Three things are his
# alone to not do:
#
#   1. overwrite alice's outputs   (featured/, model/, mlflow-app/)
#   2. approve a model version     (UpdateModelPackage)
#   3. deploy                      (Create/UpdateEndpoint)
#
# Everything else is open, because a role that cannot read a teammate's
# work or automate its own is not a data scientist -- and phase 10 is
# about the handoff between two people who are both working, not about
# one of them being locked out.
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
  # ListBucket is bucket-level, so the readable prefixes have to be
  # expressed as a condition rather than in the resource ARN. Listing
  # follows reading: bob can see what he can fetch.
  statement {
    sid       = "S3ListReadablePrefixes"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"

      values = [
        "${local.bob_prefix}*",
        "raw/*",
        "featured/*",
        "model/*",
        "${local.mlflow_prefix}*",
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

  # Read the shared training data, and alice's feature and model output.
  # Bob trains a variant of her model in phase 10, which means starting
  # from the same featured/ frame -- re-deriving it would make the two
  # runs incomparable, which is the whole point of the exercise.
  statement {
    sid     = "S3ReadSharedData"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = [
      "${aws_s3_bucket.data.arn}/raw/*",
      "${aws_s3_bucket.data.arn}/featured/*",
      "${aws_s3_bucket.data.arn}/model/*",
    ]
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

  # The MLflow artifact store, read-only. Phase 10 has bob reading
  # alice's runs and comparing them to his own -- the mlflow client
  # fetches logged models and artifacts straight from S3, so a deny here
  # makes the run comparison fail even with the API grant below.
  statement {
    sid       = "S3ReadMlflowArtifacts"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data.arn}/${local.mlflow_prefix}*"]
  }

  # An explicit Deny on the prefixes alice writes to.
  #
  # Read is not the concern -- a team that cannot see each other's work
  # is not collaborating, and phase 10 is about the handoff. What bob
  # must not do is overwrite alice's outputs, which is exactly what the
  # phase 7 bug did by accident when the pipeline clobbered
  # featured/hour.parquet.
  #
  # So: writes denied, reads allowed. Deny wins over any Allow, including
  # a broader policy attached to bob later.
  statement {
    sid    = "DenyWritesToAliceOutputs"
    effect = "Deny"

    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectAcl",
    ]

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

  # Jobs. Training and processing both, matching what alice needed for
  # phases 4 and 7 -- bob runs the same pipeline in phase 10, and a
  # pipeline whose first step is a processing job is useless without it.
  statement {
    sid    = "SageMakerJobs"
    effect = "Allow"

    actions = [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:ListTrainingJobs",
      "sagemaker:CreateProcessingJob",
      "sagemaker:DescribeProcessingJob",
      "sagemaker:StopProcessingJob",
      "sagemaker:ListProcessingJobs",
    ]

    resources = ["*"]
  }

  # Pipelines. Bob authors and runs his own; the isolation that matters
  # is on the data he can read and the approval he cannot give, not on
  # whether he is allowed to automate his work.
  statement {
    sid    = "Pipelines"
    effect = "Allow"

    actions = [
      "sagemaker:CreatePipeline",
      "sagemaker:UpdatePipeline",
      "sagemaker:DescribePipeline",
      "sagemaker:DescribePipelineDefinitionForExecution",
      "sagemaker:ListPipelines",
      "sagemaker:StartPipelineExecution",
      "sagemaker:StopPipelineExecution",
      "sagemaker:DescribePipelineExecution",
      "sagemaker:ListPipelineExecutions",
      "sagemaker:ListPipelineExecutionSteps",
      "sagemaker:ListPipelineParametersForExecution",
      "sagemaker:AddTags",
      "sagemaker:ListTags",
    ]

    resources = ["*"]
  }

  # The registry, read plus register -- but NOT UpdateModelPackage.
  #
  # This is the real boundary of phase 10. Bob trains a variant and
  # registers it as a new version; the version lands
  # PendingManualApproval and he cannot move it. Alice approves. Deleting
  # is hers too.
  #
  # CreateModel is here because registering through the SDK's ModelStep
  # creates a Model resource on the way to the package.
  statement {
    sid    = "ModelRegistryReadAndRegister"
    effect = "Allow"

    actions = [
      "sagemaker:CreateModel",
      "sagemaker:DescribeModel",
      "sagemaker:CreateModelPackage",
      "sagemaker:DescribeModelPackage",
      "sagemaker:ListModelPackages",
      "sagemaker:DescribeModelPackageGroup",
      "sagemaker:ListModelPackageGroups",
    ]

    resources = ["*"]
  }

  # Named explicitly rather than left to implicit deny. Phase 10 verifies
  # "bob cannot approve", and an explicit deny is the difference between
  # a stated rule and an oversight -- it also survives someone attaching
  # a broader policy to him later.
  statement {
    sid    = "DenyApproval"
    effect = "Deny"

    actions = [
      "sagemaker:UpdateModelPackage",
      "sagemaker:DeleteModelPackage",
      "sagemaker:DeleteModelPackageGroup",
    ]

    resources = ["*"]
  }

  # Deployment is alice's. Bob registers a candidate; putting it in front
  # of traffic is a separate decision.
  statement {
    sid    = "DenyDeployment"
    effect = "Deny"

    actions = [
      "sagemaker:CreateEndpoint",
      "sagemaker:UpdateEndpoint",
      "sagemaker:DeleteEndpoint",
      "sagemaker:CreateEndpointConfig",
      "sagemaker:DeleteEndpointConfig",
    ]

    resources = ["*"]
  }

  # Studio's console enumerates resources through Search, not through the
  # List* calls above. Without it the Pipelines and Models panels error
  # out -- the same gap that blocked alice in phase 7.
  #
  # Search is account-wide and takes no resource scope. It does not widen
  # what bob can read: results are filtered by his other grants, and the
  # denies above still apply.
  statement {
    sid    = "StudioResourceSearch"
    effect = "Allow"

    actions = [
      "sagemaker:Search",
      "sagemaker:GetSearchSuggestions",
    ]

    resources = ["*"]
  }

  # Read his own job logs. Alice needed the same grant in phase 7 -- the
  # write side belongs to the container, the read side to the person
  # opening the Logs tab.
  statement {
    sid       = "CloudWatchLogsDiscovery"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogsRead"
    effect = "Allow"

    actions = [
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
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

  # Pull the training and processing containers.
  statement {
    sid    = "EcrPullJobImages"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
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

# The same MLflow grant alice has. Phase 10 has bob reading her runs and
# logging his own into the same experiment -- a shared tracking server
# that only one person can reach is not tracking a team's work.
#
# Not narrowed for bob: MLflow's own model registry is separate from the
# SageMaker one, and the boundary that matters -- who approves a
# deployable version -- is enforced on the SageMaker side by DenyApproval
# above.
resource "aws_iam_role_policy_attachment" "bob_mlflow_access" {
  role       = aws_iam_role.bob.name
  policy_arn = aws_iam_policy.mlflow_access.arn
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
