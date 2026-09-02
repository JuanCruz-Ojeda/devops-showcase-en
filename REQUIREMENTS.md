# Requirements

What you need installed to run each part of the project, and how to install it
on **WSL2 Debian** (which is where it was developed and tested).

| Level | For what | Tools |
|---|---|---|
| **0 — base** | `docker compose up --build` (the graded deliverable) | `git`, `curl`, Docker Engine + `docker compose` v2 |
| **1 — Track A** | Deploy the Helm chart on a local cluster | + `kubectl`, `minikube`, `helm` v3 |
| **2 — Track B** | Run Trivy / Checkov locally | nothing extra (they run as containers) |

> `gh` (GitHub CLI) is **not** needed to run or defend the project — it was only
> used for the Pull Request workflow.

---

## Level 0 — base (required)

### `git` and `curl`

```bash
sudo apt-get update && sudo apt-get install -y git curl
```

### Docker Engine + Compose v2 + buildx

**Important:** Debian's `docker.io` package ships an old version (Docker 20.10)
**without `docker compose`** (the subcommand) or buildx. With that the project
**does not come up**. You have to use the official Docker repo:

```bash
# installs docker-ce + docker-compose-plugin + docker-buildx-plugin
curl -fsSL https://get.docker.com | sudo sh

# use docker without sudo
sudo usermod -aG docker "$USER"

# start the daemon
sudo systemctl enable --now docker 2>/dev/null || sudo service docker start
```

Close and reopen the WSL terminal so it picks up the `docker` group.

### Verify

```bash
docker compose version      # -> Docker Compose version v2.x  (not "command not found")
docker run --rm hello-world # -> "Hello from Docker!"
```

### Run the project

```bash
git clone https://github.com/JuanCruz-Ojeda/entrega-prueba-tecnica.git
cd entrega-prueba-tecnica
docker compose up --build
# in another terminal:
./scripts/smoke-test.sh
```

---

## Level 1 — Track A (Kubernetes / Helm)

Requires Level 0 (Docker is minikube's driver).

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

# helm v3
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Verify

```bash
kubectl version --client
minikube version
helm version
```

### Run Track A

```bash
minikube start --driver=docker --cpus=4 --memory=4096
docker build -t mini-app:dev ./app && minikube image load mini-app:dev
helm upgrade --install mini-app ./helm/mini-app
```

Full detail (scaling, persistence, cleanup) in
[`helm/README.md`](helm/README.md).

---

## Level 2 — Track B (scanners locally)

**Nothing to install.** Trivy and Checkov run as containers:

```bash
# Trivy — image vulnerabilities
docker build --pull -t mini-app:scan ./app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity CRITICAL,HIGH --ignore-unfixed mini-app:scan

# Checkov — IaC misconfiguration
docker run --rm -v "$PWD:/repo" -w /repo bridgecrew/checkov:latest --config-file .checkov.yaml
```

Thresholds and findings in [`security/README.md`](security/README.md).

---

## Versions it was developed and tested with

| Tool | Version |
|---|---|
| Debian (WSL2) | 12 (bookworm) |
| Docker Engine | 29.7.2 |
| Docker Compose | v2 (5.5.0) |
| Buildx | 0.36.1 |
| kubectl | v1.33.1 |
| minikube | v1.36.0 |
| Helm | v3.21.4 |
| git | 2.39.5 |

These are not strict minimums: any Docker with `compose` v2 and buildx, and any
recent `helm` v3 / `kubectl`, should work.
