# Azure Container Apps Python Guide

Comprehensive guide to running Python/Flask applications on Azure Container Apps — from first deploy to production operations.

> **Not just another sample app.** This guide explains *why* things work the way they do, so you can debug issues and make informed decisions.

## What is Azure Container Apps?

Azure Container Apps is a fully managed serverless container service that enables you to run microservices and containerized applications without managing infrastructure. Key features:

- **Serverless containers** — No cluster management, automatic scaling
- **KEDA-based autoscaling** — Scale on HTTP traffic, queues, or custom metrics
- **Revisions & Traffic Splitting** — Built-in blue-green deployments
- **Dapr integration** — Service-to-service invocation, state management, pub/sub
- **Pay-per-use** — Scale to zero, consumption-based pricing

## Learning Paths

```
┌─────────────────────────────────────────────────────────────────────┐
│                         QUICK START (30 min)                        │
│  ┌──────────────┐    ┌──────────────┐                              │
│  │ 1. Local Dev │───▶│ 2. Deploy   │                              │
│  └──────────────┘    └──────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         CORE PATH (2-3 hrs)                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐         │
│  │ 3. Config    │───▶│ 4. Logging  │───▶│ 5. IaC       │         │
│  └──────────────┘    └──────────────┘    └──────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      PRODUCTION PATH (2-3 hrs)                      │
│  ┌──────────────┐    ┌──────────────┐                              │
│  │ 6. CI/CD     │───▶│ 7. Revisions│                              │
│  │ (Actions)    │    │ (Traffic)   │                              │
│  └──────────────┘    └──────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Navigation

<div class="grid cards" markdown>

-   :material-school:{ .lg .middle } **Tutorial**

    ---

    Step-by-step from local development to production

    [:octicons-arrow-right-24: Start Learning](tutorial/index.md)

-   :material-head-cog:{ .lg .middle } **Concepts**

    ---

    Understand how Container Apps works under the hood

    [:octicons-arrow-right-24: Deep Dive](concepts/index.md)

-   :material-cog:{ .lg .middle } **Operations**

    ---

    Production operations and day-2 activities

    [:octicons-arrow-right-24: Operations Guide](operations/index.md)

-   :material-chef-hat:{ .lg .middle } **Recipes**

    ---

    Integration guides for databases and Azure services

    [:octicons-arrow-right-24: Browse Recipes](recipes/index.md)

</div>

## What Makes Container Apps Different?

| Feature | Container Apps | App Service | AKS |
|---------|---------------|-------------|-----|
| Infrastructure management | None | None | Full cluster ops |
| Scaling | KEDA (event-driven) | Manual/Autoscale | HPA/KEDA |
| Scale to zero | ✅ Yes | ❌ No | ✅ With KEDA |
| Microservices | ✅ Native | ⚠️ Limited | ✅ Full |
| Dapr | ✅ Built-in | ❌ No | ⚠️ Add-on |
| Learning curve | Low | Low | High |
| Cost model | Consumption | Always-on | Cluster + nodes |

## References
- [Official Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Container Apps Pricing](https://azure.microsoft.com/pricing/details/container-apps/)
- [Dapr Documentation](https://docs.dapr.io/)
