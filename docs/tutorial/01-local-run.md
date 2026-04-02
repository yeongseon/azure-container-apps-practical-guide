# 01 - Run Locally with Docker

Before deploying to Azure Container Apps, validate your Python app in a container locally. This catches image, dependency, and port issues early.

## Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose
- Source code with a Dockerfile

## Step-by-step

1. **Build and run with Docker Compose**

   ```bash
   docker compose up --build
   ```

2. **Verify health endpoint**

   ```bash
   curl http://localhost:8000/health
   ```

3. **Inspect application logs**

   ```bash
   docker compose logs --follow app
   ```

4. **Test production image path (optional)**

   ```bash
   docker build --tag aca-python-app:local .
   docker run --publish 8000:8000 --env-file .env aca-python-app:local
   ```

## Local parity checklist

- Application listens on port `8000` (or your configured container port)
- Required environment variables are present
- `/health` returns HTTP 200
- No startup exceptions in container logs

## Advanced Topics

- Add local Redis or PostgreSQL in `docker-compose.yml` to mimic service dependencies.
- Use OpenTelemetry locally to validate logs and traces before cloud deployment.
- Add a Dapr sidecar for local service invocation testing.

## See Also

- [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- [03 - Configuration, Secrets, and Dapr](03-configuration.md)
- [Dapr Integration Recipe](../recipes/dapr-integration.md)
