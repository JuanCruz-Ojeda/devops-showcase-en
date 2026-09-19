# EKS + Terraform + ArgoCD — GitOps track

This is a second infrastructure track alongside [`infra/README.md`](../README.md)
(ECS Fargate + AWS CLI runbook). That document argues ECS is the *right* call
for **this** small, single service — and it still is. This track exists for a
different reason: to show the same workload landing on the platform stack most
Cloud Engineer / DevOps roles actually run day to day — **EKS, Terraform,
GitOps with ArgoCD** — and to be explicit about what changes when you move
from "one small service" to "a platform for many services."

Both are legitimate answers to different questions. Picking ECS for a
single-service assignment and reaching for EKS when the real job is "run a
platform team's workloads" is the same engineering judgment applied twice.

## What's here vs. what's proven

| | Status |
|---|---|
| Terraform (`terraform/`) | **Validated, not applied.** `terraform fmt`, `init -backend=false` and `validate` all pass (see the commit history). No `terraform apply` against a real AWS account — this is a portfolio track, not a funded environment. Same honesty level as the ECS runbook: describe exactly what was and wasn't run. |
| ArgoCD + the app (`../gitops/argocd/`) | **Actually running.** ArgoCD installed on a local `minikube` cluster, the existing `helm/mini-app` chart deployed through it, sync and **self-heal verified live** (a manual `kubectl scale` was reverted by ArgoCD in seconds). Details and the actual command output in [`gitops/argocd/README.md`](../gitops/argocd/README.md). |

Running a real EKS cluster costs money continuously (control plane + NAT +
nodes, roughly $150-250/month even idle) for a portfolio piece with no
production traffic behind it, so the IaC is proven the way IaC should be
provable before it ever touches an account: it type-checks, its resource
graph resolves, and the modules it depends on exist at the pinned versions.
The parts that don't need a cloud bill — the GitOps mechanics — are run for
real.

## Architecture

```
                              Internet
                                 │
                    ┌────────────┴────────────┐
                    │   AWS Load Balancer      │  created by the AWS LB Controller
                    │   Controller → ALB       │  from a Kubernetes Ingress
                    └────────────┬────────────┘
                                 │  public subnets (2-3 AZs)
   ┌─────────────────────────────┼─────────────────────────────┐
   │  VPC                        │                              │
   │                    private subnets (2-3 AZs)               │
   │  ┌──────────────────────────┴───────────────────────────┐ │
   │  │  EKS cluster                                          │ │
   │  │  ┌────────────────────┐   control plane: managed by   │ │
   │  │  │ Managed node group │   AWS, multi-AZ, own SLA       │ │
   │  │  │  t3.medium x 2-4   │                                │ │
   │  │  │  ┌──────────────┐  │   pods get IRSA-scoped AWS    │ │
   │  │  │  │ mini-app pod │──┼──►permissions via the OIDC    │ │
   │  │  │  └──────────────┘  │   provider, not the node role │ │
   │  │  └────────────────────┘                                │ │
   │  └────────────────────────────────────────────────────────┘ │
   │                                                              │
   │  NAT Gateway (egress: pull from ECR, ship logs, addons)      │
   └──────────────────────────────────────────────────────────────┘

   ECR (private) ──image pull (node role)──► EKS
   ArgoCD (in-cluster) ──watches──► this Git repo ──renders──► helm/mini-app
```

ArgoCD itself would run **inside** the cluster (as it does on minikube in the
local demo) rather than as an external service — that's the point of GitOps:
the thing reconciling the cluster lives in the cluster it manages.

## Decisions and why (the 3 bullets this role actually asks about)

### VPC integration

- 3 AZs, public subnets (load balancers) + private subnets (nodes and pods),
  see [`vpc.tf`](terraform/vpc.tf).
- The AWS VPC CNI hands out **one VPC IP per pod** — not an overlay network.
  That's why the VPC is sized `/16` and split into `/20`s: with a few dozen
  pods per node across several nodes, IP exhaustion is a real failure mode on
  a tight CIDR, not a theoretical one.
- Subnets carry the `kubernetes.io/role/elb` / `internal-elb` tags. Without
  these, the AWS Load Balancer Controller (and EKS itself, for the classic
  in-tree provisioner) has no way to know which subnets are eligible for
  which kind of load balancer — it's not optional metadata, it's how
  auto-discovery works.
- `single_nat_gateway` is a variable, defaulted to `true` (one NAT, cheaper,
  single point of failure for egress) with a one-line flip to `false` (one
  NAT per AZ) for a real prod environment.

### IAM / IRSA

- `enable_irsa = true` on the EKS module creates an OIDC provider for the
  cluster. Without it, the only way to give a pod AWS permissions is to put
  them on the **node's** IAM role — which every pod scheduled on that node
  then inherits, regardless of whether it needs them.
- IRSA instead binds an IAM role to a Kubernetes ServiceAccount
  (`eks.amazonaws.com/role-arn` annotation). A pod using that ServiceAccount
  gets short-lived credentials for *that role only*, via
  `sts:AssumeRoleWithWebIdentity`. See [`irsa.tf`](terraform/irsa.tf) for
  three concrete roles:
  - **EBS CSI driver** — needs `ec2:CreateVolume`/`AttachVolume`/etc. to back
    PersistentVolumeClaims (Redis's StatefulSet would need this on real EKS).
  - **AWS Load Balancer Controller** — needs ELBv2/EC2 permissions to turn a
    Kubernetes `Ingress` into an ALB.
  - **The app itself** — created with **no policies attached**, because the
    app doesn't call any AWS API today. It exists to show the pattern and as
    a ready hook: the commented-out example attaches `secretsmanager:GetSecretValue`
    scoped to one secret ARN, for the day the app reads the Redis auth token
    from Secrets Manager instead of a Kubernetes Secret.
- Whoever runs `apply` gets cluster-admin via an EKS **access entry**
  (`enable_cluster_creator_admin_permissions`), the current replacement for
  hand-editing the old `aws-auth` ConfigMap.

### IAM / cluster access more broadly

- `cluster_endpoint_public_access_cidrs` defaults wide open (`0.0.0.0/0`) so
  `kubectl` works from anywhere in dev; the variable exists specifically so
  prod can lock it to a VPN/bastion egress IP or drop public access
  entirely (`cluster_endpoint_public_access = false`).
- Kubernetes Secrets are encrypted at rest in etcd with a dedicated KMS key
  (`cluster_encryption_config`). Without this, a Secret sitting in etcd is
  base64, not encryption.
- Control-plane audit logs (`cluster_enabled_log_types`) ship to CloudWatch —
  this is what you'd actually query if someone asks "who deleted that
  Deployment."

## High availability

- **Control plane**: run and replicated across AZs by AWS, with its own SLA.
  Nothing to configure here beyond picking a supported Kubernetes version.
- **Nodes**: the managed node group spans the private subnets across all
  configured AZs (2-4 nodes, autoscaling between `node_min_size` and
  `node_max_size`). Losing one AZ leaves nodes in the others.
- **Node upgrades**: `update_config.max_unavailable = 1` — the managed node
  group drains and replaces nodes one at a time, the same rolling-update
  guarantee ECS's deployment gives at the task level.
- **The app**: still just a `Deployment` with `replicaCount` (see
  `helm/mini-app/values.yaml`) spread by the scheduler's default anti-affinity
  across nodes/AZs. A `PodDisruptionBudget` and explicit
  `topologySpreadConstraints` are the natural next step, not yet added here.

## EKS vs. ECS, side by side

| | ECS Fargate (`infra/README.md`) | EKS (this track) |
|---|---|---|
| Right for | One or a handful of services, small team, no in-house Kubernetes operational experience needed | Many services/teams sharing a platform, or the org already standardized on Kubernetes (as this role requires) |
| Control plane ops | None — AWS-managed, no separate cost | AWS-managed, but a **flat hourly cost** exists (control plane) regardless of workload size |
| Where permissions live | Task role (1:1 with the task definition) | IRSA (1:1 with a ServiceAccount — finer-grained across many pods per node) |
| Deploy mechanism | `aws ecs update-service --force-new-deployment`, or CI calling that | GitOps: CI publishes an image, a Git commit updates the tag, ArgoCD reconciles — see `gitops/argocd/README.md` |
| Portability | AWS-specific | The chart and manifests are the same ones that already run on minikube/kind — same YAML on a laptop or on a real cluster |

## Terraform layout

```
infra/eks/terraform/
├── versions.tf   # Terraform/provider pins, commented-out S3+DynamoDB backend
├── variables.tf  # everything that differs between dev/prod
├── main.tf       # data sources + locals (name, AZs, tags)
├── vpc.tf        # terraform-aws-modules/vpc
├── eks.tf        # terraform-aws-modules/eks (control plane + managed node group)
├── irsa.tf       # 3 IRSA roles via terraform-aws-modules/iam//modules/iam-role-for-service-accounts-eks
├── ecr.tf        # private image repo + lifecycle policy
├── outputs.tf    # cluster name/endpoint, role ARNs, the update-kubeconfig command
└── terraform.tfvars.example
```

## How this would actually get applied

```bash
cd infra/eks/terraform
cp terraform.tfvars.example terraform.tfvars   # adjust region/sizing

# One-time: create the S3 bucket + DynamoDB table, then uncomment the
# backend block in versions.tf.
terraform init -migrate-state

terraform plan -out=tfplan
terraform apply tfplan

# Point kubectl at it (also printed as a Terraform output):
aws eks update-kubeconfig --region <region> --name mini-app-dev

# Install the two controllers Terraform only created IAM roles for:
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=mini-app-dev \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<aws_lb_controller_role_arn output>

# Then bootstrap GitOps the same way as the local demo:
kubectl apply -f gitops/argocd/root-app.yaml
```

From there, `gitops/argocd/apps/mini-app.yaml` would point its `valueFiles`
at an EKS-specific values file (image from ECR instead of `mini-app:dev`, an
`Ingress` annotated for the AWS Load Balancer Controller) instead of the
minikube demo's plain `values.yaml`.

## Cost, honestly

Ballpark for this exact config, `us-east-1`, left running:

| Item | Approx. monthly |
|---|---|
| EKS control plane | ~$73 (flat, $0.10/hr) |
| 2x `t3.medium` on-demand | ~$60 |
| 1x NAT Gateway | ~$33 + data processing |
| **Total (idle)** | **~$165-200/month** |

That's the real reason this isn't `terraform apply`-ed for a portfolio repo
with no traffic: EKS's fixed costs don't scale down to zero the way ECS
Fargate's per-task billing does. A funded environment would also add spot
node groups, autoscaling to zero outside business hours (via cron-scaled
node groups or Karpenter consolidation), and Savings Plans — out of scope
for what's shown here.

## What I'd do with more time

- Karpenter instead of a static managed node group, for faster and cheaper
  autoscaling.
- `PodDisruptionBudget` + `topologySpreadConstraints` on the app.
- ArgoCD Image Updater (or a CI job that bumps the tag) so a merge to `main`
  flows into the cluster without a human editing `values.yaml`.
- OPA/Kyverno policies enforced cluster-wide instead of per-chart
  `securityContext` review.
- Cross-account setup: a `tooling` account running ArgoCD, targeting
  separate `dev`/`prod` EKS clusters via ApplicationSets.
