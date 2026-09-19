# ---------------------------------------------------------------------------
# ECR — private registry for the app image
# ---------------------------------------------------------------------------
# CI (GitHub Actions) would push here instead of GHCR when the deploy target
# is AWS: OIDC login -> docker push <acct>.dkr.ecr.<region>/mini-app:<sha>.
# EKS pulls it using the node group's role (ECR permissions are included by
# the EKS module).
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name = var.project

  # MUTABLE because the current CI pushes the 'latest' tag. The next
  # hardening step is IMMUTABLE + referencing the image by digest (sha256)
  # in the chart (already called out in the root README's "What I'd do with
  # more time" section).
  image_tag_mutability = "MUTABLE"

  # dev: lets 'terraform destroy' succeed even if images are still inside.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# Retention: don't let old images pile up forever.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
