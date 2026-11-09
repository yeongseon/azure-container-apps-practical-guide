---
description: Build and operate Flask applications on Azure Container Apps with guided tutorials, Python runtime advice, and integration recipes.
content_sources:
  diagrams:
    - id: ideal-for-development-testing-and-public-facing
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
    - id: for-production-environments-requiring-network-isolation
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint
        - https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
    - id: end-to-end-learning-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/
        - https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud
---
# Python on Azure Container Apps

This guide provides a comprehensive reference implementation for running Python applications on Azure Container Apps. We use a production-ready Flask application to demonstrate best practices for cloud-native deployment, security, and observability on the Azure platform.

## Reference Application

The reference Python application is located in the `apps/python/` directory. It is a production-hardened Flask implementation designed to showcase modern cloud-native patterns.

Key features demonstrated in the reference app:

- **Health Probes**: Implements `/health` and `/ready` endpoints to enable platform-managed lifecycle and zero-downtime deployments.
- **Structured Logging**: Custom JSON formatter for logs, optimized for seamless integration with Azure Log Analytics and Application Insights.
- **OpenTelemetry**: Native support for distributed tracing and performance monitoring through OpenTelemetry (OTel) instrumentation.
- **Gunicorn Configuration**: Optimized WSGI server settings for containerized workloads, including worker management and signal handling.
- **KEDA-compatible**: Stateless architecture designed for event-driven autoscaling without internal state dependencies.
- **Dapr-ready**: Prepared for service invocation, state management, and pub/sub patterns using the Dapr sidecar model.

## Prerequisites

Before you begin the tutorial, ensure you have the following tools and resources available:

- **Python 3.11 or higher**: Required for local development, testing, and dependency management.
- **Docker Engine**: Essential for building, testing, and validating container images locally before cloud deployment.
- **Azure CLI 2.57+**: The primary tool for provisioning and managing Azure Container Apps and related infrastructure.
- **Azure Subscription**: An active subscription with sufficient permissions to create Resource Groups and Container Apps environments.

## Network Architecture by Deployment Mode

Azure Container Apps supports two primary deployment architectures: **public consumption mode** for development and proof-of-concept workloads, and **private VNet-integrated mode** for production environments requiring network isolation and secure access to dependent services.

### Public Consumption Mode

Ideal for development, testing, and public-facing applications. The Container Apps Environment is deployed without a VNet, and your application is accessible via a public HTTPS endpoint.

<!-- diagram-id: ideal-for-development-testing-and-public-facing -->
```mermaid
flowchart TD
    accTitle: Public Python app deployment model
    accDescr: Internet requests enter managed external ingress and are routed to a ready Python replica. Image-pull identity and registry authorization are separate from request traffic, while console logs are sent to the environment logging destination.
    CLIENT[Internet client]
    ACR[Azure Container Registry]
    IDENTITY[Managed identity]
    ROLE[Mode-appropriate ACR pull role]
    LOGS[Logging destination]
    ENV[Container Apps environment]
    INGRESS[Managed external ingress]
    APP[Python container app]
    REVISION[Active revision]
    PROVISIONER[Container Apps provisioning actor]
    REPLICA[Ready Flask + Gunicorn replica<br/>port 8000]

    CLIENT ==>|"HTTPS request"| INGRESS
    ENV -.->|"Hosts managed ingress and app"| INGRESS
    ENV -.->|"Hosts"| APP
    INGRESS -->|"Select active revision"| REVISION
    REVISION -->|"Route to ready replica"| REPLICA
    APP -->|"Contains"| REVISION
    REPLICA ==>|"HTTPS response via ingress"| CLIENT
    IDENTITY -.->|"Assigned for image pull"| APP
    ROLE -.->|"Authorizes identity"| ACR
    REVISION -.->|"Provision declared image"| PROVISIONER
    PROVISIONER ==>|"Authenticated image pull"| ACR
    ACR ==>|"Image layers during provisioning"| PROVISIONER
    PROVISIONER ==>|"Create ready replica"| REPLICA
    REPLICA ==>|"stdout and stderr"| LOGS
```

*Figure: Public ingress request flow is separate from image provisioning, managed-identity authorization, and log transport. The registry SKU and replica limits are deployment choices, not requirements of this model.*

### Private VNet-Integrated Mode

For production environments requiring network isolation. The Container Apps Environment is deployed inside a dedicated VNet with private endpoints to all dependent services.

<!-- diagram-id: for-production-environments-requiring-network-isolation -->
```mermaid
flowchart TD
    accTitle: VNet-integrated Python app with private service endpoints
    accDescr: The managed Container Apps environment uses a dedicated infrastructure subnet. The app resolves dependency names through linked private DNS zones and sends service traffic to private endpoint network interfaces in a separate subnet. Managed identity authorization remains distinct from DNS and transport.
    DNS[Private DNS zones<br/>linked to VNet]
    IDENTITY[User-assigned managed identity]
    KV[Azure Key Vault resource]
    STORAGE[Storage account resource]
    ACR[Azure Container Registry Premium]
    VNET[Customer virtual network]
    INFRA[Dedicated infrastructure subnet]
    ENV[Managed Container Apps environment]
    APP[Python container app]
    PROVISIONER[Container Apps provisioning actor]
    REPLICA[Provisioned Python replica]
    PE_SUBNET[Private endpoint subnet]
    KVPE[Key Vault private endpoint NIC]
    STORAGEPE[Storage private endpoint NIC]
    ACRPE[ACR private endpoint NIC]

    DNS -.->|"Private name resolution"| APP
    VNET -.->|"Contains"| INFRA
    VNET -.->|"Contains"| PE_SUBNET
    INFRA -.->|"Delegated for"| ENV
    ENV -->|"Runs"| APP
    PE_SUBNET -.->|"Contains"| KVPE
    PE_SUBNET -.->|"Contains"| STORAGEPE
    PE_SUBNET -.->|"Contains"| ACRPE
    IDENTITY -.->|"Selected by app or platform"| APP
    APP ==>|"Service request"| KVPE
    APP ==>|"Blob request"| STORAGEPE
    APP -.->|"Provision declared image"| PROVISIONER
    PROVISIONER ==>|"Private image pull"| ACRPE
    ACRPE ==>|"Image layers during provisioning"| PROVISIONER
    PROVISIONER ==>|"Create container"| REPLICA
    KVPE -.->|"Private Link association"| KV
    STORAGEPE -.->|"Private Link association"| STORAGE
    ACRPE -.->|"Private Link association"| ACR
    IDENTITY -.->|"Target-specific authorization"| KV
    IDENTITY -.->|"Target-specific authorization"| STORAGE
    IDENTITY -.->|"Mode-appropriate pull authorization"| ACR
```

*Figure: The Container Apps environment is associated with its infrastructure subnet; Key Vault, Storage, ACR, managed identity, and Private DNS zones remain separate Azure resources. Private DNS, private transport, and authorization are independent requirements.*

!!! tip "Which mode to choose?"
    Start with **Public Consumption** for development and PoC. Move to **Private VNet-Integrated** when your security policy requires private-only access to dependent services or you need to comply with corporate network isolation requirements.

## Tutorial Steps

Follow these step-by-step guides to master the deployment of Python applications on Azure Container Apps:

1.  [**Local Development**](./tutorial/01-local-development.md) — Learn how to containerize and run your Flask app in Docker on your local machine.
2.  [**First Deployment**](./tutorial/02-first-deploy.md) — Push your container image to Azure Container Registry and create your first Container App.
3.  [**Configuration & Secrets**](./tutorial/03-configuration.md) — Securely manage environment variables and integrate with Azure Key Vault.
4.  [**Logging & Monitoring**](./tutorial/04-logging-monitoring.md) — Configure structured logging and visualize metrics in the Azure Portal.
5.  [**Infrastructure as Code**](./tutorial/05-infrastructure-as-code.md) — Define and deploy your application environment using Bicep templates.
6.  [**CI/CD with GitHub Actions**](./tutorial/06-ci-cd.md) — Build automated pipelines to test and deploy your code on every commit.
7.  [**Revisions & Traffic**](./tutorial/07-revisions-traffic.md) — Master advanced deployment strategies like blue-green and canary releases.

## Python Guide Progress Snapshot

| Area | Coverage | Primary Asset |
|---|---|---|
| Build and run locally | Complete | [01-local-development](./tutorial/01-local-development.md) |
| First cloud deployment | Complete | [02-first-deploy](./tutorial/02-first-deploy.md) |
| Config, secrets, and Dapr | Complete | [03-configuration](./tutorial/03-configuration.md) |
| Observability | Complete | [04-logging-monitoring](./tutorial/04-logging-monitoring.md) |
| Infrastructure as Code | Complete | [05-infrastructure-as-code](./tutorial/05-infrastructure-as-code.md) |
| CI/CD automation | Complete | [06-ci-cd](./tutorial/06-ci-cd.md) |
| Safe rollout strategy | Complete | [07-revisions-traffic](./tutorial/07-revisions-traffic.md) |
| Runtime tuning | Complete | [python-runtime](./python-runtime.md) |
| Integration recipes | Complete | [recipes/index](./recipes/index.md) |

## End-to-End Learning Flow

<!-- diagram-id: end-to-end-learning-flow -->
```mermaid
flowchart TD
    accTitle: Python guide learning path
    accDescr: Follow seven ordered tutorials from local Docker validation through revision traffic management, then branch to the Flask and Gunicorn runtime reference and integration recipes.
    LOCAL[01 Local development<br/>Flask + Docker]
    DEPLOY[02 First deployment<br/>image to Container Apps]
    CONFIG[03 Configuration and secrets]
    OBSERVE[04 Logs, metrics, and traces]
    IAC[05 Bicep-driven infrastructure]
    CICD[06 GitHub Actions CI/CD]
    RELEASE[07 Revisions and traffic]
    RUNTIME[Python runtime reference]
    RECIPES[Python integration recipes]

    LOCAL --> DEPLOY --> CONFIG --> OBSERVE --> IAC --> CICD --> RELEASE
    RELEASE --> RUNTIME
    RELEASE --> RECIPES
```

*Figure: The numbered tutorials form the common learning sequence. Runtime tuning and integration recipes are follow-on references rather than additional deployment stages.*

!!! tip "Use this order for fastest production readiness"
    Complete tutorials `01` through `07` sequentially first, then use runtime and recipe pages for optimization and integration. This prevents configuration drift and keeps your revisions reproducible.

## Runtime Guide

For detailed technical information on how the Python runtime is configured and optimized for Azure Container Apps, see the [Python Runtime Reference](./python-runtime.md).

This guide covers:
- WSGI server (Gunicorn) worker configuration and tuning.
- System-level and application-specific environment variable overrides.
- Python package management and Docker layer optimization strategies.

## Recipes

Accelerate your development process with these common integration patterns and production recipes:

- [**Azure Cosmos DB**](./recipes/cosmosdb.md) — Securely connect to NoSQL databases using Managed Identity.
- [**Azure SQL**](./recipes/azure-sql.md) — Relational database integration with passwordless authentication.
- [**Redis Cache**](./recipes/redis.md) — High-performance distributed caching and session state management.
- [**Blob Storage**](./recipes/storage.md) — Cloud file storage and persistent volume mounts for containers.
- [**Dapr Integration**](./recipes/dapr-integration.md) — Building distributed microservices using the Dapr framework.
- [**Custom Domains**](./recipes/custom-domains.md) — Mapping your own branded URLs and SSL certificates to your apps.
- [**Container Registry**](./recipes/container-registry.md) — Private image hosting and security scanning with ACR.

## What You'll Learn

By completing this guide, you will gain the following capabilities:

- Building production-grade Docker images optimized for the Python ecosystem.
- Implementing "Zero-Trust" security by using Managed Identity instead of connection strings.
- Designing for high availability with liveness and readiness probes.
- Troubleshooting distributed systems using platform-native logs and KQL queries.
- Managing the full application lifecycle through infrastructure-as-code and automated CI/CD.

!!! note "Use standard variables consistently"
    For command consistency across tutorials and recipes, use `$RG`, `$APP_NAME`, `$ACA_ENV_NAME`, `$ACR_NAME`, and `$LOCATION` in your shell session before running commands.

!!! info "Architecture Best Practices"
    The patterns shown in this guide follow the Azure Well-Architected Framework. We prioritize security via Managed Identity, reliability via Health Probes, and operational excellence via automated deployments.

## See Also

- [Platform Architecture](../../platform/index.md) — Understand the underlying Container Apps infrastructure.
- [Operations Guide](../../operations/index.md) — Production operations.
- [Troubleshooting Methodology](../../troubleshooting/index.md) — Systematic approach to debugging issues.
- [CLI Reference](../../troubleshooting/first-10-minutes/cli-reference.md) — Quick lookup for CLI commands and limits.

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Python on Azure Container Apps overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud)
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Managed identity image pulls in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Custom virtual networks in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks)
- [Private endpoints in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint)
- [Private endpoint DNS configuration (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
