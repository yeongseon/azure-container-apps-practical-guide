# How Azure Container Apps Works

Azure Container Apps is a managed platform for running containerized applications without managing Kubernetes clusters directly. You provide container images and runtime settings; Azure operates the orchestration, ingress, scaling, and patching layers.

## Platform Architecture

At a high level, Container Apps separates **control-plane operations** (configuration, deployment, policy) from the **runtime data plane** (routing, revisions, replicas).

```mermaid
graph LR
    U[Developer / CI] --> ARM[Azure Resource Manager API]
    ARM --> CP[Container Apps Control Plane]
    CP --> ENV[Container Apps Environment]

    subgraph ENV[Container Apps Environment]
      IN[Envoy Ingress]
      APP1[Container App A\nRevision v1/v2]
      APP2[Container App B\nBackground worker]
      DAPR[Dapr Sidecars optional]
    end

    IN --> APP1
    IN --> APP2
    APP1 -.-> DAPR
    APP2 -.-> DAPR
```

## Core Building Blocks

### Environment

An environment is the regional boundary where apps share networking, observability integration, and platform runtime.

### Container App

A container app is a deployment unit with one or more containers and policies for ingress, scale, and revisions.

### Revision

Each configuration or image change creates an immutable revision. You can run one active revision (simple mode) or multiple active revisions (progressive delivery).

### Replica

A revision scales to replicas based on KEDA rules, HTTP demand, and min/max replica settings.

## Request and Deployment Lifecycle

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Azure as Control Plane
    participant Ingress as Envoy Ingress
    participant Rev1 as Revision v1
    participant Rev2 as Revision v2

    Dev->>Azure: Deploy new image/config
    Azure->>Rev2: Create new immutable revision
    Ingress->>Rev1: Route 90% traffic
    Ingress->>Rev2: Route 10% traffic
    Note over Rev2: Observe errors/latency
    Ingress->>Rev2: Shift toward 100% if healthy
```

This revision model enables low-risk rollouts and fast rollback without rebuilding infrastructure.

## Built-in Platform Capabilities

- **KEDA autoscaling** for event- and metrics-driven scaling.
- **Revision and traffic splitting** for canary and blue/green delivery.
- **Managed certificates** for HTTPS custom domains without manual certificate lifecycle tasks.
- **Dapr integration (optional)** for service invocation, pub/sub, state, and bindings.

## Practical Example: Choosing Runtime Features by App Type

| App Type | Recommended Features | Why |
|---|---|---|
| Public API | Ingress + managed cert + HTTP scale rules | Secure endpoint, automatic scale on traffic |
| Background worker | No public ingress + queue-based KEDA scaler | Event-driven processing with cost control |
| Microservice mesh | Internal ingress + Dapr service invocation | Simplifies service-to-service patterns |

## Advanced Topics

- Control-plane update behavior and revision churn management.
- Sidecar patterns beyond Dapr (observability/security proxies).
- Multi-region deployment with independent environments.

## See Also

- [Environments and Apps](./environments-and-apps.md)
- [Scaling with KEDA](./scaling-keda.md)
- [Networking](./networking.md)
- [Container Apps vs Others](./container-apps-vs-others.md)
- [Revision Management and Traffic Splitting](../tutorial/07-revisions-traffic.md)
