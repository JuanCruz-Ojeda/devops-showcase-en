# ---------------------------------------------------------------------------
# Versions and backend
# ---------------------------------------------------------------------------
# Pins Terraform and provider versions so CI and local runs produce the same
# result (same idea as ruff.toml pinning the linter's rules).
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # -------------------------------------------------------------------------
  # Remote backend: state in S3 + locking in DynamoDB.
  #
  # Left COMMENTED OUT on purpose so this can run locally (and in CI) with:
  #   terraform init -backend=false
  #   terraform validate
  # without needing an AWS account or any pre-existing infra.
  #
  # For real use: create the S3 bucket (versioned + encrypted) and the
  # DynamoDB table (partition key 'LockID') once, uncomment this block, then
  # run 'terraform init -migrate-state'. Details in infra/eks/README.md.
  # -------------------------------------------------------------------------
  # backend "s3" {
  #   bucket         = "REPLACE-ME-tfstate"
  #   key            = "eks/dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.region

  # Tags applied to every resource that supports tagging.
  default_tags {
    tags = local.tags
  }
}
