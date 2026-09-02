# Optional Track B — DevSecOps / scanning in CI

The pipeline (`.github/workflows/ci.yml`, job `security-scan`) runs two
open-source scanners on every push and every PR, in parallel with `build-test`.

| Scanner | What it looks at | Blocks? | Why that threshold |
|---|---|---|---|
| **Trivy** | Known vulnerabilities (CVEs) in the image: OS packages + Python dependencies | **Yes**, on `CRITICAL`/`HIGH` **with a fix available** (`--ignore-unfixed`) | These are concrete, actionable threats: there is a patch. Blocking forces the update. What has no fix yet you cannot solve today — blocking there would just keep the pipeline red forever. |
| **Checkov** | Misconfiguration / bad practices in `Dockerfile`, the Helm chart and `ci.yml` itself | **No** (`soft-fail` in `.checkov.yaml`) | These are best-practice rules, more subjective and with more false positives across frameworks. They exist for visibility and human review (**Security → Code scanning** tab), not to stop deliveries. |

**`publish` depends on `security-scan`**: an image that did not pass Trivy's gate
is not published to GHCR.

Both produce results in **SARIF** format and upload them to the repo's
*Security → Code scanning*, in separate categories (`trivy` / `checkov`).

> Note: the upload to *Code scanning* only works on **public** repos (or with
> GitHub Advanced Security). On a private repo the step is marked
> `continue-on-error` and the job does not fail — the full report still lands in
> the `security-scan` log. When the repo is made public, the Security tab
> populates on its own.

---

## Trivy — findings and what was done

Initial run against the image: **3 CRITICAL, 18 HIGH** (166 total).
Of those, **5 HIGH had a fix** → with the threshold, the build failed.

### Actually fixed (not suppressed)

| Finding | Cause | Fix |
|---|---|---|
| `CVE-2026-14456` in `openssl` / `libssl3t64` (3 packages) | The `FROM python:3.11-slim` layer was **cached**: it did not pull the new, already-patched manifest | `--pull` / `pull: true` on all builds (compose and `build-push-action`) |
| `CVE-2026-23949` in `jaraco.context`, `CVE-2026-24049` in `wheel` | `pip`/`setuptools`/`wheel` ship in the base image and are **not used at runtime** (only to install) | `pip uninstall -y pip setuptools wheel` in the same `RUN` layer (`app/Dockerfile`) |

After these two changes: **0 `CRITICAL`/`HIGH` findings with a fix.** The gate
passes clean, with no need for `.trivyignore` (it stays empty).

### What remains (and why it does not block)

- **3 `CRITICAL`**, all in `perl-base` (`CVE-2026-13221`, `CVE-2026-42496`, `CVE-2026-8376`):
  a package Debian ships by default, **no fix available yet**, and one the
  application (pure Python) **never runs**. No real exposure.
- **~13 `HIGH`** with no fix, in base-OS packages. They will resolve themselves
  once Debian ships the patches and the image is rebuilt (the `--pull` will pick
  them up).

`--ignore-unfixed` is what lets exactly these through: findings that cannot be
acted on today.

---

## Checkov — findings and what was done

Initial run: **`Dockerfile` 53/53 OK**, **GitHub Actions 56/56 OK**,
**Helm 217/271** → **54 failures**, almost all about Kubernetes `securityContext`.

### Actually fixed (`helm/mini-app/templates/`)

`securityContext` was added at the pod and container level in `app`, `redis` and
the `helm test` pod:

- `runAsNonRoot: true` + explicit `runAsUser`/`runAsGroup` (the image already ran
  non-root; now Kubernetes knows and enforces it).
- `seccompProfile: RuntimeDefault`.
- `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`.
- `automountServiceAccountToken: false` (no pod calls the k8s API).
- `fsGroup` on Redis so the PVC is writable running as non-root.
- Resource requests/limits on the `helm test` pod.

Result: **54 → 25 failures**. Verified that the chart still deploys and works
(`helm test` + smoke test OK, Redis writes to the PVC).

### What remains (deliberate decisions)

| Check | # | Why it is accepted |
|---|---|---|
| `CKV_K8S_21` default namespace | 7 | The namespace is an **install-time** decision (`helm install -n ...`), not the chart's. The chart deliberately does not hardcode it. |
| `CKV_K8S_15` `imagePullPolicy: Always` | 3 | Intentional: `IfNotPresent` is **required** for the local flow with `minikube image load` (no registry). |
| `CKV_K8S_43` image by digest | 3 | Locally the mutable `:dev` tag is used to iterate. In a real deploy the GHCR image would be pinned by digest. |
| `CKV_K8S_22` read-only filesystem | 3 | gunicorn (control socket) and Redis (`--appendonly`) need writable paths; this would require mounting an `emptyDir`. Pending. |
| `CKV_K8S_35` secrets as a file | 2 | The app reads `REDIS_PASSWORD` from env; passing it as a mounted file requires a code change. Pending. |
| `CKV_K8S_40` high UID | 2 | The UID is set by the **third-party image** (`redis`=999, `curl_user`=100). The app does comply (uid 10001). |
| `CKV_K8S_8/9` probes on the test pod | 2 | It is a one-shot pod that runs and exits — readiness/liveness do not apply. |
| `CKV2_K8S_6` NetworkPolicy | 3 | A bigger feature; also minikube's default CNI does not enforce it. Pending. |

All of them are in the SARIF and visible in *Security → Code scanning*; none is hidden.

---

## Running the scanners locally

```bash
# Trivy — image vulnerabilities
docker build --pull -t mini-app:scan ./app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity CRITICAL,HIGH --ignore-unfixed mini-app:scan

# Checkov — IaC misconfiguration
docker run --rm -v "$PWD:/repo" -w /repo bridgecrew/checkov:latest \
  --config-file .checkov.yaml
```

---

## With more time

- Read-only filesystem in the containers (`emptyDir` for the writable paths).
- `NetworkPolicy` restricting app ↔ redis ↔ test traffic.
- Image signing (cosign) and publishing an **SBOM** alongside the image.
- Secrets mounted as a file instead of an env var.
