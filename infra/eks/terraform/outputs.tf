# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN (used to attach more IRSA roles)."
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_url" {
  description = "ECR repo URL that CI publishes to."
  value       = aws_ecr_repository.app.repository_url
}

output "aws_lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.aws_lb_controller_irsa_role.iam_role_arn
}

output "app_role_arn" {
  description = "IRSA role ARN for the app's ServiceAccount annotation."
  value       = module.app_irsa_role.iam_role_arn
}

output "configure_kubectl" {
  description = "Command to point kubeconfig at this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
