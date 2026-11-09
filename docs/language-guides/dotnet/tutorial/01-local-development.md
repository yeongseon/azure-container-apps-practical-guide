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
        - https://learn.microsoft.com/en-us/dotnet/core/docker/build-container
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

Before deploying to Azure Container Apps, validate your .NET app in a container locally. This catches image, dependency, and port issues early.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, managed identity image pull, and a private endpoint for ACR.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "12px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 100}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the .NET local-development tutorial
    accDescr: A client exchanges requests and responses with .NET replicas through managed ingress. The infrastructure subnet associates with the environment, an identity is assigned to the app, and revision provisioning exchanges image requests and layer responses with ACR through its private endpoint.
    CLIENT["Client"]
    subgraph ENV["Container Apps<br/>environment"]
        direction TD
        INGRESS["Managed ingress"]
        APP["Container app<br/>.NET 8"]
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
    accTitle: Local .NET container development workflow
    accDescr: Source code is packaged by a multi-stage Docker build, run as a local container on port 8000, and checked through the health endpoint before deployment.

    CODE["ASP.NET Core source<br/>and project file"]
    BUILD["Multi-stage Docker build<br/>publish .NET 8 app"]
    IMAGE["Local image<br/>aca-dotnet-guide"]
    CONTAINER["Local container<br/>port 8000"]
    HEALTH["GET /health<br/>expect HTTP 200"]

    CODE -->|"docker build"| BUILD
    BUILD -->|"Package runtime image"| IMAGE
    IMAGE -->|"docker run --publish 8000:8000"| CONTAINER
    CONTAINER -->|"Health request"| HEALTH
```

*Figure: Build the .NET application into a local image, run it with the same port contract used in Azure, and verify `/health` before continuing.*

## Prerequisites

- Docker Engine or Docker Desktop
- .NET 8.0 SDK (optional for local Docker build)
- Source code with a Dockerfile

!!! tip "Aim for local-cloud parity"
    Keep local container port mapping and environment variable names aligned with your Azure deployment settings. This reduces revision failures caused by mismatched runtime assumptions.

## Step-by-step

1. **Build the container image**

   ```bash
   cd apps/dotnet-aspnetcore
   docker build --tag aca-dotnet-guide .
   ```

   ???+ example "Expected output"
       ```text
       [1/10] FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
       [2/10] WORKDIR /src
       [3/10] COPY *.csproj ./
       [4/10] RUN dotnet restore
       [5/10] COPY . ./
       [6/10] RUN dotnet publish -c Release -o /app/publish
       [7/10] FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine
       [8/10] WORKDIR /app
       [9/10] COPY --from=build /app/publish .
       [10/10] EXPOSE 8000
       Successfully tagged aca-dotnet-guide:latest
       ```

2. **Run the container locally**

   ```bash
   # Copy and customize the environment file
   cp .env.example .env

   docker run --publish 8000:8000 --env-file .env aca-dotnet-guide
   ```

   ???+ example "Expected output"
       ```text
       info: Microsoft.Hosting.Lifetime[14]
             Now listening on: http://0.0.0.0:8000
       info: Microsoft.Hosting.Lifetime[0]
             Application started. Press Ctrl+C to shut down.
       info: Microsoft.Hosting.Lifetime[0]
             Hosting environment: Production
       info: Microsoft.Hosting.Lifetime[0]
             Content root path: /app
       ```

3. **Verify health endpoint**

   ```bash
   curl http://localhost:8000/health
   ```

   ???+ example "Expected output"
       ```json
       {"status":"healthy","timestamp":"2026-04-04T16:13:19.2964050Z"}
       ```

   You can also verify runtime metadata:

   ```bash
   curl http://localhost:8000/info
   ```

   ???+ example "Expected output"
       ```json
       {"app":"azure-container-apps-dotnet-guide","version":"1.0.0","runtime":{"dotnet":".NET 8.0.25","os":"Alpine Linux v3.23","arch":"X64"}}
       ```

4. **Inspect application logs**

   ```bash
   docker logs <container-id>
   ```

   ???+ example "Expected output"
       ```text
       info: Microsoft.Hosting.Lifetime[14]
             Now listening on: http://0.0.0.0:8000
       info: Microsoft.Hosting.Lifetime[0]
             Application started. Press Ctrl+C to shut down.
       ```

   To find the container ID: `docker ps`

## Local parity checklist

- Application listens on port `8000` (or your configured `PORT` environment variable)
- Required environment variables are present in `.env`
- `/health` returns HTTP 200 with JSON payload
- No startup exceptions (e.g., `DependencyInjectionException`) in container logs

!!! warning "Do not commit local secret files"
    If you create a local `.env` file for testing, keep sensitive values out of source control and use placeholder values in shared examples.

## Advanced Topics

- **Multi-stage builds**: Use the build stage for running unit tests before publishing.
- **Rootless containers**: The reference app uses `USER 1000:1000` for enhanced security.
- **OpenTelemetry**: Enable local OTLP exporters to validate telemetry before cloud deployment.

## Review Matrix

| Review area | Page-specific check |
|---|---|
| Scope | Confirm the guidance applies to 01 - Run Locally with Docker. |
| Source basis | Validate the recommendation against the Microsoft Learn sources in this page. |
| Evidence | Capture command output, portal state, metrics, logs, or screenshots before treating the result as proven. |

## See Also
- [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- [03 - Configuration, Secrets, and Dapr](03-configuration.md)
- [.NET Runtime Reference](../dotnet-runtime.md)

## Sources
- [Azure Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Managed identity image pull](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Private endpoints for Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Quickstart: Code to Cloud (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud)
- [Dockerizing an ASP.NET Core application (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/core/docker/build-container)
