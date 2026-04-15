---
content_sources:
  diagrams:
    - id: documents
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/
---

# Concepts

This section explains Azure Container Apps platform behavior in a language-agnostic way. Use these documents to understand architecture, scaling, and networking before diving into implementation.

## Main Content

### Documents

| Document | Description |
|---|---|
| [Architecture: Resource Relationships](architecture/resource-relationships.md) | Control plane vs data plane, environment and app resource hierarchy |
| [Environments](environments/index.md) | Regional boundary for apps, consumption vs workload profiles |
| [Revisions](revisions/index.md) | Immutable snapshots, single vs multi-revision mode, traffic splitting |
| [Scaling](scaling/index.md) | KEDA autoscaling, HTTP/event/custom scale rules, replica management |
| [Networking](networking/index.md) | Ingress, VNet integration, private endpoints, service discovery |
| [Jobs](jobs/index.md) | Scheduled, event-driven, and manual job execution |
| [Identity and Secrets](identity-and-secrets/managed-identity.md) | Managed identity setup and RBAC patterns (see also Key Vault, Easy Auth, Security Operations pages) |
| [Reliability](reliability/health-recovery.md) | Health probes, graceful shutdown, zone redundancy, recovery |

<!-- diagram-id: documents -->
```mermaid
graph LR
    A[Architecture] --> B[Environments]
    B --> C[Revisions]
    C --> D[Scaling]
    D --> E[Networking]
    E --> F[Identity and Secrets]
    F --> G[Reliability]
    C --> H[Jobs]
```

### Recommended reading order

1. Start with architecture and resource relationships
2. Understand environment boundaries and profile choices
3. Learn revision lifecycle and traffic splitting
4. Design scaling envelope with KEDA rules
5. Finalize networking controls and ingress
6. Validate identity, secrets, and reliability patterns

!!! tip "Read by decision sequence"
    If you are designing a new workload, treat this section as a dependency chain: architecture and environments first, then revisions/scaling, and finally networking plus identity controls.

!!! warning "Do not skip platform concepts"
    Jumping directly to language guides without understanding revision mode, ingress boundaries, and scaling behavior often leads to production misconfigurations.

## Advanced Topics

- Build architecture decision records (ADRs) per environment
- Standardize profile and scaling baselines by workload class
- Define SLO-driven scaling and networking review checkpoints

!!! note "Platform docs are language-agnostic"
    Implementation snippets in language guides should follow the architectural boundaries defined here, not the other way around.

## Language-Specific Details

For language-specific implementation details, see:
- [Python Guide](../language-guides/python/index.md)

## See Also

- [Operations](../operations/index.md)
- [Best Practices](../best-practices/index.md)
- [Reference](../reference/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
