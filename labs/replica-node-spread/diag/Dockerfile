# Diag image for the replica-node-spread lab.
#
# Runs a Flask app under gunicorn that exposes /diag with kernel-level
# signals (boot_id, uptime, machine_id, kernel_release, microcode) so the
# lab can infer per-replica node distribution from a public HTTP endpoint.
#
# Built per lab README:
#   cd labs/replica-node-spread/diag
#   az acr build --registry <acr> --image rns-lab/diag:latest .
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

# Two workers x two threads is enough headroom for the lab's
# observe-only HTTP load (no business logic). Bind to all interfaces
# so the ACA ingress can reach it.
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "2", \
     "--threads", "2", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
