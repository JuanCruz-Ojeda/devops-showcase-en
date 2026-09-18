# ---------------------------------------------------------------------------
# IRSA — IAM Roles for Service Accounts
# ---------------------------------------------------------------------------
# The correct pattern for granting AWS permissions to a pod: instead of
# attaching a policy to the NODE's role (every pod on that node would
# inherit it), an IAM role is bound to a Kubernetes ServiceAccount through
# the cluster's OIDC provider. The pod gets short-lived, least-privilege
# credentials.
#
# Flow: pod runs under a ServiceAccount -> the SA carries the annotation
# eks.amazonaws.com/role-arn -> EKS's webhook injects an OIDC token -> the
# pod calls sts:AssumeRoleWithWebIdentity.
# ---------------------------------------------------------------------------

# --- EBS CSI driver: permissions to create/attach EBS volumes -------------
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

# --- AWS Load Balancer Controller ----------------------------------------
# Translates Ingress / Service type=LoadBalancer into real ALBs/NLBs. Needs
# permissions to manage ELBv2 resources, target groups, security groups...
# (The controller itself is installed via Helm after apply; see the README.)
module "aws_lb_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${local.name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# --- Application role (example pattern) -----------------------------------
# The mini-app does NOT call any AWS API today, so this role carries no
# policies. It's here to demonstrate the pattern and as a ready hook for the
# day the app reads, say, the Redis auth token from Secrets Manager.
module "app_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${local.name}-app"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      # namespace:serviceaccount allowed to assume this role.
      namespace_service_accounts = ["mini-app:mini-app"]
    }
  }

  tags = local.tags
}

# Example (commented out): if the app read a secret from Secrets Manager, it
# would get ONLY GetSecretValue on THAT secret, nothing else.
#
# resource "aws_iam_role_policy" "app_read_redis_secret" {
#   name = "${local.name}-read-redis-secret"
#   role = module.app_irsa_role.iam_role_name
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect   = "Allow"
#       Action   = ["secretsmanager:GetSecretValue"]
#       Resource = "arn:aws:secretsmanager:${var.region}:*:secret:${local.name}/redis-auth-*"
#     }]
#   })
# }
