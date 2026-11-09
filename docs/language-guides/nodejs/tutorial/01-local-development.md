---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints
    - id: local-development-workflow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud
        - https://learn.microsoft.com/en-us/azure/container-apps/containers#configuration
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 01 - Run Locally with Docker

Before deploying to Azure Container Apps, validate your Node.js app in a container locally. This catches image, dependency, and port issues early.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, managed identity image pull, and a private endpoint for ACR.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "12px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 100}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Node.js local-development tutorial
    accDescr: A client exchanges requests and responses with Node.js replicas through managed ingress. The infrastructure subnet associates with the environment, an identity is assigned to the app, and revision provisioning exchanges image requests and layer responses with ACR through its private endpoint.
    CLIENT["Client"]
    subgraph ENV["Container Apps<br/>environment"]
        direction TD
        INGRESS["Managed ingress"]
        APP["Container app<br/>Node.js 20"]
        PROVISION["Revision provisioning<br/>(platform)"]
        REPLICAS["Running replicas"]
    end
    INFRA["Subnet"]
    IDENTITY["Identity"]
    PE_ACR["ACR private<br/>endpoint"]
    ACR["Azure Container<br/>Registry"]
    DNS["ACR DNS zone"]
    CLIENT ==>|"Req"| INGRESS
    INGRESS ==>|"Resp"| CLIENT
    INGRESS ==>|"Req"| REPLICAS
    REPLICAS ==>|"Resp"| INGRESS
    APP -.-> REPLICAS
    APP -.-> IDENTITY
    INFRA -.-> ENV
    PROVISION ==>|"Pull"| PE_ACR
    PE_ACR ==>|"Req"| ACR
    ACR ==>|"Resp"| PE_ACR
    PE_ACR ==>|"Layers"| PROVISION
    DNS -.-> PE_ACR
    CLIENT ~~~ INFRA ~~~ INGRESS ~~~ APP ~~~ IDENTITY ~~~ REPLICAS ~~~ PROVISION ~~~ DNS ~~~ PE_ACR ~~~ ACR
    linkStyle 12,13,14,15,16,17,18,19,20 opacity:0
```

*Figure: The infrastructure subnet integrates with the environment, the identity is assigned to the container app, and platform revision provisioning exchanges image requests and layer responses with ACR through its private endpoint.*

## Local Development Workflow

<!-- diagram-id: local-development-workflow -->
```mermaid
flowchart TD
    accTitle: Local Node.js container development workflow
    accDescr: Express source and dependencies are packaged by Docker, run as a local container on port 8000, and checked through the health endpoint before deployment.
    CODE["Express source<br/>and package files"]
    BUILD["Docker build<br/>install production dependencies"]
    IMAGE["Local image<br/>aca-nodejs-guide"]
    CONTAINER["Local container<br/>port 8000"]
    HEALTH["GET /health<br/>expect HTTP 200"]
    CODE -->|"docker build"| BUILD
    BUILD -->|"Package Node.js image"| IMAGE
    IMAGE -->|"docker run --publish 8000:8000"| CONTAINER
    CONTAINER -->|"Health request"| HEALTH
```

*Figure: Build the Express application into a local image, run it with the Azure port contract, and verify `/health` before continuing.*

## Prerequisites

- Docker Engine or Docker Desktop
- Node.js and npm installed
- Source code with a Dockerfile

!!! tip "Aim for local-cloud parity"
    Keep local container port mapping and environment variable names aligned with your Azure deployment settings. This reduces revision failures caused by mismatched runtime assumptions.

## Step-by-step

1. **Build the container image**

    ```bash
    cd apps/nodejs
    docker build --tag aca-nodejs-guide .
    ```

    ???+ example "Expected output"
        ```text
        [1/5] FROM docker.io/library/node:20-slim
        [2/5] WORKDIR /app
        [3/5] COPY package*.json ./
        [4/5] RUN npm install --omit=dev
        [5/5] COPY src/ ./src/
        Successfully tagged aca-nodejs-guide:latest
        ```

2. **Run the container locally**

    ```bash
    # Copy and customize the environment file
    cp .env.example .env

    docker run --publish 8000:8000 --env-file .env aca-nodejs-guide
    ```

    ???+ example "Expected output"
        ```json
        {"timestamp":"2026-04-05T10:00:00.000Z","level":"INFO","message":"Server started on port 8000"}
        ```

3. **Verify health endpoint**

    ```bash
    curl http://localhost:8000/health
    ```

    ???+ example "Expected output"
        ```json
        {"status":"healthy","timestamp":"2026-04-05T10:01:00.000Z"}
        ```

    You can also verify runtime metadata:

    ```bash
    curl http://localhost:8000/info
    ```

    ???+ example "Expected output"
        ```json
        {"app":"azure-container-apps-nodejs-guide","version":"1.0.0","runtime":{"node":"v20.20.2","platform":"linux","arch":"x64"}}
        ```

4. **Inspect application logs**

    ```bash
    docker logs <container-id>
    ```

    ???+ example "Expected output"
        ```json
        {"timestamp":"2026-04-05T10:00:00.000Z","level":"INFO","message":"Server started on port 8000"}
        {"timestamp":"2026-04-05T10:01:00.000Z","level":"INFO","method":"GET","url":"/health","status":200}
        ```

    To find the container ID: `docker ps`

## Local parity checklist

- Application listens on port `8000` (or your configured container port)
- Required environment variables are present
- `/health` returns HTTP 200
- No startup exceptions in container logs

!!! warning "Do not commit local secret files"
    If you create a local `.env` file for testing, keep sensitive values out of source control and use placeholder values in shared examples.

## Advanced Topics

- Use multi-stage Docker builds to keep your production image lean and secure.
- Use `node --watch` during development to automatically restart the server on file changes.
- Add local Redis or MongoDB via `docker-compose` to mimic cloud dependencies.

## Review Matrix

| Review area | Page-specific check |
|---|---|
| Scope | Confirm the guidance applies to 01 - Run Locally with Docker. |
| Source basis | Validate the recommendation against the Microsoft Learn sources in this page. |
| Evidence | Capture command output, portal state, metrics, logs, or screenshots before treating the result as proven. |

## See Also

- [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- [03 - Configuration, Secrets, and Dapr](03-configuration.md)
- [Recipes Index](../recipes/index.md)

## Sources
- [Azure Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Managed identity image pull](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Private endpoints for Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Quickstart: Code to Cloud (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud)
- [Dockerfile requirements for Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers#configuration)
