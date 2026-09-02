# Optional Track A — Kubernetes / Helm

First-party chart (`helm/mini-app/`) to deploy the app + Redis on a local
cluster (minikube). It does not use third-party charts.

## What it includes

| Resource | Kind | Why |
|---|---|---|
| `mini-app` | Deployment | The app is stateless → interchangeable replicas. Parametrizable `replicaCount`. |
| `mini-app` | Service (ClusterIP) | Entry point to the app; balances across replicas. |
| `mini-app-redis` | StatefulSet (1 replica) | Redis is stateful → stable identity + its own PVC (`volumeClaimTemplates`). |
| `mini-app-redis` | Headless Service | Direct DNS to the Redis pod (no balancing). |
| `mini-app` | ConfigMap | `REDIS_HOST`, `REDIS_PORT` (non-sensitive). |
| `mini-app-redis` | Secret | Redis password. Generated randomly and preserved across `helm upgrade`. |

Config and secrets are **never** hardcoded in the manifests: the app receives
them via `envFrom` (ConfigMap) and `secretKeyRef` (Secret).

## Prerequisites

- `helm` v3, `kubectl`, `minikube`, `docker`
- Run from the repo root.

## Testing path (from 0 to 0)

All commands from the repo root.

### 1. Cluster and image

```bash
minikube start --driver=docker --cpus=4 --memory=4096
kubectl get nodes                                   # minikube Ready

docker build -t mini-app:dev ./app                  # local build (the GHCR one is private)
minikube image load mini-app:dev
minikube image ls | grep mini-app                   # docker.io/library/mini-app:dev
```

### 2. Validate the chart (no cluster)

```bash
helm lint helm/mini-app
helm template mini-app helm/mini-app | head -60     # review the render
```

### 3. Install and wait

```bash
helm upgrade --install mini-app ./helm/mini-app
kubectl rollout status deployment/mini-app --timeout=120s
kubectl rollout status statefulset/mini-app-redis --timeout=120s
kubectl get pod,svc,statefulset,pvc,cm,secret -l app.kubernetes.io/instance=mini-app
```

Expected: 2 pods `Running`, 2 Services (one `None` = headless), StatefulSet `1/1`,
PVC `Bound`, 1 ConfigMap, 1 Secret.

### 4. Test the app

```bash
helm test mini-app --logs                           # Phase: Succeeded + curl output

kubectl port-forward svc/mini-app 8080:5000 >/dev/null &
./scripts/smoke-test.sh                             # / /health /cache-test + counter goes up
kill %1
```

### 5. Scaling demo (the track's answer)

```bash
helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=3
kubectl rollout status deployment/mini-app --timeout=120s
kubectl get pod -l app.kubernetes.io/component=app  # 3 pods

# Terminal A: traffic from inside the cluster (kube-proxy balances)
kubectl run tester --rm -it --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 30); do curl -s http://mini-app:5000/cache-test; echo; done'
#   -> hits grows monotonically: consistent state

# Terminal B: which pod served each request
kubectl logs -l app.kubernetes.io/component=app --prefix --tail=60 | grep cache-test
#   -> all 3 pod names show up serving

helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=1   # back to 1 replica
```

> `--set app.replicaCount=1` must be passed explicitly: this Helm preserves the
> values from the previous release. Alternative: `--reset-values`, which restores
> the chart's default values.

### 6. Persistence demo

```bash
PW=$(kubectl get secret mini-app-redis -o jsonpath='{.data.redis-password}' | base64 -d)
kubectl exec mini-app-redis-0 -- sh -c "redis-cli -a '$PW' --no-auth-warning get hits"   # N
kubectl delete pod mini-app-redis-0
kubectl rollout status statefulset/mini-app-redis --timeout=120s
kubectl exec mini-app-redis-0 -- sh -c "redis-cli -a '$PW' --no-auth-warning get hits"   # still N
```

### 7. Rollback demo (optional)

```bash
helm history mini-app                               # list of revisions
helm rollback mini-app 1                            # back to revision 1
```

### 8. Tear everything down (back to the initial state)

```bash
helm uninstall mini-app
kubectl delete pod,pvc -l app.kubernetes.io/instance=mini-app
kubectl get all,pvc,cm,secret -l app.kubernetes.io/instance=mini-app   # no resources
helm list                                                             # empty

# full cluster reset (optional):
minikube delete
```

## Parametrizable values (`values.yaml`)

| Key | Default | For what |
|---|---|---|
| `app.replicaCount` | `1` | App replicas (horizontal scaling). |
| `image.repository` / `image.tag` | `mini-app` / `dev` | Image to deploy. For GHCR: `ghcr.io/juancruz-ojeda/entrega-prueba-tecnica` + `imagePullSecrets`. |
| `image.pullPolicy` | `IfNotPresent` | Uses the already-loaded image, does not pull. |
| `redis.auth.password` | `""` (auto-generated) | Redis password. With a value: fixed (handy for `--set` in demos). |
| `redis.persistence.size` | `128Mi` | Size of the Redis PVC. |
| `redis.persistence.storageClass` | `""` (cluster default) | PVC StorageClass. |
| `app.resources` / `redis.resources` | small requests/limits | Resources for each container. |

Example: `helm upgrade --install mini-app ./helm/mini-app --set app.replicaCount=3`

## The defense question: what happens if I scale `app` to 2+ replicas?

**It is safe.** The app is stateless and all state lives in Redis. The N replicas
use the same Service (`mini-app-redis`), so the `hits` counter is consistent
because Redis is the single source of truth. Verified: with 3 replicas, 10
consecutive requests to `/cache-test` through the Service return the counter
growing monotonically.

**The limit is Redis, not the app:**

- Redis is **a single instance** → single point of failure. If the pod goes
  down, the app replicas lose the backend until the StatefulSet recreates it
  (~10-15s).
- The **PVC** gives durability against a pod restart (verified: kill
  `mini-app-redis-0` and the counter survives). It does **not** protect against
  node loss or PVC deletion.
- Scaling the **Redis StatefulSet** to 2+ replicas would be **wrong** with this
  chart: each pod would have its own dataset, with no replication → the counter
  would become inconsistent depending on which pod serves.
- Real Redis HA = StatefulSet + Redis Sentinel/Cluster, or a managed service. In
  production it is exactly what [`../infra/README.md`](../infra/README.md)
  proposes: **ElastiCache for Redis** with a replica.

## Cleanup

```bash
helm uninstall mini-app
# helm uninstall does NOT delete: (a) the StatefulSet's PVC (data protection)
# or (b) the helm test pod (before-hook-creation policy, so you can read its
# logs). Clean them up by hand:
kubectl delete pod,pvc -l app.kubernetes.io/instance=mini-app
```

## Notes

- `docker-compose.yml` runs Redis **without** a password on purpose (simple
  local dev). The `REDIS_PASSWORD` support in `app/app.py` is optional and
  backward-compatible: without the variable, the app connects without auth.
- `helm template ./helm/mini-app` renders the manifests without a cluster
  (useful for review). In that mode the Secret password looks different on each
  render because `lookup` has no cluster to query; in `helm install/upgrade` the
  behavior is correct (generated once and preserved).
