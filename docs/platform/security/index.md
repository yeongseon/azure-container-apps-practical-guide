---
content_sources:
  diagrams:
    - id: security-architecture-overview
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/security
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
        - https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/policy-reference
    - id: no-ingress-not-http-addressable-event-driven
      type: flowchart
      source: self-generated
      justification: Decision flow synthesized from Microsoft Learn to keep disabled ingress, internal app ingress, external app ingress, continuously running event workers, and finite job executions distinct.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/connect-apps
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/jobs
        - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
    - id: container-apps-provides-a-built-in-authentication
      type: sequence
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/security
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
        - https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/policy-reference
    - id: dapr-sidecar-enables-automatic-mtls-for
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/security
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
        - https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/policy-reference
    - id: microsoft-defender-for-containers-provides-continuous
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/security
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
        - https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/policy-reference
    - id: least-privilege-assignment-pattern
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/security
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
        - https://learn.microsoft.com/en-us/azure/container-apps/authentication
        - https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction
        - https://learn.microsoft.com/en-us/azure/role-based-access-control/overview
        - https://learn.microsoft.com/en-us/azure/container-apps/policy-reference
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: App ingress visibility and environment accessibility are separate settings; external app ingress on an internal environment does not create public internet reachability.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
    - claim: An app with ingress disabled has no direct app-ingress endpoint, but a Dapr-enabled no-ingress app can still receive Dapr service invocation from other Dapr-enabled apps.
      source: https://learn.microsoft.com/en-us/azure/container-apps/connect-apps
      verified: true
    - claim: Container Apps jobs run finite executions triggered manually, on a schedule, or by events, and jobs do not support ingress.
      source: https://learn.microsoft.com/en-us/azure/container-apps/jobs
      verified: true
    - claim: Workload profiles environments support user-defined routes, NAT Gateway egress, and environment private endpoints; legacy Consumption-only environments do not support those features.
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: true
---
# Security in Azure Container Apps

Azure Container Apps provides multiple layers of security — from network isolation and identity-based access to image integrity and data protection. This page consolidates the security architecture into a single reference, connecting the topics covered in networking, identity, and operations sections.

## Security Architecture Overview

<!-- diagram-id: security-architecture-overview -->
```mermaid
flowchart TB
    subgraph External ["External Boundary"]
        U[Internet Client]
        AD[Microsoft Entra ID]
    end

    subgraph Azure ["Azure Subscription"]
        subgraph Env ["Azure-managed Container Apps Environment"]
            ING[Managed ingress proxy]
            APP1[App: External Ingress]
            APP2[App: Internal Ingress]
            SC[Sidecar - Dapr mTLS]
        end

        subgraph VNet ["Customer Virtual Network"]
            Subnet["Dedicated environment subnet relationship"]

            subgraph PESubnet ["Private Endpoint Subnet"]
                PE1["PE: Key Vault"]
                PE2["PE: Storage"]
                PE3["PE: ACR"]
            end

            FW[Azure Firewall / NVA]
        end

        subgraph Services ["Platform Services"]
            KV[Azure Key Vault]
            ACR[Azure Container Registry]
            ST[Azure Storage]
            DEF[Microsoft Defender for Containers]
        end

        RBAC[Azure RBAC]
    end

    U -- "1. HTTPS + TLS 1.2" --> ING
    ING -- "2. Easy Auth / JWT" --> AD
    ING --> APP1
    APP1 -- "3. mTLS via Dapr" --> SC
    SC --> APP2
    APP1 -- "4. Managed Identity" --> PE1
    APP1 -- "4. Managed Identity" --> PE2
    ACR -- "5. Image Pull via MI" --> Env
    DEF -- "6. Vulnerability findings" --> ACR
    FW -- "7. Egress Filter" --> Env
    RBAC -- "8. Control Plane" --> Env
```

Each numbered path represents a security control layer:

| # | Layer | Control |
|---|---|---|
| 1 | Transport | TLS 1.2 enforced at managed ingress |
| 2 | Authentication | Easy Auth or custom JWT validation |
| 3 | Service-to-service | mTLS via Dapr sidecar |
| 4 | Resource access | Managed identity with least-privilege RBAC |
| 5 | Image pull | Managed identity authentication to ACR |
| 6 | Image integrity | Vulnerability scanning via Defender for Containers |
| 7 | Egress | Outbound filtering via Azure Firewall or UDR |
| 8 | Control plane | Azure RBAC for management operations |

## Security Deep Dives

Use these focused pages when you need implementation details for a specific security domain:

- [Image Security](image-security.md) — registry authentication, revision-time pulls, and vulnerability scanning scope.
- [Secrets](secrets.md) — inline secrets, Key Vault references, `secretRef`, and refresh behavior.
- [Network Isolation](network-isolation.md) — internal environments, private endpoints, NSG/UDR, ingress posture, and egress control.
- [Customer-Managed Keys](customer-managed-keys.md) — current documented CMK status and Key Vault-related alternatives.

## Network Isolation

Network isolation combines distinct environment-accessibility, app-ingress, VNet, private-connectivity, DNS, subnet-control, and egress decisions. No single setting supplies every boundary.

### Ingress Boundary

First decide whether the workload needs a **direct Container Apps HTTP or TCP ingress endpoint**. If it does, keep the app-level ingress setting separate from the environment's accessibility:

- **External app ingress** publishes the app at the environment inbound boundary. That boundary can be public, an internal load balancer, or a private endpoint, so `external: true` does not by itself mean internet reachable.
- **Internal app ingress** makes the app's own FQDN directly reachable only from the same Container Apps environment by default. It is not the setting for VNet-wide access; an environment-level HTTP route can also explicitly target it.
- **Disabled app ingress** creates no direct FQDN or app-name ingress endpoint. A Dapr-enabled app can still receive Dapr service invocation from other Dapr-enabled apps in the environment.
- **Container Apps jobs** are separate finite-execution resources. They support neither ingress nor Dapr, but a running job can make outbound app-to-app calls. Jobs run manually, on a schedule, or in response to events.

**Takeaway:** No ingress and internal ingress are not synonyms. Internal ingress provides an environment-local direct endpoint; disabled app ingress provides no direct app-ingress endpoint, while Dapr invocation remains a separate optional path.

<!-- diagram-id: no-ingress-not-http-addressable-event-driven -->
```mermaid
flowchart TD
    accTitle: Choose direct ingress, Dapr-only invocation, or a Container Apps job
    accDescr: A decision flow separates workloads that need a direct Container Apps HTTP or TCP endpoint from apps without direct ingress and finite jobs. Direct endpoints use external or internal app ingress. A no-ingress app can optionally receive Dapr service invocation, while jobs support neither ingress nor Dapr.

    NEED{"Need a direct Container Apps<br/>HTTP or TCP endpoint?"}
    CALLERS{"Who must directly reach<br/>the app?"}
    EXT["External app ingress<br/>external: true"]
    ENV_BOUNDARY["Environment accessibility<br/>public, internal load balancer,<br/>or private endpoint"]
    INT["Internal app ingress<br/>external: false"]
    SAME_ENV["Direct app FQDN access<br/>from the same environment"]

    FINITE{"Finite execution that<br/>runs to completion?"}
    WORKER["Container app<br/>app ingress disabled"]
    DAPR{"Receive Dapr<br/>service invocation?"}
    DAPR_ONLY["Dapr-enabled app<br/>no direct app-ingress endpoint"]
    EVENT_ONLY["Worker or event processor<br/>no direct app-ingress endpoint"]
    JOB["Container Apps job<br/>no ingress and no Dapr"]
    TRIGGER["Manual, schedule,<br/>or event trigger"]

    NEED -->|"Yes"| CALLERS
    CALLERS -->|"Environment boundary callers"| EXT
    EXT --> ENV_BOUNDARY
    CALLERS -->|"Same environment only"| INT
    INT --> SAME_ENV

    NEED -->|"No"| FINITE
    FINITE -->|"No, run continuously"| WORKER
    WORKER --> DAPR
    DAPR -->|"Yes"| DAPR_ONLY
    DAPR -->|"No"| EVENT_ONLY
    FINITE -->|"Yes"| JOB
    TRIGGER --> JOB

    LEGEND["Decision key<br/>external/internal = direct app ingress<br/>Dapr invocation = separate sidecar path<br/>jobs support neither ingress nor Dapr"]
```

*Figure: This decision view intentionally does not consume the architecture topology base: its purpose is to choose a workload and ingress posture, not to trace the managed ingress-to-replica request path.*

An event-driven app with ingress disabled can scale on a custom KEDA-backed rule. If it has neither such a rule nor `minReplicas` of at least `1`, it can scale to zero without a signal that starts it again. A Dapr-enabled no-ingress app remains invocable through Dapr's separate service-invocation path. An event-driven job instead uses a custom scaler to determine how many finite job executions to start; jobs do not support Dapr or ingress.

!!! warning "Internal-only environments for sensitive workloads"
    Create the environment as internal to remove its public endpoint. A VNet client reaches an app through that internal environment boundary only when the app uses external app ingress; internal app ingress remains directly reachable only from the same environment unless an environment-level HTTP route targets it. Put a controlled gateway in front only when the design requires an entry path.

### VNet Integration

With a custom VNet, the environment uses a dedicated subnet relationship. Keep the Azure-managed logical environment separate from the customer-managed VNet in architecture diagrams. The relationship enables:

- Private endpoint access to Azure services (Key Vault, Storage, SQL, ACR).
- DNS resolution through Azure Private DNS Zones.
- Subnet-level Network Security Groups (NSGs) for additional filtering.

### Egress Filtering

In workload profiles environments, control outbound traffic using user-defined routes (UDRs) and Azure Firewall:

- Route all outbound traffic through a central firewall.
- Allow-list required FQDNs and service tags for platform dependencies.
- Audit outbound connections for compliance.

!!! note "Platform dependency FQDNs"
    Overly restrictive egress rules break image pulls, telemetry upload, and control-plane communication. Always validate with a canary app before enforcing strict egress policies.

For detailed networking configuration, see [Networking Overview](../networking/index.md).

## Authentication and Authorization

### Easy Auth (Built-in Authentication)

Container Apps provides a built-in authentication layer (Easy Auth) that validates tokens before requests reach application code:

<!-- diagram-id: container-apps-provides-a-built-in-authentication -->
```mermaid
sequenceDiagram
    participant C as Client
    participant E as Envoy Ingress
    participant A as Easy Auth Middleware
    participant App as Container App

    C->>E: HTTPS Request
    E->>A: Forward to auth layer
    A->>A: Validate token with Entra ID
    alt Token valid
        A->>App: Forward authenticated request
        App->>C: 200 OK
    else Token invalid
        A->>C: 401 Unauthorized
    end
```

Easy Auth supports Microsoft Entra ID, Facebook, GitHub, Google, X, and custom OpenID Connect providers. The platform authentication middleware runs as a sidecar on each replica when enabled; the sequence above is a logical request flow rather than a physical claim that authentication is part of the ingress proxy.

!!! tip "When to use Easy Auth vs custom auth"
    Use Easy Auth for standard identity provider flows with minimal code. Use custom JWT validation when you need fine-grained claims inspection, multi-tenant logic, or non-standard token formats.

### API Key and Header-Based Access

For service-to-service calls that do not use identity tokens, validate API keys or custom headers at the application level. Store keys in Key Vault and reference them as managed secrets.

### Mutual TLS (mTLS)

Dapr service invocation provides automatic mTLS between Dapr sidecars for Dapr-enabled apps. This is separate from the optional environment-level peer-to-peer encryption feature, which can encrypt network traffic within the environment for direct app communication:

<!-- diagram-id: dapr-sidecar-enables-automatic-mtls-for -->
```mermaid
flowchart TD
    subgraph Env ["Container Apps Environment"]
        subgraph A ["App A"]
            A_APP[Application Code]
            A_DAPR[Dapr Sidecar]
        end

        subgraph B ["App B"]
            B_DAPR[Dapr Sidecar]
            B_APP[Application Code]
        end
    end

    A_APP -- "HTTP localhost" --> A_DAPR
    A_DAPR -- "mTLS encrypted" --> B_DAPR
    B_DAPR -- "HTTP localhost" --> B_APP
```

Key properties of Dapr mTLS in Container Apps:

- Certificates are automatically rotated by the platform.
- Encryption is transparent to application code — apps communicate over localhost to their sidecar.
- mTLS applies to all Dapr-enabled service invocations within the environment.

!!! warning "mTLS requires Dapr enablement"
    Dapr service-invocation mTLS requires Dapr on both caller and callee. For direct app-to-app traffic, use the separate environment peer-to-peer encryption setting when that path needs platform-managed TLS; Microsoft Learn documents that peer-to-peer encryption is disabled by default.

## Image Security

### Container Registry Authentication

Use managed identity for image pulls instead of admin credentials:

| Method | Security Posture | Recommendation |
|---|---|---|
| Admin credentials | Shared password, no audit trail | Avoid in production |
| Service principal | Requires secret rotation | Acceptable with rotation policy |
| Managed identity | Passwordless, auditable, auto-rotated | Recommended |

### Vulnerability Scanning

Microsoft Defender for Cloud vulnerability assessment can assess images stored in Azure Container Registry. Treat assessment findings as evidence for a promotion decision; the cited documentation does not establish that Defender directly blocks a Container Apps deployment:

<!-- diagram-id: microsoft-defender-for-containers-provides-continuous -->
```mermaid
flowchart TD
    DEV[Developer] -- "Push image" --> ACR[Azure Container Registry]
    ACR -- "Scan on push" --> DEF[Defender for Containers]
    DEF -- "Vulnerability report" --> SEC[Security Team]
    DEF -- "Review critical CVEs" --> POL[Promotion policy]
    ACR -- "Pull approved image" --> ENV[Container Apps Environment]
```

Interpret this existing overview as an assessment-and-promotion concept rather than a literal enforcement path:

- **Registry assessment**: Defender for Cloud provides vulnerability assessment for images stored in ACR.
- **Posture evidence**: security recommendations and findings help teams prioritize remediation.
- **Promotion control**: CI/CD or release governance can use those findings as an input; do not assume assessment alone blocks a Container Apps deployment.

### Trusted Image Practices

- Use specific image tags or digests — never `latest` in production.
- Verify signed images with a current registry and deployment-policy mechanism appropriate to your supply chain; do not assume legacy Docker Content Trust is enforced by Container Apps.
- Restrict ACR network access with private endpoints and firewall rules.
- Maintain a base image update cadence to patch OS-level vulnerabilities.

## Role-Based Access Control (RBAC)

Azure RBAC controls who can manage Container Apps resources at the control plane level.

### Built-in Roles for Container Apps

| Role | Scope | Permissions |
|---|---|---|
| Contributor | Resource Group | Full management of Container Apps resources |
| Container Apps Contributor | Resource / RG | Manage Container Apps resources; review the current role definition before assignment |
| Reader | Resource Group | View Container Apps configuration and status |
| Monitoring Reader | Resource Group | View metrics and logs |

### Least-Privilege Assignment Pattern

<!-- diagram-id: least-privilege-assignment-pattern -->
```mermaid
flowchart TD
    subgraph Roles ["RBAC Assignment Strategy"]
        ADMIN[Platform Admin] -- "Contributor on RG" --> RG[Resource Group]
        DEV[Developer] -- "Container Apps Contributor" --> APP[Container App]
        SRE[SRE / Ops] -- "Monitoring Reader + Log Analytics Reader" --> MON[Monitoring Resources]
        CI[CI/CD Pipeline] -- "Container Apps Contributor + AcrPush" --> DEPLOY[Deployment Scope]
    end
```

Principles:

- Assign roles at the narrowest scope possible (resource level over resource group).
- Use custom roles when built-in roles are too broad.
- Review role assignments quarterly — remove unused assignments.
- Separate deployment permissions (CI/CD) from runtime permissions (managed identity).

### Portal view: Access control (IAM) blade

![Access control IAM blade for a Container App showing the Check access tab with Grant access View access and View deny assignments cards and the Roles tab label](../../assets/platform/identity-and-secrets/04-iam-blade.png)

[Observed] The blade is `<your-app-name> | Access control (IAM)` with the subtitle `Container App`. Four tabs are rendered along the top: `Check access`, `Role assignments`, `Roles`, and `Deny assignments`. The `Check access` tab is selected. The tab body shows three cards titled `Grant access to this resource` (with an `Add role assignment` button), `View access to this resource` (with a `View` button), and `View deny assignments` (with a `View` button). Above the cards, a `My access` section exposes a `View my access` button and a `Check access` section exposes a `Check access` button. The command bar includes `+ Add`, `Download role assignments`, `Edit columns`, `Refresh`, `Delete`, and `Feedback`. The left navigation lists `Application`, `Settings`, `Networking`, `Security`, `Monitoring`, `Automation`, and `Help` groups.

[Inferred] The `Grant access to this resource` card with its `Add role assignment` button is consistent with the per-resource scoping that the [Least-Privilege Assignment Pattern](#least-privilege-assignment-pattern) diagram describes — RBAC bindings created at the Container App resource rather than at the resource group. The `Roles` tab label is consistent with the catalog framing in the [Built-in Roles for Container Apps](#built-in-roles-for-container-apps) table, which lists `Contributor`, `Container Apps Contributor`, `Reader`, and `Monitoring Reader` as the principal role choices an operator would pick from. The presence of a `Deny assignments` tab alongside `Role assignments` is consistent with this page's broader RBAC framing as both an allow surface and an exception surface.

[Not Proven] This image does not show the contents of the `Role assignments`, `Roles`, or `Deny assignments` tabs, so the actual list of principals, the actual catalog of built-in and custom roles, and any existing deny rules are not visible here. No secondary pane, dialog, or result panel is rendered in this capture, so any controls beyond the buttons and labels shown here are outside the scope of this image.

## Data Protection

### Encryption at Rest

- Azure Container Apps uses platform-managed encryption for service-managed data and configuration.
- Secrets stored in Container Apps configuration are encrypted at rest, but broad management roles can include secret-reading actions; review role definitions before assignment.
- Key Vault references keep the source secret in Key Vault and let the app resolve it by managed identity. They are not the same as configuring customer-managed encryption keys for Container Apps service-managed storage.

### Encryption in Transit

| Path | Encryption | Managed By |
|---|---|---|
| Client → Ingress | TLS 1.2 or 1.3 at HTTP ingress | Platform |
| Ingress → App | Internal traffic; optionally encrypted by environment peer-to-peer encryption | Platform |
| App → App (Dapr) | mTLS | Dapr sidecar |
| App → Azure Services (PE) | Service protocol over a Private Link path; application-layer TLS depends on the service | Application + Private Endpoint |
| App → External APIs | TLS as required by the destination | Application code |

### Secret Management

Container Apps supports two secret storage patterns:

1. **Platform secrets**: stored in Container Apps configuration, referenced as environment variables.
2. **Key Vault references**: secrets resolved from Key Vault by using managed identity and exposed to the app through Container Apps secret configuration.

!!! tip "Prefer Key Vault references for production"
    Key Vault references centralize the source secret and its access control. Verify the documented refresh behavior and application restart requirements for your secret-consumption pattern instead of assuming rotation is immediate.

For secret management details, see [Key Vault Integration](../identity-and-secrets/key-vault.md).

## Compliance and Governance

### Azure Policy for Container Apps

Azure Policy enforces organizational security standards:

- Require VNet integration for all environments.
- Require managed identity (block admin credential usage for ACR).
- Require HTTPS-only ingress.
- Block external ingress for sensitive workloads.
- Audit or deny insecure HTTP ingress by requiring HTTPS-only configuration.

### Audit and Monitoring

Security-relevant events are captured in:

- **Azure Activity Log**: control-plane operations (create, update, delete).
- **Container Apps system logs**: runtime events, restarts, probe failures.
- **Application Insights**: request traces, dependency calls, exceptions.
- **Identity-provider and application logs**: use the configured provider's sign-in evidence plus application or authentication diagnostics; do not assume every Easy Auth event appears in one log without configuring and verifying that source.

!!! warning "Enable diagnostic settings"
    Without diagnostic settings configured, security events are not retained beyond platform defaults. Configure Log Analytics workspace integration for all Container Apps environments.

## Advanced Topics

- Zero-trust architecture patterns with internal environments and private endpoints end-to-end.
- Workload identity federation for cross-cloud and GitHub Actions OIDC deployments.
- Runtime security monitoring with Microsoft Defender for Cloud integration.
- Network micro-segmentation using multiple environments with separate VNets.
- Automated compliance scanning with Azure Policy initiatives.

## See Also

- [Networking Overview](../networking/index.md)
- [VNet Integration](../networking/vnet-integration.md)
- [Private Endpoints](../networking/private-endpoints.md)
- [Egress Control](../networking/egress-control.md)
- [Managed Identity](../identity-and-secrets/managed-identity.md)
- [Key Vault Integration](../identity-and-secrets/key-vault.md)
- [Easy Auth](../identity-and-secrets/easy-auth.md)
- [Security Operations](../identity-and-secrets/security-operations.md)
- [Image Security](image-security.md)
- [Secrets](secrets.md)
- [Network Isolation](network-isolation.md)
- [Customer-Managed Keys](customer-managed-keys.md)
- [Security Best Practices](../../best-practices/security.md)
- [Image Security Best Practices](../../best-practices/image-security.md)
- [Compliance Baseline](../../best-practices/compliance-baseline.md)

## Sources

- [Security in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/security)
- [Networking in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Managed Identity in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Authentication and Authorization in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Microsoft Defender for Containers (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction)
- [Azure RBAC Overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
- [Azure Policy for Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/policy-reference)
- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Jobs in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/jobs)
- [Scaling in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Configure environment ingress and peer-to-peer encryption (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration)
