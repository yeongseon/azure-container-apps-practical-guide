---
hide:
  - toc
content_sources:
  diagrams:
    - id: end-to-end-learning-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/
        - https://learn.microsoft.com/azure/container-apps/nodejs-overview
---

# Node.js on Azure Container Apps

This guide provides a comprehensive reference implementation for running Node.js applications on Azure Container Apps (ACA). We use a production-ready Express application to demonstrate best practices for cloud-native deployment, security, and observability on the Azure platform.

## Reference Application

The reference Node.js application is located in the `apps/nodejs/` directory. It is a production-hardened Express implementation designed to showcase modern cloud-native patterns.

Key features demonstrated in the reference app:

- **Health Probes**: Implements `/health` and `/ready` endpoints to enable platform-managed lifecycle and zero-downtime deployments.
- **Structured Logging**: Native JSON logging for all requests and application events, optimized for seamless integration with Azure Log Analytics.
- **Application Insights**: Native support for distributed tracing and performance monitoring through the Azure Monitor OpenTelemetry Distro.
- **Graceful Shutdown**: Handles `SIGTERM` and `SIGINT` signals to ensure in-flight requests are completed before the container stops.
- **KEDA-compatible**: Stateless architecture designed for event-driven autoscaling without internal state dependencies.
- **Dapr-ready**: Prepared for service invocation, state management, and pub/sub patterns using the Dapr sidecar model.

## Prerequisites

Before you begin the tutorial, ensure you have the following tools and resources available:

- **Node.js 20 or higher**: Required for local development, testing, and dependency management.
- **Docker Engine**: Essential for building, testing, and validating container images locally before cloud deployment.
- **Azure CLI 2.57+**: The primary tool for provisioning and managing Azure Container Apps and related infrastructure.
- **Azure Subscription**: An active subscription with sufficient permissions to create Resource Groups and Container Apps environments.

## Tutorial Steps

Follow these step-by-step guides to master the deployment of Node.js applications on Azure Container Apps:

1.  [**Local Development**](./tutorial/01-local-development.md) — Learn how to containerize and run your Express app in Docker on your local machine.
2.  [**First Deployment**](./tutorial/02-first-deploy.md) — Push your container image to Azure Container Registry and create your first Container App.
3.  [**Configuration & Secrets**](./tutorial/03-configuration.md) — Securely manage environment variables and integrate with Azure Key Vault.
4.  [**Logging & Monitoring**](./tutorial/04-logging-monitoring.md) — Configure structured logging and visualize metrics in the Azure Portal.
5.  [**Infrastructure as Code**](./tutorial/05-infrastructure-as-code.md) — Define and deploy your application environment using Bicep templates.
6.  [**CI/CD with GitHub Actions**](./tutorial/06-ci-cd.md) — Build automated pipelines to test and deploy your code on every commit.
7.  [**Revisions & Traffic**](./tutorial/07-revisions-traffic.md) — Master advanced deployment strategies like blue-green and canary releases.

## Node.js Guide Progress Snapshot

| Area | Coverage | Primary Asset |
|---|---|---|
| Build and run locally | Complete | [01-local-development](./tutorial/01-local-development.md) |
| First cloud deployment | Complete | [02-first-deploy](./tutorial/02-first-deploy.md) |
| Config, secrets, and Dapr | Complete | [03-configuration](./tutorial/03-configuration.md) |
| Observability | Complete | [04-logging-monitoring](./tutorial/04-logging-monitoring.md) |
| Infrastructure as Code | Complete | [05-infrastructure-as-code](./tutorial/05-infrastructure-as-code.md) |
| CI/CD automation | Complete | [06-ci-cd](./tutorial/06-ci-cd.md) |
| Safe rollout strategy | Complete | [07-revisions-traffic](./tutorial/07-revisions-traffic.md) |
| Runtime tuning | Complete | [nodejs-runtime](./nodejs-runtime.md) |
| Integration recipes | Complete | [recipes/index](./recipes/index.md) |

## End-to-End Learning Flow

<!-- diagram-id: end-to-end-learning-flow -->
```mermaid
flowchart LR
    A[Local Docker Validation] --> B[Azure First Deployment]
    B --> C[Configuration and Secrets]
    C --> D[Logs, Metrics, Traces]
    D --> E[Bicep-Driven Infrastructure]
    E --> F[GitHub Actions CI/CD]
    F --> G[Revisions and Traffic Splits]
    G --> H[Runtime Tuning and Recipes]
```

!!! tip "Use this order for fastest production readiness"
    Complete tutorials `01` through `07` sequentially first, then use runtime and recipe pages for optimization and integration. This prevents configuration drift and keeps your revisions reproducible.

## Runtime Guide

For detailed technical information on how the Node.js runtime is configured and optimized for Azure Container Apps, see the [Node.js Runtime Reference](./nodejs-runtime.md).

This guide covers:
- Base image selection and security.
- Memory management and garbage collection tuning for containers.
- Node.js package management and Docker layer optimization strategies.

## Recipes

Accelerate your development process with these common integration patterns and production recipes. See the [Recipes Index](./recipes/index.md) for the full catalog.

- **Azure Cosmos DB** — Securely connect to NoSQL databases using Managed Identity.
- **Azure SQL** — Relational database integration with passwordless authentication.
- **Redis Cache** — High-performance distributed caching and session state management.
- **Blob Storage** — Cloud file storage and persistent volume mounts for containers.
- **Dapr Integration** — Building distributed microservices using the Dapr framework.
- **Custom Domains** — Mapping your own branded URLs and SSL certificates to your apps.
- **Container Registry** — Private image hosting and security scanning with ACR.

## What You'll Learn

By completing this guide, you will gain the following capabilities:

- Building production-grade Docker images optimized for the Node.js ecosystem.
- Implementing "Zero-Trust" security by using Managed Identity instead of connection strings.
- Designing for high availability with liveness and readiness probes.
- Troubleshooting distributed systems using platform-native logs and KQL queries.
- Managing the full application lifecycle through infrastructure-as-code and automated CI/CD.

!!! note "Use standard variables consistently"
    For command consistency across tutorials and recipes, use `$RG`, `$APP_NAME`, `$ENVIRONMENT_NAME`, `$ACR_NAME`, and `$LOCATION` in your shell session before running commands.

!!! info "Architecture Best Practices"
    The patterns shown in this guide follow the Azure Well-Architected Framework. We prioritize security via Managed Identity, reliability via Health Probes, and operational excellence via automated deployments.

## See Also

- [Platform Architecture](../../platform/index.md) — Understand the underlying ACA infrastructure.
- [Operations Guide](../../operations/index.md) — Production operations.
- [Troubleshooting Methodology](../../troubleshooting/index.md) — Systematic approach to debugging issues.
- [CLI Reference](../../troubleshooting/first-10-minutes/cli-reference.md) — Quick lookup for CLI commands and limits.

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
- [Node.js on Azure Container Apps overview (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/nodejs-overview)
