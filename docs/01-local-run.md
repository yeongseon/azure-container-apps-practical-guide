# Local Development with Docker

Before deploying to Azure Container Apps, it's best to verify your Python application runs correctly in a containerized environment locally. This ensures your Dockerfile is correctly configured and all dependencies are present.

## Overview

```mermaid
flowchart LR
    A[Source Code] --> B[Dockerfile]
    B --> C[docker build]
    C --> D[Local Image]
    D --> E[docker-compose up]
    E --> F[localhost:8000]
    F --> G{Test Endpoints}
    G --> H[/health]
    G --> I[/info]
```

## Prerequisites

!!! info "Docker Required"
    Container Apps run your code in containers. Testing locally with Docker ensures your containerized app works before deployment.

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine
- [Docker Compose](https://docs.docker.com/compose/)
- Python 3.11 or later (optional for local testing outside Docker)

## Running with Docker Compose

The easiest way to start the application along with any required local services (like Redis or a local database) is using Docker Compose.

1. **Build and start the containers:**

   ```bash
   docker-compose up --build
   ```

2. **Access the application:**

   Open your browser and navigate to `http://localhost:8000`.

3. **Check logs:**

   View real-time logs from your Python application container:

   ```bash
   docker-compose logs -f app
   ```

!!! tip "Hot Reload"
    Use volume mounts to enable hot reloading during development. Changes to your Python files will be reflected without rebuilding the image.

## Manual Docker Build

If you want to test the production Dockerfile directly:

1. **Build the image:**

   ```bash
   docker build -t aca-python-app .
   ```

2. **Run the container:**

   ```bash
   docker run -p 8000:8000 --env-file .env aca-python-app
   ```

!!! warning "Environment File"
    Ensure your `.env` file exists and contains required variables. The container will fail to start if critical environment variables are missing.

## Development Workflow

When working locally, you can mount your source code as a volume to see changes reflected immediately without rebuilding the image:

```yaml
# docker-compose.yml snippet
services:
  app:
    volumes:
      - .:/app
    environment:
      - FLASK_ENV=development
      - LOG_LEVEL=DEBUG
```

This local setup mimics the Azure Container Apps environment where your app runs inside a managed Kubernetes cluster, helping you catch configuration issues early.

!!! note "Next Steps"
    Once your app runs locally, proceed to [Provision Infrastructure](02-provision-infra.md) to set up Azure resources.
