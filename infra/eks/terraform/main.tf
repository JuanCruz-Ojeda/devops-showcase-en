# ---------------------------------------------------------------------------
# Shared data sources and locals
# ---------------------------------------------------------------------------

# Available AZs in the region (drops the ones that need opt-in).
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Base name: mini-app-dev. Prefixes the cluster, VPC, ECR repo and roles.
  name = "${var.project}-${var.environment}"

  # First N AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Common tags. Applied via the provider's default_tags; repeated here for
  # modules that don't inherit it (VPC/EKS propagate it to sub-resources).
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repo        = "devops-showcase-en"
  }
}
