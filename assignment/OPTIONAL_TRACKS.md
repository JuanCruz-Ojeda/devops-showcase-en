<!--
Original content as received (unmodified). Unofficial English translation of the
Spanish original. The reference to "README_CANDIDATO.md" is from the original
assignment package (it maps to assignment/README.md here).
-->

# Optional tracks (candidate's choice)

The core of the exercise (see `README_CANDIDATO.md`) is enough to evaluate the
essentials. These two tracks are **optional and not required** — choose to do
the one(s) that match your real experience. Skipping them does not subtract
points from the core; doing them well adds extra points.

## Track A — Kubernetes / Helm

If you have real experience with Kubernetes, deploy `app/` (together with Redis)
on a local cluster (for example `kind` or `minikube`) using a **first-party Helm
chart** (not a third-party chart copied without understanding what it does).

At a minimum:
- Deployment + Service for `app` and for `redis` (or a Redis chart as a
  dependency, if you can justify why).
- Configuration/secret handling via `ConfigMap`/`Secret` (no hardcoded
  variables in the manifest).
- A `values.yaml` with at least one parametrizable value (for example,
  replicas or the image/tag).
- That you can explain, in the defense, what happens if you scale `app` to 2+
  replicas with the current state (shared Redis).

## Track B — DevSecOps / scanning in the pipeline

If you have experience with security in CI/CD, add a scanning step to the
pipeline (`.github/workflows/ci.yml`), using open-source tools (no paid license
required):

- **Trivy** (or similar) to scan the Docker image for known vulnerabilities.
- **tfsec** or **checkov** to scan the code in `infra/` if you did Terraform.

The pipeline does not have to fail the build on every finding — show us that you
know how to configure a reasonable threshold (for example, only fail on
CRITICAL/HIGH) and that you can explain why you chose that threshold.
