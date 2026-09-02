# Flask + Redis mini-service — solution

[![CI](https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica/actions/workflows/ci.yml/badge.svg)](https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica/actions/workflows/ci.yml)

> **Note on language and history.** This project started as a DevOps / Cloud
> Engineer technical assignment **delivered in Spanish**, which is why its Git
> history exists in that language. This repository is a full English translation
> of the code, the docs **and** the commit messages, kept so it can be walked
> through in English during client interviews.
>
> The original repository is the canonical record and stays in Spanish there:
> **[`JuanCruz-Ojeda/entrega-prueba-tecnica`](https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica)**
> (private — access on request). It holds the complete Git history with its
> original SHAs, the **Pull Request** discussions (Track A and Track B were
> merged via PR), the **CI run history**, and the **Security → Code scanning**
> tab (Trivy / Checkov SARIF). Those artifacts live on GitHub and were not
> translated.

HTTP mini-service (Flask) that exposes three endpoints and uses Redis as a
cache / counter. This repo takes an assignment that **did not come up** and
leaves it running, hardened and documented.

- `GET /`           → `{"service":"mini-app","status":"ok"}`
- `GET /health`     → `{"status":"healthy"}` (used by the health checks)
- `GET /cache-test` → increments a counter in Redis and returns it

## Project origin

This repository solves a **DevOps / Cloud Engineer technical test**: you get a
mini-service that does not come up and you have to leave it running, hardened
and documented, in 2-3 hours.

The original assignment, exactly as received (translated to English, see the
notice in each file), is in [`assignment/`](assignment/). The first commit in the
history (`Initial state of the technical test`) is the untouched starting code;
from there each commit fixes one specific problem, so `git log` tells the
reasoning step by step.

---

## How to run it (a single command)

Requirements: **Docker Engine + `docker compose` v2**. On WSL2 Debian the apt
`docker.io` package is too old (no `docker compose`); see
[`REQUIREMENTS.md`](REQUIREMENTS.md) for the detail and per-level install
(base / Track A / Track B).

```bash
docker compose up --build
```

This builds the image, starts Redis and the app, and waits for Redis to be
healthy before starting the app.

- App: <http://localhost:8080/>
- Health: <http://localhost:8080/health>
- Cache: <http://localhost:8080/cache-test>

To stop it:

```bash
docker compose down          # keeps the Redis volume
docker compose down -v       # also deletes the volume
```

Tested from a clean folder (`git clone` → `docker compose up --build`).

### Quick check

Everything in one line (up, test, down):

```bash
docker compose up --build -d && ./scripts/smoke-test.sh && docker compose down -v
```

`scripts/smoke-test.sh` waits for the app to respond, then checks that `/`,
`/health` and `/cache-test` return 200 and that the Redis counter increments
between calls. It is the same script CI runs.

---

## Full verification (step by step)

```bash
# 1. Bring the stack up
docker compose up --build -d

# 2. Endpoints + Redis counter
./scripts/smoke-test.sh

# 3. The app runs as an unprivileged user (non-root)
docker compose exec app id
#    -> uid=10001(appuser) gid=10001(appuser)

# 4. Compose healthchecks green
docker compose ps
#    -> app and redis in state "Up ... (healthy)"

# 5. Resilience: if the main process exits on its own (crash, OOM),
#    "restart: unless-stopped" recreates the container by itself.
docker inspect mini-app-app-1 --format 'restarts={{.RestartCount}}'   # -> 0
docker compose exec app sh -c 'kill -TERM 1'                          # kills the gunicorn master
sleep 12
docker inspect mini-app-app-1 --format 'restarts={{.RestartCount}}'   # -> 1
curl -fsS http://localhost:8080/health                                # -> {"status":"healthy"}

# 6. Tear everything down (and delete the Redis volume)
docker compose down -v
```

### The same thing CI runs, locally

```bash
# Lint (ruff, with the rules from ruff.toml)
docker run --rm -v "$PWD:/io" -w /io ghcr.io/astral-sh/ruff:0.16.5 check .

# Image build
docker build -t mini-app ./app
```

### From a clean clone (the way a reviewer will do it)

```bash
git clone https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica.git
cd entrega-prueba-tecnica
docker compose up --build -d && ./scripts/smoke-test.sh && docker compose down -v
```

---

## What I changed and why

### The stack did not come up

| # | Problem | Fix | Why |
|---|---|---|---|
| 1 | `docker-compose.yml` mapped `8080:8080`, but the app listens on `5000` | Map `8080:5000` | Without this there was nothing listening on the container side on 8080. |
| 2 | Compose never passed `REDIS_HOST` to the app → it used `localhost` → `/cache-test` returned 500 | `environment: REDIS_HOST=${REDIS_HOST:-redis}` | On the Compose network, Redis resolves by the service name (`redis`). |
| 3 | Obsolete `version:` key | Removed | Compose v2 ignores it and warns; it clutters the output. |
| 4 | No startup ordering or health checks | `depends_on: condition: service_healthy` + `healthcheck` on app and redis + `restart: unless-stopped` | The app does not start until Redis is actually ready; if the process dies, the container restarts by itself. |

### Dockerfile (production best practices)

| Before | Now | Why |
|---|---|---|
| `FROM python:3.11` (full image, ~1 GB) | `python:3.11-slim` (final image **134 MB**) | Smaller attack surface, faster pull and deploy. |
| `COPY . .` before `pip install` | Copy `requirements.txt` → install → then `COPY app.py` | Layer cache: changing the code no longer reinstalls dependencies. |
| Ran as `root` | Unprivileged system user (`appuser`) | Reduces the impact of a container compromise. |
| `CMD ["python", "app.py"]` (Flask dev server) | `gunicorn` (production WSGI server, 2 workers) | The dev server is not built for production. |
| No `HEALTHCHECK` | `HEALTHCHECK` against `/health` | Also useful outside Compose (e.g. as a signal in ECS). |
| — | `.dockerignore`, `PYTHONUNBUFFERED`, `PYTHONDONTWRITEBYTECODE` | Smaller build context and unbuffered logs. |

### Application

Minimal changes (rewriting the app was not the goal):

- Removed `import time` (unused).
- Import ordering per isort (the linter asked for it).

### CI/CD

`.github/workflows/ci.yml` was full of TODOs. It now has three jobs:

**`build-test`** — runs on every push and every PR:

1. **Lint** with `ruff` (rules pinned explicitly in `ruff.toml`).
2. **Build + smoke test**: brings the stack up with Compose and runs
   `scripts/smoke-test.sh`. If something fails, it dumps the Compose logs.

**`security-scan`** — runs on every push and PR, in parallel (Track B):

3. **Trivy** (image vulnerabilities, blocks on `CRITICAL`/`HIGH` with a fix) +
   **Checkov** (IaC misconfiguration, does not block). SARIF to *Security → Code scanning*.
   See [`security/README.md`](security/README.md).

**`publish`** — only on push to `main`, and only if `build-test` **and `security-scan`** passed:

4. Builds and **publishes the image to GHCR**
   (`ghcr.io/juancruz-ojeda/entrega-prueba-tecnica`), with the tags
   `latest` and `sha-<commit>`, OCI labels (repo, revision) and layer cache
   across runs. Uses the `GITHUB_TOKEN` Actions already provides (no secrets)
   and permissions scoped to `packages: write` in that job only.

Deploying to AWS follows the same path (OIDC login → push to ECR →
`aws ecs update-service`); the detail is in [`infra/README.md`](infra/README.md).

### Infrastructure

See [`infra/README.md`](infra/README.md): architecture (ECS Fargate + ALB +
ElastiCache) with a rationale for each decision and a step-by-step **AWS CLI
runbook**. Terraform was deliberately not used (the team has not adopted it
yet); the document explains the path to move it to IaC.

---

## Optional Track A — Kubernetes / Helm

First-party chart in [`helm/mini-app/`](helm/mini-app) to deploy the app + Redis
on a local cluster (minikube). Detail and commands in
[`helm/README.md`](helm/README.md).

- **App**: `Deployment` (stateless, parametrizable `replicaCount`) + `Service`.
- **Redis**: `StatefulSet` (1 replica) with `volumeClaimTemplates` (PVC) + headless `Service`.
- **Config/secrets**: `ConfigMap` (`REDIS_HOST`/`REDIS_PORT`) + `Secret` (Redis
  password, auto-generated and stable across `upgrade`). Nothing hardcoded in the manifests.
- **`values.yaml`** parametrizable: replicas, image/tag, PVC size, resources.
- **`helm test`** included (a pod that `curl`s `/health` and `/cache-test`).
- Scaling `app` to 2+ replicas is safe (stateless + shared Redis); the limit is
  Redis (1 instance = SPOF), which in production is ElastiCache. Full analysis in
  `helm/README.md`.

Requires a small backward-compatible change in `app/app.py` (optional
`REDIS_PASSWORD` support); `docker compose` still runs without auth.

---

## Optional Track B — DevSecOps / scanning

The pipeline runs two open-source scanners on every push and PR (job `security-scan`).
Detail, thresholds and accepted findings in [`security/README.md`](security/README.md).

- **Trivy** — vulnerabilities (CVEs) in the image. **Blocks** on `CRITICAL`/`HIGH`
  with a fix available (`--ignore-unfixed`). `publish` depends on this gate.
- **Checkov** — misconfiguration in `Dockerfile`, the Helm chart and `ci.yml` itself.
  **Does not block** (`soft-fail`): visibility, not a gate.
- Both upload SARIF to **Security → Code scanning**.

The scanning **found, and actually fixed** (not suppressed):
unused `pip`/`setuptools`/`wheel` were removed from the image (2 `HIGH` CVEs);
`--pull` on the builds avoids CVEs from a stale base cache; full
`securityContext` on the Helm manifests (54 → 25 Checkov findings).

---

## Decisions left to my judgment

| Decision | Why |
|---|---|
| **gunicorn** instead of the Flask server | Real production: handling multiple requests, robustness under load. |
| **slim** image (not `alpine`) | `alpine` with Python causes headaches with compiled wheels; `slim` is the middle ground. |
| **non-root** user in the image | Principle of least privilege. |
| **Healthchecks** in Compose and in the image | So `depends_on` waits for Redis *ready*, not just *created*; a clear liveness signal for any orchestrator. |
| Redis with a **named volume + appendonly** | The counter survives local restarts. On AWS this is replaced by ElastiCache. |
| **ECS Fargate** (not EC2 or EKS) | Minimal operational overhead for a small service. |
| **ElastiCache** (not Redis in a container) on AWS | With 2+ app replicas, state has to be external and managed. |
| **Secrets Manager** for credentials | Never secrets in the image or in `environment` in plain text. |
| Logs to **stdout/stderr** → CloudWatch | The app does not manage log files; the environment collects them. |
| `ruff.toml` with explicit rules | CI and local give the same result, without depending on the tool's defaults. |

---

## What I would do with more time

- **Hash-pinned dependencies** (`pip-tools` / `--require-hashes`) for 100%
  reproducible builds.
- **Unit tests** for the endpoints with `pytest` + `fakeredis` (today there is
  only an integration smoke test).
- **Multi-stage build** if the dependencies grew and needed a toolchain.
- **Real IaC** (Terraform/CDK) instead of the runbook, with remote state and
  deploy from CI via OIDC.
- **HTTPS** on the ALB (ACM) with an 80→443 redirect.
- **Auto scaling** on the ECS service configured (target-tracking).
- **Redis HA in the chart**: today it is 1 replica; the next step is
  Sentinel/Cluster (or, the production answer, ElastiCache).
- **Harden the chart further** (the remaining Checkov findings): read-only
  filesystem, `NetworkPolicy`, secrets mounted as a file. See `security/README.md`.
- **Image signing** (cosign) and a published **SBOM** alongside the image in GHCR.

---

## Repo structure

```
.
├── app/
│   ├── app.py             # the Flask application (no logic changes)
│   ├── requirements.txt   # flask, redis, gunicorn
│   ├── Dockerfile         # production image
│   └── .dockerignore
├── scripts/
│   └── smoke-test.sh      # endpoint verification (CI + local)
├── infra/
│   └── README.md          # AWS architecture + runbook
├── helm/                  # Optional Track A: Kubernetes / Helm
│   ├── README.md          # how to deploy + scaling analysis
│   └── mini-app/          # first-party chart (Chart.yaml, values.yaml, templates/)
├── security/              # Optional Track B: DevSecOps / scanning
│   └── README.md          # thresholds, findings and what was accepted
├── assignment/            # the original assignment (English translation)
│   ├── README.md          # assignment
│   ├── infra.md           # infrastructure assignment
│   └── OPTIONAL_TRACKS.md
├── .github/workflows/
│   └── ci.yml             # build-test + security-scan + publish
├── docker-compose.yml     # brings everything up with one command
├── ruff.toml              # linter config
├── .checkov.yaml          # Checkov config (Track B)
├── .trivyignore           # Trivy suppressions (Track B, empty today)
├── .env.example
├── REQUIREMENTS.md        # what to install per level (base / Track A / Track B)
└── README.md              # this file
```
