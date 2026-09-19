# ---------------------------------------------------------------------------
# EKS — managed control plane + managed node group
# ---------------------------------------------------------------------------
# AWS runs the control plane (API server, etcd, scheduler): replicated
# across 3 AZs, with an SLA, patched and upgraded by AWS. We only manage the
# worker nodes.
#
# "Managed" node group: AWS owns the Auto Scaling Group, drains nodes during
# upgrades, and replaces nodes that fail health checks. Alternatives:
#   - Fargate profiles: no nodes at all, pay per pod. Good for bursty/sporadic
#     workloads; no DaemonSets and some add-ons don't work.
#   - Self-managed nodes: full control of the AMI/userdata, but you own the
#     maintenance.
# For a small, steady service, a managed node group is the sweet spot.
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # API server endpoint: public (for kubectl/CI from outside) + private (so
  # nodes talk to the control plane over the internal network).
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # OIDC provider for IRSA: without this you can't grant AWS permissions
  # to an individual pod.
  enable_irsa = true

  # Encrypt Kubernetes Secrets at rest in etcd with a dedicated KMS key
  # (created by the module). Without this, Secrets sit in etcd as base64
  # only, not actually encrypted.
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # Control plane logs shipped to CloudWatch (auditing, troubleshooting).
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # EKS-managed add-ons (EKS itself resolves versions compatible with
  # cluster_version).
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      # Installed BEFORE the nodes come up, so the first pod already has
      # networking.
      before_compute = true
    }
    aws-ebs-csi-driver = {
      # The driver needs permissions to create/attach EBS volumes.
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_group_defaults = {
    instance_types = var.node_instance_types
    capacity_type  = "ON_DEMAND"
  }

  eks_managed_node_groups = {
    general = {
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      labels = {
        role = "general"
      }

      # Nodes land in private subnets (inherited from the module's subnet_ids).
      # update_config: at most 1 node unavailable at a time during an upgrade.
      update_config = {
        max_unavailable = 1
      }

      tags = local.tags
    }
  }

  # Whoever runs 'terraform apply' becomes cluster admin (via EKS access
  # entries, the replacement for the old aws-auth ConfigMap).
  enable_cluster_creator_admin_permissions = true

  tags = local.tags
}
