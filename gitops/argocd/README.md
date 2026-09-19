# GitOps with ArgoCD

This is not a description of how ArgoCD *would* work — it was installed and
run against the existing [`helm/mini-app`](../../helm/mini-app) chart on a
local `minikube` cluster, and the sync + self-heal behavior below is copied
from that actual run, not from documentation. See
[`infra/eks/README.md`](../../infra/eks/README.md) for how the same manifests
would target a real EKS cluster instead.

## Why GitOps instead of `helm upgrade` from CI

In a push-based pipeline, CI has credentials to the cluster and runs
`kubectl apply` / `helm upgrade` directly. That means every CI runner needs
cluster-admin-ish access, and if someone changes something by hand on the
cluster, nothing notices or corrects it.

In a pull-based (GitOps) model, ArgoCD runs **inside** the cluster, has its
own read access to the Git repo, and continuously reconciles: it diffs the
cluster's actual state against what Git says it should be, and — with
`selfHeal` on — corrects any drift automatically. No pipeline needs
cluster credentials at all; the only thing that needs to reach the cluster
is ArgoCD, which is already inside it. Git becomes the audit log: every
change to the cluster is a commit, not a `kubectl` command lost in someone's
shell history.

## App of Apps

```
gitops/argocd/
├── root-app.yaml       # applied by hand, once
└── apps/
    └── mini-app.yaml   # ArgoCD discovers and creates this itself
```

[`root-app.yaml`](root-app.yaml) is the **only** manifest a human ever
applies directly:

```bash
kubectl apply -f gitops/argocd/root-app.yaml
```

It's an ArgoCD `Application` that watches `gitops/argocd/apps/` and
`syncPolicy.automated`s whatever it finds there. Adding a second service
later means adding one YAML file to `apps/`, not touching the cluster.

[`apps/mini-app.yaml`](apps/mini-app.yaml) is the child `Application` that
this created automatically. It points straight at the existing
[`helm/mini-app`](../../helm/mini-app) chart — no separate copy of the chart
for the GitOps path — with:

```yaml
syncPolicy:
  automated:
    prune: true      # delete cluster resources removed from Git
    selfHeal: true    # revert changes made directly on the cluster
```

## What was actually run

```bash
# 1. Local cluster
minikube start --driver=docker --cpus=4 --memory=4096

# 2. ArgoCD (server-side apply avoids a known apply-annotation-size issue
#    with the ApplicationSet CRD on client-side apply)
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server

# 3. The image the chart deploys (same one CI builds)
docker build -t mini-app:dev ./app
minikube image load mini-app:dev

# 4. Bootstrap GitOps
kubectl apply -f gitops/argocd/root-app.yaml
```

Result:

```
$ kubectl -n argocd get applications
NAME       SYNC STATUS   HEALTH STATUS
mini-app   Synced        Healthy
root-app   Synced        Healthy

$ kubectl -n mini-app get pods
NAME                       READY   STATUS    RESTARTS   AGE
mini-app-96b5bc694-6np72   1/1     Running   0          33s
mini-app-redis-0           1/1     Running   0          33s
```

And the app itself, reached through the ArgoCD-deployed Service:

```
$ curl http://localhost:5000/
{"service":"mini-app","status":"ok"}
$ curl http://localhost:5000/cache-test
{"hits":"1","redis_host":"mini-app-redis"}
$ curl http://localhost:5000/cache-test
{"hits":"2","redis_host":"mini-app-redis"}
```

## Self-heal, live

`values.yaml` says `app.replicaCount: 1`. Scaling the Deployment by hand,
straight on the cluster — the thing a GitOps setup exists to catch:

```
$ kubectl -n mini-app get deploy mini-app -o jsonpath='{.spec.replicas}'
1

$ kubectl -n mini-app scale deploy/mini-app --replicas=5
deployment.apps/mini-app scaled

$ kubectl -n mini-app get pods
NAME                       READY   STATUS        RESTARTS   AGE
mini-app-96b5bc694-6np72   1/1     Running       0          69s
mini-app-96b5bc694-fv8qv   0/1     Terminating   0          2s
mini-app-96b5bc694-htxbn   0/1     Terminating   0          2s
mini-app-96b5bc694-mzng8   0/1     Terminating   0          2s
mini-app-96b5bc694-vvrj8   0/1     Terminating   0          2s
```

ArgoCD had already reverted it **within about 5 seconds** of the manual
scale — by the time the first status check ran, the 4 extra pods were
already `Terminating` and the Deployment was back to `replicas: 1`. No one
ran `kubectl scale` back down; ArgoCD's reconciliation loop did it on its
own, because the cluster's state didn't match what Git said it should be.

This is the property push-based deploys don't have: the cluster can't drift
away from Git and stay drifted.

## On real EKS

The mechanics don't change — only two things would:

1. `apps/mini-app.yaml`'s `helm.valueFiles` would point at an EKS-specific
   values file: image pulled from ECR instead of the locally-loaded
   `mini-app:dev`, and an `Ingress` annotated for the AWS Load Balancer
   Controller instead of a bare `ClusterIP` Service.
2. ArgoCD itself would run once, in-cluster, watching this same repo —
   exactly like it does on minikube here.

Everything upstream of that (CI building the image, tagging it, this repo
being the source of truth for what should be running) is identical.
