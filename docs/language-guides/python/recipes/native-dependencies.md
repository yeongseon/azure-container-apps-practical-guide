# Recipe: Python Native Dependencies on Azure Container Apps

Handle Python packages with compiled/native components by installing required system libraries and using build strategies that keep runtime images lean.

## Prerequisites

- Docker 24+
- Python dependency list containing native packages (for example `psycopg2`, `numpy`, `Pillow`, `cryptography`)
- Existing ACR for pushing tested images

## Common native dependency scenarios

- `psycopg2`: needs PostgreSQL client headers (`libpq-dev`) when building from source
- `numpy`/`scipy`: can require BLAS/LAPACK toolchain for source builds
- `Pillow`: often needs image libs (`libjpeg-dev`, `zlib1g-dev`)
- `cryptography`: may need Rust and OpenSSL headers if wheel is unavailable

## `python:3.11-slim` vs `python:3.11`

| Base image | Size | Compatibility | Recommendation |
|---|---|---|---|
| `python:3.11-slim` | Smaller | May require manual system libs | Preferred for production |
| `python:3.11` | Larger | More libraries preinstalled | Useful for quick debugging |

## Install system packages in Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app

RUN apt-get update && apt-get install --yes --no-install-recommends \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt

COPY src ./src
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--chdir", "src", "app:app"]
```

## Multi-stage build for smaller runtime images

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /build

RUN apt-get update && apt-get install --yes --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels --requirement requirements.txt

FROM python:3.11-slim AS runtime
WORKDIR /app

RUN apt-get update && apt-get install --yes --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels --requirement requirements.txt \
    && rm -rf /wheels

COPY src ./src
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--chdir", "src", "app:app"]
```

## Pre-compiled wheels vs source build

- Prefer wheels for faster builds and predictable runtime behavior.
- If wheels are unavailable for your architecture, install compile toolchains in the builder stage.
- Pin versions to avoid unexpected source compilation after upstream wheel changes.

## Example: `psycopg2-binary` vs `psycopg2`

```text
# requirements.txt (simple)
psycopg2-binary==2.9.9
```

```text
# requirements.txt (source build)
psycopg2==2.9.9
```

With `psycopg2-binary`, you often avoid installing `libpq-dev`. With `psycopg2` source builds, include `libpq-dev` and a compiler in your builder stage.

## Test native dependencies locally before deploy

```bash
docker build --tag "$ACR_NAME.azurecr.io/$APP_NAME:native-test" .
docker run --rm --publish 8000:8000 "$ACR_NAME.azurecr.io/$APP_NAME:native-test"
curl "http://localhost:8000/health"
```

Minimal runtime import verification:

```bash
docker run --rm "$ACR_NAME.azurecr.io/$APP_NAME:native-test" \
  python -c "import psycopg2, PIL, numpy, cryptography; print('native imports ok')"
```

## Advanced Topics

- Build and test on the same CPU architecture as your target environment.
- Cache wheels in CI for reproducible and faster pipelines.
- Scan final images for CVEs after package install.

## See Also

- [Custom Container](custom-container.md)
- [Container Registry](container-registry.md)
- [Revisions](../../../platform/revisions/index.md)
- [Microsoft Learn: Build images for Container Apps](https://learn.microsoft.com/azure/container-apps/tutorial-build-deploy-image)
