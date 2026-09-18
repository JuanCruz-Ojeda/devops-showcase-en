# ---------------------------------------------------------------------------
# Input variables
# ---------------------------------------------------------------------------
# Everything that changes between environments (dev / prod) lives here.
# Defaults point at a cheap 'dev' environment; prod overrides via its own
# .tfvars file.
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project name. Prefixes every resource."
  type        = string
  default     = "mini-app"
}

variable "environment" {
  description = "Logical environment (dev / stg / prod). Part of the cluster name."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region where the cluster is created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR. A /16 leaves plenty of room for the AWS CNI (one VPC IP per pod)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to use. 3 = tolerates losing one AZ without losing quorum."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API server endpoint. Defaults to open
    so 'kubectl' works from anywhere in dev. In prod: lock this down to the
    VPN / bastion egress IP, or go endpoint-private-only.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group. A list allows capacity fallback."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count (autoscaling floor)."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count (autoscaling ceiling)."
  type        = number
  default     = 4
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = a single NAT Gateway for the whole VPC (cheaper, single point of
            failure for egress).
    false = one NAT Gateway per AZ (recommended in prod: egress survives
            losing an AZ).
  EOT
  type        = bool
  default     = true
}
