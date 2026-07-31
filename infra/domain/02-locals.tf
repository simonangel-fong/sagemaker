# locals.tf

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  prefix_name = "${var.project}-${var.env}"
  bucket_name = "${local.prefix_name}-data-${random_string.suffix.result}"

  # raw/ is the upload target, the other two are written by later phases.
  s3_prefixes = ["raw/", "featured/", "model/"]

  # MLflow artifact store. Not in s3_prefixes: the tracking server
  # creates it, and an empty marker object confuses the artifact listing.
  mlflow_prefix = "mlflow/"

  default_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.tags
  )
}
