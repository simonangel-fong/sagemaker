# space.tf
#
# Phase 4: alice's private JupyterLab space.
#
# Terraform declares the space, registers the repo in the clone menu, and
# attaches a lifecycle config that clones it on app start. Starting the
# app stays manual -- that is the part that bills.

# ##############################
# Lifecycle config
# ##############################
# Studio spaces have no default_code_repository equivalent to the one on
# notebook instances, so auto-clone has to go through an LCC script.
resource "aws_sagemaker_studio_lifecycle_config" "clone_repo" {
  studio_lifecycle_config_name     = "${local.prefix_name}-clone-repo"
  studio_lifecycle_config_app_type = "JupyterLab"

  studio_lifecycle_config_content = base64encode(
    templatefile("${path.module}/scripts/clone-repo.sh", {
      repo_url = var.git_repository_url
    })
  )
}

# ##############################
# Space
# ##############################
resource "aws_sagemaker_space" "alice" {
  domain_id  = aws_sagemaker_domain.this.id
  space_name = "alice-jupyterlab"

  space_sharing_settings {
    sharing_type = "Private"
  }

  ownership_settings {
    owner_user_profile_name = aws_sagemaker_user_profile.alice.user_profile_name
  }

  space_settings {
    app_type = "JupyterLab"

    jupyter_lab_app_settings {
      default_resource_spec {
        instance_type        = var.space_instance_type
        lifecycle_config_arn = aws_sagemaker_studio_lifecycle_config.clone_repo.arn
      }

      # The LCC does the cloning; this just lists the repo in the git menu.
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
