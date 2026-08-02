# locals.tf

locals {
  # ##############################
  # Metadata
  # ##############################
  prefix_name = "${var.project}-${var.env}"
  default_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.tags
  )
}
