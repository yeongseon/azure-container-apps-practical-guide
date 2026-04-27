---
content_sources:
  diagrams:
    - id: architecture-overview
      type: flowchart
      source: self-generated
      justification: "Synthesized from Microsoft Learn pages on Container Apps overview, environments, networking, scaling, revisions, and Dapr integration"
      based_on:
        - https://learn.microsoft.com/azure/container-apps/overview
        - https://learn.microsoft.com/azure/container-apps/environment
        - https://learn.microsoft.com/azure/container-apps/networking
        - https://learn.microsoft.com/azure/container-apps/scale-app
        - https://learn.microsoft.com/azure/container-apps/revisions
        - https://learn.microsoft.com/azure/container-apps/dapr-overview
    - id: control-data-plane
      type: flowchart
      source: self-generated
      justification: "Synthesized from Microsoft Learn pages distinguishing management operations from runtime traffic"
      based_on:
        - https://learn.microsoft.com/azure/container-apps/overview
        - https://learn.microsoft.com/azure/container-apps/environment
content_validation:
  status: verified
  last_reviewed: "2026-04-27"
  reviewer: agent
  core_claims:
    - claim: "Azure Container Apps is powered by KEDA for autoscaling."
      source: https://learn.microsoft.com/azure/container-apps/scale-app
      verified: true
    - claim: "Container Apps uses an HTTP edge proxy (Envoy) that terminates TLS and routes requests."
      source: https://learn.microsoft.com/azure/container-apps/networking
      verified: true
    - claim: "A Container Apps environment is a secure boundary that manages OS upgrades, scale operations, failover procedures, and resource balancing."
      source: https://learn.microsoft.com/azure/container-apps/environment
      verified: true
    - claim: "Dapr integration provides service-to-service invocation, state management, and pub/sub messaging."
      source: https://learn.microsoft.com/azure/container-apps/dapr-overview
      verified: true
---

# How Container Apps Works

Azure Container Apps is a serverless container platform built on a managed, Kubernetes-based environment. This page provides the mental model you need for design reviews, deployment decisions, and production troubleshooting.

## Architecture at a Glance

<!-- diagram-id: architecture-overview -->
```mermaid
flowchart TD
    Deploy["Developer or CI/CD pipeline"]
    Client["Client or API consumer"]
    Events["Event sources<br/>Queues, Event Hubs, timers"]

    subgraph Control["Control plane"]
        ARM["Azure Resource Manager"]
        RP["Container Apps resource provider"]
    end

    subgraph Env["Container Apps environment"]
        Ingress["Envoy ingress proxy<br/>TLS termination and routing"]
        Scale["KEDA-based autoscaling"]
        Profiles["Workload profiles<br/>Consumption or Dedicated"]

        subgraph App["Container App"]
            RevA["Revision A<br/>Replicas"]
            RevB["Revision B<br/>Replicas"]
            Dapr["Dapr sidecar<br/>optional"]
        end
    end

    Logs["Azure Monitor<br/>Log Analytics"]
    Services["External services<br/>Databases, storage, APIs"]

    Deploy --> ARM --> RP
    RP --> Env
    Client --> Ingress
    Ingress --> RevA
    Ingress -. "weighted traffic" .-> RevB
    Events --> Scale
    Scale --> RevA
    Scale --> RevB
    Profiles --> RevA
    Profiles --> RevB
    RevA -. "sidecar" .- Dapr
    RevA --> Services
    RevA --> Logs
```

- The control plane starts when you deploy or update a container app through Azure Resource Manager, the Azure portal, the CLI, Bicep, or Terraform.
- The data plane starts when traffic reaches the environment's HTTP edge proxy, which terminates TLS and routes requests to the active revision and its replicas.
- The environment is the secure boundary for your apps and manages shared platform responsibilities such as workload placement, upgrades, failover, and resource balancing.
- Revisions are immutable deployment snapshots, so a single app can have multiple versions active at the same time for testing or weighted traffic rollout.
- Scaling is event-driven: HTTP traffic, TCP connections, CPU or memory thresholds, and external event sources can all influence replica count through the platform's KEDA-powered scaling model.

## Control Plane vs Data Plane

<!-- diagram-id: control-data-plane -->
```mermaid
flowchart TD
    subgraph CP["Control plane<br/>What you configure"]
        A1["Azure Portal, CLI, ARM, Bicep"]
        A2["App creation and deletion"]
        A3["Revision deployment"]
        A4["Scaling rules"]
        A5["Identity and RBAC assignment"]
        A6["Networking and ingress config"]
    end

    subgraph DP["Data plane<br/>What runs at runtime"]
        B1["Envoy ingress proxy"]
        B2["Container execution<br/>Replicas"]
        B3["KEDA scale decisions"]
        B4["Dapr service invocation"]
        B5["Log and metric collection"]
        B6["Health probes"]
    end

    CP --> DP
```

Understanding the split between management and runtime behavior helps you troubleshoot faster. If an app cannot be created, updated, or granted access, the problem usually starts in the control plane. If the app deploys successfully but returns 5xx responses, fails health probes, or scales unexpectedly, the problem is usually in the data plane.

| Operation | Plane | Why it belongs there |
|---|---|---|
| Create a Container Apps environment | Control plane | This is an Azure resource management action handled through Azure Resource Manager and the resource provider. |
| Assign a managed identity | Control plane | Identity assignment and RBAC are configuration-time management operations. |
| Configure ingress mode and target port | Control plane | Ingress settings are stored as app configuration and applied by the platform. |
| Deploy a new revision | Control plane | A revision is created from a configuration or template change. |
| Route external HTTPS traffic to a replica | Data plane | This is runtime traffic handled by the HTTP edge proxy inside the environment. |
| Run startup, liveness, and readiness probes | Data plane | Probe execution happens against running containers. |
| Scale from zero to one replica after an event | Data plane | Runtime signals are evaluated by the platform's KEDA-powered scaling path. |
| Invoke another service through Dapr | Data plane | Service invocation happens between running workloads at request time. |
| Collect app logs and metrics | Data plane | Observability signals are emitted from active runtime components and forwarded to monitoring backends. |

## Control Plane

The control plane is the configuration and orchestration layer for Azure Container Apps. It is where you declare desired state and where Azure applies platform-managed operations to reach that state.

### What the control plane does

- Accepts resource creation and update requests through Azure Resource Manager.
- Stores app configuration such as image reference, ingress settings, secrets references, environment variables, scale rules, and revision mode.
- Creates new immutable revisions when you change revision-scope settings.
- Applies identity configuration, including system-assigned or user-assigned managed identity settings.
- Enforces access checks for management operations through Azure RBAC.
- Coordinates environment-level configuration such as networking boundaries, workload profiles, certificates, and diagnostics settings.

### Why control-plane issues matter operationally

Many production incidents begin before a single request reaches your application code. Common examples include:

- A deployment fails because the caller lacks permission to update the container app.
- A new revision never becomes healthy because the platform cannot pull the image or resolve referenced secrets.
- A managed identity exists, but the required RBAC role assignment was never created on the downstream resource.
- Ingress was configured as internal when the expectation was public access.

These are control-plane failures because the platform cannot establish the desired runtime state. They are the right place to investigate when the Azure portal, CLI, ARM deployment output, or activity logs show errors before traffic is served.

### Typical control-plane artifacts

| Artifact | Scope | Example questions |
|---|---|---|
| Container app resource | App | Which image, revision mode, scale rules, and ingress settings are configured? |
| Container Apps environment | Shared boundary | Which apps share the same environment, logging backend, and network boundary? |
| Managed identity | App or shared | Which principal is used to access Azure resources? |
| RBAC assignment | Azure resource | Does the identity have the required role on Key Vault, Storage, or Container Registry? |
| Revision definition | App version | What changed between the last healthy revision and the failing one? |

!!! note "Think of the control plane as declared intent"
    The control plane describes what should exist and how it should be configured.
    If Azure cannot converge the runtime to that declared state, troubleshoot management permissions,
    referenced resources, identity bindings, and deployment configuration before analyzing request traffic.

## Data Plane

The data plane is the runtime path that handles live application traffic, background events, container execution, and telemetry. Once a revision is active, most user-visible behavior happens here.

### Core runtime components

- **HTTP edge proxy**: Microsoft Learn documents an HTTP edge proxy built on Envoy. It terminates TLS for inbound HTTPS traffic and routes requests to the correct app revision.
- **Replicas**: A revision runs as one or more replicas. Each replica hosts your container and, when enabled, sidecars such as Dapr.
- **Scaling path**: Azure Container Apps is powered by KEDA for autoscaling. HTTP traffic, CPU, memory, TCP, and event-driven rules can all affect scale decisions.
- **Internal service connectivity**: Microsoft Learn documents that Envoy also routes internal traffic inside clusters, which matters for internal ingress and service-to-service patterns.
- **Observability pipeline**: Logs, console output, and metrics are emitted from runtime components and can be sent to Azure Monitor and Log Analytics.

### Typical data-plane symptoms

- Requests return 502, 503, or 504 even though deployment completed successfully.
- Health probes fail and the replica is restarted.
- Replica count oscillates unexpectedly under burst traffic.
- Event-driven scale-out does not happen because the queue trigger or scaler target is misconfigured.
- Dapr-based service invocation or pub/sub messaging fails while the app itself remains deployable.

### Data-plane troubleshooting questions

| Question | Why it matters |
|---|---|
| Did traffic reach the environment ingress endpoint? | Separates DNS, certificate, and client path issues from application issues. |
| Which revision received traffic? | Traffic splitting and multiple active revisions can hide version-specific failures. |
| Were replicas created and kept healthy? | A scaling success can still fail at readiness or runtime initialization. |
| Did the app fail before or after request routing? | Distinguishes ingress behavior from container behavior. |
| Are downstream dependencies slow or unavailable? | Many runtime symptoms are caused by databases, storage, APIs, or network egress dependencies. |

## Environment Internals

The Container Apps environment is the platform boundary that hosts one or more apps and jobs. Microsoft Learn describes it as a **secure boundary** around groups of container apps with shared networking, observability, and compute characteristics.

> "A container apps environment is a secure boundary around a group of container apps. Container Apps environments provide a secure boundary where Container Apps can run, and they manage OS upgrades, scale operations, failover procedures, and resource balancing."  
> — Microsoft Learn, *Environment in Azure Container Apps*

That definition is important because it explains what you do and do not manage:

- You manage app-level configuration, identities, secrets references, networking choices, and scaling rules.
- Azure manages the underlying platform lifecycle for the environment, including OS upgrades and balancing capacity across the managed, Kubernetes-based environment.
- Apps in the same environment share environment-level capabilities such as logging destinations, virtual network integration choices, and workload profiles.

### What the environment manages for you

| Platform concern | Managed by the environment | Operational impact |
|---|---|---|
| OS upgrades | Yes | You do not patch worker hosts directly. Platform maintenance happens beneath the app layer. |
| Scale operations | Yes | Replica placement and scale orchestration happen within the environment boundary. |
| Failover procedures | Yes | The platform handles infrastructure-level recovery mechanisms within its service design. |
| Resource balancing | Yes | Workloads are balanced according to the environment's available platform capacity and profile model. |
| Shared observability plumbing | Yes | Environment configuration determines how logs and diagnostics integrate with Azure Monitor or Log Analytics. |

### Why environment design matters

An environment is more than a deployment target. It is also a blast-radius boundary. Placing multiple apps in one environment can simplify service discovery and shared operations, but it also means those apps share:

- Environment-level networking posture.
- Logging and diagnostics configuration.
- Workload profile choices and some capacity characteristics.
- Operational dependency on the same environment lifecycle.

Use that mental model during architecture review: first decide which apps should share an environment, then decide how those apps expose ingress, consume identities, and connect to downstream services.

## Revision and Replica Model

Revisions are one of the most important architectural ideas in Azure Container Apps. Microsoft Learn defines revisions as immutable snapshots of an app version. When you change revision-scope settings, the platform creates a new revision instead of modifying the existing one in place.

### Why revisions exist

- They allow safe rollout of configuration and image changes.
- They preserve previous versions for rollback or side-by-side validation.
- They let you use single revision or multiple revision mode depending on release strategy.
- They support traffic splitting so you can direct percentages of traffic to different revisions.

### Revision lifecycle mental model

1. A deployment changes app configuration or template fields that affect revision state.
2. Azure Container Apps creates a new immutable revision.
3. The platform provisions replicas for that revision.
4. Health checks determine whether the new revision becomes ready.
5. Traffic is assigned based on revision mode and traffic rules.
6. Older revisions remain active, inactive, or deprovisioned according to your configuration and operational actions.

### Revision versus replica

| Concept | Meaning | Example |
|---|---|---|
| Revision | Immutable version of the app definition | `myapp--green` and `myapp--blue` |
| Replica | Running instance of a revision | Three running container instances of `myapp--green` |
| Traffic split | Percentage-based routing between active revisions | 90% to stable, 10% to canary |

!!! tip "Use revisions to isolate change risk"
    When a new version fails, compare the failing revision with the previous healthy revision first.
    Revisions give you a clean boundary for image, configuration, probe, and scale-rule changes.

## Scaling Model

Azure Container Apps is powered by KEDA for autoscaling. That phrasing matters because it explains why the platform can scale on more than CPU and memory alone. Container Apps can respond to runtime demand from HTTP traffic, TCP traffic, event sources, and other supported scaler types.

### Key scaling ideas

- **Scale to zero**: Consumption-based apps can scale down to zero when no work is present, then scale back out when a request or event arrives.
- **Event-driven scaling**: Queue depth, message backlogs, or other event signals can trigger additional replicas.
- **Resource-driven scaling**: CPU and memory thresholds can influence scale decisions for running workloads.
- **HTTP and TCP awareness**: Ingress traffic can participate in scaling behavior when the app is exposed through supported networking modes.

### Simplified scaling flow

1. A signal appears, such as HTTP requests, CPU pressure, or queue backlog.
2. The platform evaluates configured scale rules.
3. KEDA-powered scaling logic determines the desired replica count.
4. The environment provisions or removes replicas.
5. Health probes and readiness determine whether those replicas can serve live traffic.

### What scaling does not solve by itself

Scaling more replicas does not fix every issue. You can still have:

- Slow downstream databases that become the real bottleneck.
- Long cold-start or initialization paths that delay readiness.
- Probe failures caused by missing dependencies or wrong ports.
- Message handling patterns that are not idempotent under parallel scale-out.

## Networking Model

Networking in Azure Container Apps starts with the environment boundary and extends to ingress exposure, virtual network integration, internal service connectivity, and downstream egress paths.

### Ingress and request routing

Microsoft Learn documents an HTTP edge proxy based on Envoy. This proxy terminates TLS, enforces ingress decisions, and routes inbound requests to the correct app revision. That architecture explains several common behaviors:

- TLS termination happens at the ingress layer rather than inside each application container by default.
- Traffic can be routed to different revisions according to configured percentages.
- The ingress endpoint can be configured for external or internal reachability depending on design requirements.

### Internal and external exposure

| Mode | What it means | Common use case |
|---|---|---|
| External ingress | The app is reachable from outside the environment through its public endpoint or configured custom domain. | Public APIs, web front ends, webhook receivers |
| Internal ingress | The app is reachable only inside the environment or connected network boundary. | Private APIs, backend services, internal event processors |

### Virtual network integration

The environment can be integrated with a virtual network, which is the right level to think about networking design. Instead of asking only whether one app is private, ask these broader questions:

- Which environments require private address space and tighter east-west controls?
- Which downstream services require private connectivity?
- Which apps need only internal ingress because they are consumed by peer services rather than internet clients?

### Internal traffic inside the environment

Microsoft Learn notes that Envoy routes internal traffic inside clusters. In practice, that is useful for understanding internal ingress, service-to-service communication paths, and how requests can remain inside the platform boundary for private application topologies.

## Optional Platform Features

Not every architecture needs every platform feature. Azure Container Apps adds capabilities incrementally, so it helps to treat these as optional building blocks rather than default requirements.

### Dapr integration

Azure Container Apps supports Dapr integration for common distributed application patterns. Microsoft Learn documents Dapr support for:

- Service-to-service invocation
- State management
- Pub/sub messaging
- Bindings and actors scenarios, depending on component use

This feature is valuable when you want a consistent sidecar-based abstraction for service communication and eventing, but it also adds another runtime component to observe and troubleshoot.

### Jobs

Azure Container Apps also supports jobs for work that should run to completion instead of serving long-lived request traffic. Jobs are useful for:

- Scheduled processing
- Manual administrative execution
- Event-driven batch work

Architecturally, jobs share the Container Apps platform model but differ from apps in one key way: the primary unit of work is an execution that runs to completion, not an ingress-exposed service that continuously receives requests.

## Design Review Checklist

Use this page as a quick architecture review guide before you deploy a new workload:

- Have you separated control-plane concerns from data-plane runtime concerns?
- Is the environment boundary appropriate for the apps that will share networking, logging, and operational lifecycle?
- Do you understand which changes create a new revision and how rollback will work?
- Are scale rules aligned with real workload signals rather than guesses?
- Is ingress configured correctly for external versus internal exposure?
- Are identity and RBAC dependencies documented for every downstream Azure resource?
- If Dapr or Jobs are enabled, is the team prepared to operate those additional runtime patterns?

## See Also
- [Resource Relationships](resource-relationships.md)
- [Networking](../networking/index.md)
- [Scaling](../scaling/index.md)

## Sources
- [Azure Container Apps overview (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/overview)
- [Environment in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/environment)
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/networking)
- [Set scaling rules in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/scale-app)
- [Revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions)
- [Dapr integration in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/dapr-overview)
- [Managed identities in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/managed-identity)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/ingress-overview)
- [Jobs in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/jobs)
