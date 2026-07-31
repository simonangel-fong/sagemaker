# locals.tf

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  prefix_name = "${var.project}-${var.env}"
  bucket_name = "${local.prefix_name}-data-${random_string.suffix.result}"

  default_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.tags
  )
}
