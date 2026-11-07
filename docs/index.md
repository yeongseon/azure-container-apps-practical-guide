---
description: Hands-on Azure Container Apps guide — architecture, scaling, networking, monitoring, KQL queries, troubleshooting playbooks, and Bicep labs.
content_sources:
  diagrams:
    - id: learning-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
---
# Azure Container Apps Practical Guide

Azure Container Apps Practical Guide is a hands-on documentation site for learning, deploying, operating, and troubleshooting Azure Container Apps.

It covers Azure Container Apps architecture, environments, revisions, scaling, KEDA, networking, managed identity, monitoring, Log Analytics KQL queries, troubleshooting playbooks, and Bicep-based hands-on labs — from first deployment to production incident response.

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } **New to Container Apps?**

    ---

    Start with platform fundamentals, understand environments and revisions, and deploy your first container app.

    [:octicons-arrow-right-24: Start Here](start-here/overview.md)

-   :material-server:{ .lg .middle } **Running Production Workloads?**

    ---

    Apply battle-tested patterns for container design, scaling, networking, identity, and reliability.

    [:octicons-arrow-right-24: Best Practices](best-practices/index.md)

-   :material-bug:{ .lg .middle } **Investigating an Incident?**

    ---

    Jump straight to hypothesis-driven playbooks with real KQL queries and evidence patterns.

    [:octicons-arrow-right-24: Troubleshooting](troubleshooting/index.md)

</div>

## Navigate the Guide

| Section | Purpose |
|---|---|
| [Start Here](start-here/overview.md) | Orientation, learning paths, and repository map. |
| [Platform](platform/index.md) | Understand core Container Apps architecture, environments, revisions, scaling, networking, and jobs. |
| [Best Practices](best-practices/index.md) | Apply production patterns for container design, scaling, networking, identity, and reliability. |
| [Language Guides](language-guides/index.md) | Follow end-to-end implementation tracks for Python, Node.js, Java, and .NET. |
| [Operations](operations/index.md) | Run production workloads with deployment, monitoring, alerting, and recovery practices. |
| [Troubleshooting](troubleshooting/index.md) | Diagnose startup, networking, scaling, and identity issues quickly. |
| [Reference](reference/index.md) | Use quick lookups for CLI, environment variables, and platform limits. |

For orientation and study order, start with [Start Here](start-here/overview.md).

## Learning flow

<!-- diagram-id: learning-flow -->
```mermaid
flowchart TD
    accTitle: Goal-based learning flow for the Container Apps practical guide
    accDescr: Begin with orientation, learn the platform model, apply production practices, implement a language tutorial, operate the workload, and use troubleshooting or reference material whenever the task requires it.

    START[Start Here<br/>choose a goal and path]
    PLATFORM[Platform<br/>understand service behavior]
    PRACTICES[Best Practices<br/>make design decisions]
    BUILD[Language Guides<br/>build and deploy]
    OPERATE[Operations<br/>run day-two procedures]
    TROUBLESHOOT[Troubleshooting<br/>diagnose from evidence]
    REFERENCE[Reference<br/>look up commands and limits]

    START --> PLATFORM
    PLATFORM --> PRACTICES
    PRACTICES --> BUILD
    BUILD --> OPERATE
    OPERATE --> TROUBLESHOOT
    PLATFORM -. look up details .-> REFERENCE
    BUILD -. look up details .-> REFERENCE
    OPERATE -. look up details .-> REFERENCE
    TROUBLESHOOT -. look up details .-> REFERENCE
```

The solid path is a recommended learning sequence, not a mandatory prerequisite chain. Use the dotted reference links whenever you need exact syntax, configuration meaning, metrics, or limits.

## Scope and disclaimer

This is an independent community project. Not affiliated with or endorsed by Microsoft.

Primary product reference: [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/)

## See Also

- [Start Here](start-here/overview.md)
- [Platform](platform/index.md)
- [Best Practices](best-practices/index.md)
- [Language Guides](language-guides/index.md)
- [Operations](operations/index.md)
- [Troubleshooting](troubleshooting/index.md)
- [Reference](reference/index.md)

## Sources

- [Azure Container Apps overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/overview)
