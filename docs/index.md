# Azure Container Apps Guide

A practical hub for learning, designing, operating, and troubleshooting Azure Container Apps and Jobs across languages, revision models, and deployment patterns.

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } **Start Here**

    ---

    New to Container Apps? Start with the overview, learning paths, and repository map.

    [:octicons-arrow-right-24: Get Started](start-here/overview.md)

-   :material-layers:{ .lg .middle } **Platform**

    ---

    Understand the core architecture, scaling, networking, and security concepts.

    [:octicons-arrow-right-24: Explore Platform](platform/index.md)

-   :material-code-tags:{ .lg .middle } **Language Guides**

    ---

    Step-by-step tutorials and implementation recipes for Python, Node.js, and more.

    [:octicons-arrow-right-24: View Guides](language-guides/index.md)

-   :material-cog:{ .lg .middle } **Operations**

    ---

    Guide for running in production: deployment, monitoring, and secret rotation.

    [:octicons-arrow-right-24: Operations Guide](operations/index.md)

-   :material-lifebuoy:{ .lg .middle } **Troubleshooting**

    ---

    Quick triage, playbooks, and methodology for when things go wrong.

    [:octicons-arrow-right-24: Fix Issues](troubleshooting/index.md)

</div>

## What Makes Container Apps Different?

Azure Container Apps is a fully managed serverless container service. It enables you to run microservices and containerized applications without managing complex infrastructure.

| Feature | Container Apps | App Service | AKS |
|---------|---------------|-------------|-----|
| Infrastructure management | None | None | Full cluster ops |
| Scaling | KEDA (event-driven) | Manual/Autoscale | HPA/KEDA |
| Scale to zero | ✅ Yes | ❌ No | ✅ With KEDA |
| Microservices | ✅ Native | ⚠️ Limited | ✅ Full |
| Dapr | ✅ Built-in | ❌ No | ⚠️ Add-on |
| Learning curve | Low | Low | High |
| Cost model | Consumption | Always-on | Cluster + nodes |

## See Also

- [Azure Container Apps Documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
- [Dapr Documentation](https://docs.dapr.io/)
- [KEDA Documentation](https://keda.sh/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
