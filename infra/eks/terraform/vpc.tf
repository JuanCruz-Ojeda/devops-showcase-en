# ---------------------------------------------------------------------------
# Networking — VPC with public and private subnets across N AZs
# ---------------------------------------------------------------------------
# - Nodes and pods live in PRIVATE subnets (not reachable from the internet).
# - Public load balancers (the ALB/NLB the AWS Load Balancer Controller
#   creates) go in the PUBLIC subnets.
# - Node egress to the internet (pulling from ECR, shipping logs, add-ons)
#   goes through a NAT Gateway.
#
# The subnet tags below are REQUIRED so EKS and the AWS Load Balancer
# Controller know where to place each kind of load balancer:
#   kubernetes.io/role/elb           -> subnets for internet-facing LBs
#   kubernetes.io/role/internal-elb  -> subnets for internal LBs
# ---------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /16 split into /20s: ~4096 IPs per subnet. The AWS CNI hands out one VPC
  # IP per pod, so it pays to leave headroom.
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}
