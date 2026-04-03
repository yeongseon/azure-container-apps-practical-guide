# Concepts: Understanding Azure Container Apps

This section explains **how Azure Container Apps works** so you can make better design decisions before writing deployment scripts.

Use these concept guides to understand platform behavior (revisions, scaling, ingress, environments) and choose the right architecture for production workloads.

## Concept Map

```mermaid
graph TD
    A[Azure Container Apps Fundamentals] --> B[How Container Apps Works]
    A --> C[Environments and Apps]
    A --> D[Scaling with KEDA]
    A --> E[Networking]
    A --> F[Container Apps vs Other Services]

    B --> B1[Control plane vs data plane]
    B --> B2[Revisions and traffic splitting]
    B --> B3[Dapr and managed runtime]

    C --> C1[Consumption vs Workload profiles]
    C --> C2[Environment boundaries]

    D --> D1[Event-driven autoscaling]
    D --> D2[Scale rules and limits]

    E --> E1[Ingress and Envoy]
    E --> E2[Service discovery]
    E --> E3[VNet integration]

    F --> F1[AKS]
    F --> F2[App Service]
    F --> F3[ACI]
    F --> F4[Functions]
```

## Who Should Read This

- Teams moving from App Service or AKS to Container Apps.
- Developers planning revision-based rollouts.
- Platform engineers designing network boundaries and autoscaling behavior.

## How to Use This Section

1. Start with [How Container Apps Works](./how-container-apps-works.md).
2. Read [Environments and Apps](./environments-and-apps.md) before provisioning.
3. Review [Scaling with KEDA](./scaling-keda.md) and [Networking](./networking.md) for production architecture.
4. Use [Container Apps vs Others](./container-apps-vs-others.md) for platform selection decisions.

## Advanced Topics

- Multi-environment topology (dev/stage/prod isolation patterns).
- Cost and performance tuning with workload profiles.
- Progressive delivery using revisions and weighted traffic.

## See Also
- [How Container Apps Works](./how-container-apps-works.md)
- [Environments and Apps](./environments-and-apps.md)
- [Scaling with KEDA](./scaling-keda.md)
- [Networking](./networking.md)
- [Container Apps vs Others](./container-apps-vs-others.md)
- [Revision Management and Traffic Splitting](../tutorial/07-revisions-traffic.md)
