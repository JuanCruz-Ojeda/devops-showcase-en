# "slim" base image, version-pinned: smaller attack surface and reproducible builds.
FROM python:3.11-slim

# - PYTHONDONTWRITEBYTECODE: don't write .pyc files inside the container.
# - PYTHONUNBUFFERED: send logs to stdout/stderr unbuffered (visible in real time).
# - PIP_*: cleaner, quieter installs.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install dependencies BEFORE copying the code: if the code changes but
# requirements.txt does not, Docker reuses this layer and the build is nearly instant.
COPY requirements.txt .
# pip/setuptools/wheel are only needed to INSTALL the packages, not for gunicorn
# to run them at runtime. They are uninstalled in the same layer: this reduces the
# attack surface and removes CVEs from those build tools in the final image
# (found while scanning with Trivy — see security/README.md).
RUN pip install --no-cache-dir -r requirements.txt \
    && pip uninstall -y pip setuptools wheel \
    && rm -rf /usr/local/lib/python3.11/ensurepip

# Only now do we copy the application code.
COPY app.py .

# Run as an unprivileged (non-root) user to reduce the impact of a possible
# container compromise. It gets its own HOME because gunicorn needs a writable
# directory for its internal control socket.
RUN useradd --create-home --uid 10001 appuser
USER appuser
ENV HOME=/home/appuser

# Port gunicorn listens on inside the container.
EXPOSE 5000

# Image-level healthcheck (also useful outside compose, e.g. in ECS).
# The slim image does not ship curl, but it does ship Python: we hit /health with urllib.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:5000/health').status == 200 else 1)"

# Production WSGI server. Flask's development server (python app.py) is not meant
# for production (single-thread, not robust under load).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
