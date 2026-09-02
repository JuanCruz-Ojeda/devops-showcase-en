# Infrastructure — AWS deployment

This document describes how I would deploy the mini-app on AWS in a **minimal
but reasonable-for-production** way (not highly available or multi-region, but
resilient to the loss of a single container or a single AZ).

No IaC tool (Terraform/CDK) is used because the team has not adopted one yet;
instead there is an **AWS CLI runbook**. The final section explains the natural
path to move it to IaC.

---

## 1. Architecture

```
                    Internet
                       │
                       ▼
             ┌───────────────────┐
             │  ALB (public)     │   :80  (→ :443 + ACM in real prod)
             │  2 public subnets │   health check: GET /health
             └─────────┬─────────┘
                       │  (only the ALB SG can talk to the tasks)
                       ▼
        ┌──────────────────────────────┐
        │  ECS Service (Fargate)       │   desiredCount = 2
        │  2 tasks across 2 AZs        │   private subnets
        │  container: mini-app:5000    │   logs → CloudWatch Logs
        └───────────────┬──────────────┘
                        │  (only the tasks' SG can talk to Redis)
                        ▼
        ┌──────────────────────────────┐
        │  ElastiCache for Redis       │   private subnets
        │  1 primary (+1 optional rep.)│   no access from the Internet
        └──────────────────────────────┘

  ECR  ──(image pull)──►  ECS
  Secrets Manager / SSM  ──(config/secret injection)──►  task definition
```

### Components and why

| Component | Choice | Reason |
|---|---|---|
| Compute | **ECS Fargate** | No EC2 to manage (patching, AMIs, capacity). You pay per task. Horizontal scaling is trivial. For **one** small service, EKS is too much operation (control plane, upgrades, add-ons) and plain EC2 forces you to maintain the host. |
| Traffic entry | **Application Load Balancer** | Terminates TLS, runs active health checks, spreads across the tasks and the different AZs. It is the integration point with the ECS scheduler (automatic target registration/deregistration). |
| Image registry | **ECR** | Private, integrated with IAM and with the ECS pull. CI publishes there (tag by SHA). |
| State / cache | **ElastiCache for Redis** | Redis is shared state: it cannot live inside the app container if there are 2+ replicas. As a managed service, AWS handles patching, backups, failover and monitoring. |
| Non-sensitive config | Variables in the **task definition** (or **SSM Parameter Store**) | `REDIS_HOST`, `REDIS_PORT`: not secrets, but also not hardcoded in the image. |
| Secrets | **AWS Secrets Manager** | If Redis AUTH is enabled (or any credential appears), it is injected via the task definition's `secrets` block. Never in `environment` in plain text or in the image. |
| Logs | **CloudWatch Logs** (`awslogs` driver) | Centralized, configurable retention, basis for metrics and alarms. The app already writes to stdout/stderr unbuffered (`PYTHONUNBUFFERED`, gunicorn access logs to stdout). |
| Network | **VPC with 2 AZs**: ALB in public subnets, tasks and Redis in private subnets, **NAT Gateway** for egress (ECR pull, log shipping) | The tasks are not directly reachable from the Internet; only the ALB is. Cheaper alternative: tasks in public subnets with `assignPublicIp=ENABLED` and no NAT — you save the NAT cost but expose the task IP (mitigable with SGs, but less clean). |

### Network security — chained Security Groups

- **`alb-sg`**: inbound `80` (and `443`) from `0.0.0.0/0`.
- **`app-sg`** (ECS tasks): inbound `5000` **only from `alb-sg`**.
- **`redis-sg`** (ElastiCache): inbound `6379` **only from `app-sg`**.

Each layer only accepts traffic from the layer immediately in front of it.

### What happens if the container goes down

1. The **ALB health check** (`GET /health`) starts failing for that task.
2. The ALB marks it `unhealthy` and stops sending it traffic.
3. The **ECS scheduler** detects that the task is not `RUNNING`/healthy, removes
   it from the target group and **launches a replacement** to get back to
   `desiredCount = 2`.
4. Since there are **2 tasks across 2 AZs**, while one is being recreated the
   other keeps serving: no downtime.
5. On a bad deploy (image that does not start or does not pass the health
   check), the ECS **deployment circuit breaker** aborts the deployment and
   does an **automatic rollback** to the previous task definition revision.

The same behavior applies if a whole AZ goes down: ECS reschedules the tasks in
the healthy AZ.

### Observability

- **Logs**: a CloudWatch Logs group per service (`/ecs/mini-app`), retention e.g. 30 days.
- **Metrics**: ECS CPU/Memory, `HTTPCode_Target_5XX_Count`,
  `TargetResponseTime`, ALB `HealthyHostCount`/`UnHealthyHostCount`.
- **Alarms** (CloudWatch → SNS): sustained `UnHealthyHostCount > 0`,
  `5XX` above a threshold, sustained high CPU.
- Optional: **Container Insights** for aggregated cluster views.

### Scaling

`Application Auto Scaling` on the ECS Service, target-tracking on
`ALBRequestCountPerTarget` (or CPU). A minimum (2) and a maximum (e.g. 6) are
defined. The app is stateless and state lives in Redis, so scaling horizontally
is safe. Out of scope for the base, but the design already allows it without
changes.

---

## 2. Runbook (AWS CLI)

Placeholders in `<...>`. Assumes a VPC with 2 public and 2 private subnets
already existing (or created separately).

### 2.1. Variables

```bash
export AWS_REGION=us-east-1
export ACCOUNT_ID=<account-id>
export VPC_ID=<vpc-id>
export PUBLIC_SUBNETS=<subnet-pub-a>,<subnet-pub-b>
export PRIVATE_SUBNETS=<subnet-priv-a>,<subnet-priv-b>
export IMAGE_TAG=<git-sha>
export ECR_REPO=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mini-app
```

### 2.2. ECR + image push

```bash
aws ecr create-repository --repository-name mini-app \
  --image-scanning-configuration scanOnPush=true

aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t $ECR_REPO:$IMAGE_TAG ./app
docker push $ECR_REPO:$IMAGE_TAG
```

### 2.3. Security Groups

```bash
ALB_SG=$(aws ec2 create-security-group --group-name mini-app-alb-sg \
  --description "ALB mini-app" --vpc-id $VPC_ID --query GroupId --output text)
APP_SG=$(aws ec2 create-security-group --group-name mini-app-app-sg \
  --description "mini-app tasks" --vpc-id $VPC_ID --query GroupId --output text)
REDIS_SG=$(aws ec2 create-security-group --group-name mini-app-redis-sg \
  --description "mini-app ElastiCache" --vpc-id $VPC_ID --query GroupId --output text)

# ALB: 80 from the Internet
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# App: 5000 only from the ALB
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 5000 --source-group $ALB_SG

# Redis: 6379 only from the tasks
aws ec2 authorize-security-group-ingress --group-id $REDIS_SG \
  --protocol tcp --port 6379 --source-group $APP_SG
```

### 2.4. CloudWatch Logs

```bash
aws logs create-log-group --log-group-name /ecs/mini-app
aws logs put-retention-policy --log-group-name /ecs/mini-app --retention-in-days 30
```

### 2.5. ElastiCache for Redis

```bash
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name mini-app-redis-subnets \
  --cache-subnet-group-description "mini-app private subnets" \
  --subnet-ids $(echo $PRIVATE_SUBNETS | tr ',' ' ')

aws elasticache create-replication-group \
  --replication-group-id mini-app-redis \
  --replication-group-description "mini-app Redis" \
  --engine redis --cache-node-type cache.t4g.micro \
  --num-node-groups 1 --replicas-per-node-group 1 \
  --cache-subnet-group-name mini-app-redis-subnets \
  --security-group-ids $REDIS_SG \
  --transit-encryption-enabled --at-rest-encryption-enabled

# Note the primary endpoint:
aws elasticache describe-replication-groups --replication-group-id mini-app-redis \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' --output text
export REDIS_HOST=<noted-endpoint>
```

### 2.6. IAM roles

```bash
# Execution role: ECS uses it to pull from ECR, write logs and read secrets.
aws iam create-role --role-name mini-app-exec \
  --assume-role-policy-document file://trust-ecs-tasks.json
aws iam attach-role-policy --role-name mini-app-exec \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
# (+ an inline policy with secretsmanager:GetSecretValue on the secret ARN, if used)

# Task role: the app's runtime permissions. The app does not call any AWS API,
# so it gets an empty role (or none is assigned at all).
aws iam create-role --role-name mini-app-task \
  --assume-role-policy-document file://trust-ecs-tasks.json
```

`trust-ecs-tasks.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

### 2.7. Task definition

`taskdef.json`:

```json
{
  "family": "mini-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::<account-id>:role/mini-app-exec",
  "taskRoleArn": "arn:aws:iam::<account-id>:role/mini-app-task",
  "containerDefinitions": [{
    "name": "mini-app",
    "image": "<account-id>.dkr.ecr.<region>.amazonaws.com/mini-app:<git-sha>",
    "essential": true,
    "portMappings": [{ "containerPort": 5000, "protocol": "tcp" }],
    "environment": [
      { "name": "REDIS_HOST", "value": "<elasticache-endpoint>" },
      { "name": "REDIS_PORT", "value": "6379" }
    ],
    "secrets": [
      { "name": "REDIS_AUTH_TOKEN", "valueFrom": "arn:aws:secretsmanager:<region>:<account-id>:secret:mini-app/redis-auth" }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/mini-app",
        "awslogs-region": "<region>",
        "awslogs-stream-prefix": "app"
      }
    }
  }]
}
```

> Note: the `secrets` block only applies if Redis AUTH is enabled. In the
> current app `REDIS_AUTH_TOKEN` is not used; it is left as an example of the
> pattern.

```bash
aws ecs register-task-definition --cli-input-json file://taskdef.json
```

### 2.8. ECS cluster

```bash
aws ecs create-cluster --cluster-name mini-app \
  --settings name=containerInsights,value=enabled
```

### 2.9. ALB + target group + listener

```bash
ALB_ARN=$(aws elbv2 create-load-balancer --name mini-app-alb \
  --type application --scheme internet-facing \
  --subnets $(echo $PUBLIC_SUBNETS | tr ',' ' ') \
  --security-groups $ALB_SG --query 'LoadBalancers[0].LoadBalancerArn' --output text)

TG_ARN=$(aws elbv2 create-target-group --name mini-app-tg \
  --protocol HTTP --port 5000 --vpc-id $VPC_ID --target-type ip \
  --health-check-path /health --health-check-interval-seconds 15 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 create-listener --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
# In real prod: a 443 listener with --certificates (ACM) and an 80→443 redirect.
```

### 2.10. ECS Service

```bash
aws ecs create-service \
  --cluster mini-app --service-name mini-app \
  --task-definition mini-app \
  --desired-count 2 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNETS],securityGroups=[$APP_SG],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=mini-app,containerPort=5000" \
  --health-check-grace-period-seconds 20 \
  --deployment-configuration "deploymentCircuitBreaker={enable=true,rollback=true},minimumHealthyPercent=100,maximumPercent=200"
```

### 2.11. Verification

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)

curl -fsS http://$ALB_DNS/                 # {"service":"mini-app","status":"ok"}
curl -fsS http://$ALB_DNS/health           # {"status":"healthy"}
curl -fsS http://$ALB_DNS/cache-test       # hits=N
curl -fsS http://$ALB_DNS/cache-test       # hits=N+1  → Redis OK
```

### 2.12. Update to a new version

```bash
docker build -t $ECR_REPO:<new-sha> ./app && docker push $ECR_REPO:<new-sha>
# edit taskdef.json with the new tag
aws ecs register-task-definition --cli-input-json file://taskdef.json
aws ecs update-service --cluster mini-app --service mini-app \
  --task-definition mini-app --force-new-deployment
```

ECS does a **rolling update** (brings up the new ones, waits for them to be
healthy in the ALB, only then takes down the old ones). If the new ones do not
pass the health check, the circuit breaker rolls back by itself.

---

## 3. Path to IaC (next step)

The runbook is the basis for understanding which resources are needed and how
they relate. The next step would be:

1. Translate all of this to **Terraform** (or CDK), with remote state in S3 +
   locking in DynamoDB.
2. Chain the deploy into CI: after the push to ECR, a job runs
   `register-task-definition` + `update-service` (or `terraform apply` of the
   task-definition module), authenticating via **OIDC** (no long-lived keys).
3. Parametrize per environment (`dev` / `prod`) with workspaces or folders.
