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

  # MLflow artifact store. Not in s3_prefixes: the app creates it, and an
  # empty marker object confuses the artifact listing.
  #
  # mlflow-app/, not mlflow/. The retired tracking server owned mlflow/
  # and its experiment ids start at 1 again here -- pointing the app at
  # the same prefix would interleave two unrelated id spaces.
  mlflow_prefix = "mlflow-app/"

  # Phase 9. Bob writes here and nowhere else; alice keeps the root
  # prefixes above, which is what he is denied. Not in s3_prefixes: the
  # bucket does not need an empty marker for a prefix bob creates on his
  # first put.
  bob_prefix = "users/bob/"

  default_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.tags
  )
}
