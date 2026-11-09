---
content_sources:
  diagrams:
    - id: ingress-request-lifecycle
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint
    - id: ingress-decision-tree
      type: flowchart
      source: self-generated
      justification: Synthesized decision flow from Microsoft Learn ingress, networking, connect-apps, client certificate, and rule-based routing guidance.
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration
        - https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks
        - https://learn.microsoft.com/en-us/azure/container-apps/connect-apps
        - https://learn.microsoft.com/en-us/azure/container-apps/client-certificate-authorization
        - https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: External app ingress publishes an app at the environment inbound boundary; public internet reachability also depends on the environment virtual IP and public network access configuration.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
    - claim: An app with internal ingress is directly reachable only within its environment by default, but an environment-level HTTP route can target that app and provide an outside entry path.
      source: https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing
      verified: true
    - claim: Azure Container Apps supports transport values auto, http, http2, and tcp for ingress configuration.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to
      verified: true
    - claim: Azure Container Apps supports additional port mappings with a maximum of five additional ports per app, and externally exposed extra TCP ports must be unique across the environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
    - claim: The default request timeout for HTTP ingress is 240 seconds.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
---
# Ingress in Azure Container Apps

Azure Container Apps ingress controls how inbound traffic reaches a container app, whether that traffic comes from the public internet, callers in the same environment, or TCP clients. Use this page as the canonical ingress map, then follow the linked deep dives for VNet design, private exposure, service discovery, and revision traffic strategy.

## Overview

Azure Container Apps provides a managed ingress layer in front of your app. Microsoft Learn describes an HTTP edge proxy that terminates TLS at the edge, while the broader networking documentation also calls out Envoy for internal traffic routing inside the platform.

- Enable ingress when the app must accept inbound HTTP or TCP traffic.
- Disable ingress for event-driven workers, background processors, or jobs that should not accept inbound requests.
- Use the app's default FQDN or a custom domain when ingress is enabled.

!!! note "Document Envoy conservatively"
    Microsoft Learn explicitly documents the HTTP edge proxy and separately documents Envoy for internal routing inside Container Apps clusters. This page therefore refers to a managed ingress edge and avoids overstating that every ingress detail is directly documented as Envoy-based at the public edge.

**Takeaway:** Environment accessibility controls which callers can reach the managed entry point; app ingress and revision traffic settings then control how an accepted request reaches a replica.

<!-- diagram-id: ingress-request-lifecycle -->
```mermaid
flowchart TD
    accTitle: Azure Container Apps ingress request lifecycle
    accDescr: Internet, virtual network, private endpoint, and same-environment callers reach the managed environment only through allowed entry paths. The managed ingress proxy terminates TLS and selects replicas under revision traffic rules. Dotted arrows show app, revision, and replica membership or configuration rather than request traffic.

    INTERNET["Internet caller"]
    PRIVATE["Private caller<br/>VNet or private endpoint path"]
    INTERNAL["Same-environment caller"]
    CONFIG["Ingress configuration<br/>environment access, app exposure,<br/>revision traffic weights"]

    subgraph ENV["Managed Container Apps environment"]
        ENTRY["Allowed environment entry<br/>public or private"]
        INGRESS["Managed ingress proxy<br/>TLS and request routing"]
        APP["Container app<br/>logical grouping"]
        REV_ACTIVE["Active revision<br/>immutable app version"]
        REPLICAS["Revision replicas<br/>running instances"]
    end

    INTERNET ==>|"When public entry is enabled"| ENTRY
    PRIVATE ==>|"When private entry is configured"| ENTRY
    INTERNAL ==>|"Internal app call"| INGRESS
    ENTRY ==>|"Accepted inbound request"| INGRESS
    INGRESS ==>|"Select replica under revision traffic rules"| REPLICAS

    CONFIG -.->|"CONTROL: apply exposure and routing settings"| ENTRY
    CONFIG -.->|"CONTROL: apply app ingress policy"| INGRESS
    APP -.->|"Logical revision membership"| REV_ACTIVE
    REV_ACTIVE -.->|"Logical replica membership"| REPLICAS

    LEGEND["Arrow key<br/>thick = request path<br/>dotted = configuration or logical relationship"]
```

*Figure: Accepted ingress traffic crosses the environment entry boundary, then managed ingress selects a replica under revision traffic rules. Dotted app → revision → replica relationships describe configuration membership, not request hops. App-level external ingress does not by itself prove public internet reachability; environment accessibility and public network access also apply.*

The default FQDN uses the environment DNS suffix. For internal service-to-service calls, Microsoft Learn documents an internal FQDN pattern that includes `.internal.` and is scoped to the same Container Apps environment.

## Portal view

The **Ingress** blade under **Networking** shows the app-level ingress controls visible for a single container app. Use it to confirm app exposure, protocol, port, client-certificate mode, and IP restrictions. Environment accessibility, public network access, and premium ingress are configured on the Container Apps environment rather than this app blade, while some app ingress properties require another portal surface or ARM, Bicep, YAML, or CLI configuration.

![Azure Portal Ingress blade for ca-sample-d38538 showing Ingress enabled, Accepting traffic from anywhere, Ingress type HTTP, Client certificate mode Ignore, Transport Auto, Target port 80, the public Endpoints URL ending in koreacentral.azurecontainerapps.io, an Additional TCP ports row, and the start of the IP Restrictions section with "Allow all traffic (default)" selected.](../../assets/platform/networking/01-ingress-blade.png)

- **[Observed]** The blade renders the ingress toggle checked, **Ingress traffic** with two radio choices ("Limited to Container Apps Environment" unselected, "Accepting traffic from anywhere" selected), **Ingress type** with HTTP selected and TCP disabled, **Client certificate mode** with Ignore / Accept / Require options, a **Transport** dropdown defaulted to Auto, an **Insecure connections** checkbox, **Target port** showing `80`, an **Endpoint(s)** link of the form `https://<your-app-name>.<env-suffix>.koreacentral.azurecontainerapps.io`, an **Additional TCP ports** collapsible row, and an **IP Restrictions** section header followed by "IP Security Restrictions Mode" set to "Allow all traffic (default)".
- **[Inferred]** Grouping `Ingress traffic`, `Ingress type`, `Client certificate mode`, `Transport`, `Target port`, and `IP Restrictions` together on one blade is consistent with the conceptual model in this page: ingress is one decision surface that combines exposure (external vs internal), protocol (HTTP / HTTP/2 / TCP), authentication boundary (client certificate mode), and source filtering (IP restrictions). The "Accepting traffic from anywhere" radio appears to map to `external: true` in ARM/Bicep/YAML, and "Limited to Container Apps Environment" appears to map to `external: false`.
- **[Not Proven]** The visible blade does not expose every ingress field documented by Microsoft Learn. CORS policy, session affinity (`affinity: sticky` / `none`), the default 240-second request timeout, and `additionalPortMappings` rules beyond the collapsed "Additional TCP ports" row are not visible in this capture. Where each of those settings is reached in the Portal — versus only via ARM/Bicep/YAML — is not proven by this PNG.

## Enabling ingress

At the app level, ingress is controlled through the ingress configuration, including the `external` property in ARM, Bicep, and YAML representations.

| Ingress state | Result | Typical use |
|---|---|---|
| Enabled + `external: true` | App is published at the environment inbound boundary; public or private reachability follows the environment network configuration | Public web app on a public environment, or VNet/private endpoint access |
| Enabled + `external: false` | App's own FQDN is directly reachable only within the environment by default; an environment-level HTTP route can still target it | Internal microservice, internal API |
| Disabled | No inbound HTTP or TCP endpoint | Queue worker, event-driven processor, background component |

When ingress is disabled, the app does not expose an inbound endpoint. That is the safest posture for workloads that only react to events or outbound calls.

## External vs Internal ingress

The most important app-level ingress decision is whether the app is published at its environment boundary or directly reachable only inside the environment. This setting alone does not determine internet reachability.

| Setting | Reachability | Name behavior | Best fit |
|---|---|---|---|
| `external: true` | Environment inbound boundary and same-environment callers; the boundary can be public, internal-load-balancer, or private-endpoint based | Uses the app FQDN or custom domain | Public apps when the environment permits public access; private VNet apps on an internal environment |
| `external: false` | Direct app access from the same environment by default; an environment-level HTTP route can still forward outside traffic to the app | Uses environment-scoped internal addressing, including `.internal.` FQDN patterns | Internal microservices not targeted by an external route |

For same-environment calls, Microsoft Learn documents two common internal patterns:

- `http://<app-name>`
- `<app-name>.internal.<environment-unique-id>.<region>.azurecontainerapps.io`

By default, a request sent through the environment inbound endpoint to an app with internal ingress returns `404`. An environment-level HTTP route is an explicit exception: it can target an `external: false` app and forward requests from the route FQDN. To keep the app unreachable from outside the environment, do not include it as an HTTP route target, or isolate it in a separate environment with no public routes.

### App-level vs environment-level internal exposure

Do not confuse **app-level internal ingress** with an **internal environment**:

| Scope | Setting | Effect |
|---|---|---|
| App | `external: false` | Hides the app's own FQDN from the environment inbound boundary; same-environment callers retain direct access, and an environment HTTP route can still target the app |
| Environment | `internal: true` / `--internal-only true` | Removes the public environment entry point and uses internal load balancer behavior for the environment |

This distinction matters:

- An **external environment** can still host an app with `external: false`.
- That setting does **not** make the whole environment private.
- A truly private inbound design usually starts with an **internal environment** and then chooses app-level ingress per service.

For the full environment-level private networking deep dive, see [Private Endpoints](private-endpoints.md) and [VNet Integration](vnet-integration.md).

**Takeaway:** Decide who needs access before choosing app ingress. For VNet-only inbound access, an internal environment still uses app-level external ingress so the environment's internal entry point can accept the request.

<!-- diagram-id: ingress-decision-tree -->
```mermaid
flowchart TD
    accTitle: Choose an Azure Container Apps ingress exposure model
    accDescr: A decision tree starts with whether the workload accepts inbound traffic, then separates same-environment, public internet, private virtual network, and partner callers. It distinguishes app ingress from environment accessibility and public network access.

    NEED{"Does the workload<br/>accept inbound traffic?"}
    CALLER{"Who must reach<br/>the app?"}
    DISABLED["Disable ingress<br/>no inbound endpoint"]
    INTERNAL_APP["Internal app ingress<br/>external: false"]
    INTERNAL_NAME["Use the app name or<br/>internal FQDN"]
    PUBLIC_APP["External app ingress<br/>external: true"]
    PUBLIC_ENV["External environment<br/>public network access enabled"]
    PUBLIC_CONTROLS["Use TLS, custom domain,<br/>IP rules, and app authorization"]
    PRIVATE_ENV["Internal environment<br/>custom VNet and internal entry"]
    PRIVATE_APP["External app ingress<br/>accept through the environment's<br/>private entry point"]
    PARTNER["External app ingress<br/>plus required client certificate"]
    PARTNER_CONTROLS["Validate client identity<br/>and apply app authorization"]

    NEED -->|"No"| DISABLED
    NEED -->|"Yes"| CALLER
    CALLER -->|"Same environment only"| INTERNAL_APP
    INTERNAL_APP --> INTERNAL_NAME
    CALLER -->|"Public internet"| PUBLIC_APP
    PUBLIC_APP --> PUBLIC_ENV
    PUBLIC_ENV --> PUBLIC_CONTROLS
    CALLER -->|"Private VNet only"| PRIVATE_ENV
    PRIVATE_ENV --> PRIVATE_APP
    CALLER -->|"B2B partner with mTLS"| PARTNER
    PARTNER --> PARTNER_CONTROLS

    LEGEND["Boundary key<br/>app ingress = per-app exposure<br/>environment access = available public or private entry"]
```

*Figure: The decision keeps app-level ingress separate from the environment traffic boundary. In particular, external app ingress on an internal environment accepts traffic through the private environment entry point; it does not create public internet reachability.*

## Transport

Azure Container Apps supports these ingress transport values:

| Value | Use when | Notes |
|---|---|---|
| `auto` | Standard HTTP workloads | Automatically detects HTTP/1 or HTTP/2 |
| `http` | HTTP/1-only workload or conservative HTTP config | Explicit HTTP transport |
| `http2` | gRPC or end-to-end HTTP/2 requirement | Use for gRPC workloads |
| `tcp` | Non-HTTP TCP exposure | Required for TCP ingress |

Use `http2` for gRPC. Use `tcp` only when the app is exposing a raw TCP listener rather than HTTP semantics.

## TCP ingress

TCP ingress is for workloads that expose a TCP port instead of an HTTP endpoint.

Key Microsoft Learn–verified constraints:

- Azure Container Apps supports TCP ingress in addition to HTTP ingress.
- External TCP ingress is supported only for Container Apps environments that use a virtual network.
- The TCP `exposedPort` can't be `80` or `443`.
- If `exposedPort` is omitted, it defaults to `targetPort`.
- Port `36985` is reserved for internal health checks.
- Microsoft Learn does **not** document a blanket "only one TCP app per environment" rule. Instead, it documents that externally exposed extra TCP ports must be unique across the environment, while internal extra ports can reuse the same port across multiple apps.

TCP ingress does not use browser-oriented ingress features such as CORS, and it does not rely on HTTP request concepts such as headers, paths, or methods.

## Additional TCP and HTTP ports

Use `additionalPortMappings` when the app needs more than its main ingress port.

| Behavior | Microsoft Learn guidance |
|---|---|
| Maximum additional ports | Up to five additional ports per app |
| External extra ports | Must be unique across the Container Apps environment |
| Internal extra ports | Can be reused across multiple apps |
| HTTP features on extra ports | The main ingress port supports built-in HTTP features; extra TCP ports do not |

If you run HTTP on top of an extra TCP port, built-in ingress features such as CORS and session affinity are not supported on that extra port.

## IP restrictions

Use `ipSecurityRestrictions` to allow or deny inbound traffic by source IP or CIDR range.

| Behavior | Guidance |
|---|---|
| No IP rules configured | All inbound traffic is allowed |
| Allow rules | Permit only matching sources |
| Deny rules | Explicitly block matching sources |

Microsoft Learn documents that there is no mixed allow-and-deny precedence model to evaluate in a single rule set: **all rules must be the same type**. The IP restrictions article states, "All rules must be the same type. You cannot combine allow rules and deny rules," and the Azure CLI reference reiterates that all restrictions must use the same action. If no restrictions are configured, all inbound traffic is allowed.

Use platform IP restrictions when you want coarse-grained source filtering at ingress. Keep fine-grained authorization in the gateway or application layer.

## Client certificates (mTLS)

Container Apps supports ingress client certificate authentication through `clientCertificateMode` values such as `ignore`, `accept`, and `require`.

Use this for B2B or partner-facing APIs when the trust decision belongs at the ingress boundary.

!!! note "Repository cross-links pending separate merge"
    The current `main` branch in this repository does not yet contain the planned `docs/platform/security/ingress-client-certificates.md` and `docs/platform/security/mtls.md` pages referenced in the task context. This ingress overview therefore documents the feature briefly and cites Microsoft Learn directly instead of creating broken internal links.

## CORS policy

Use `corsPolicy` when browser-based callers need cross-origin access controlled at the ingress layer.

Microsoft Learn documents these fields:

- `allowedOrigins`
- `allowedMethods`
- `allowedHeaders`
- `exposeHeaders`
- `allowCredentials`
- `maxAge`

Use platform CORS when you want a consistent ingress policy across revisions. Use app-level CORS only when the application needs request-specific behavior that the platform policy cannot express.

## Sticky sessions and session affinity

Container Apps supports session affinity with `affinity: sticky` or `affinity: none` only when HTTP ingress is enabled and the app uses single revision mode.

| Setting | Behavior |
|---|---|
| `none` | No session affinity |
| `sticky` | Uses cookies to keep a client on the same replica |

Prefer `sticky` only when the application cannot yet be made stateless. Sticky sessions pin a client to a replica, so they can reduce load distribution quality. Because the feature requires single revision mode, it is not a mechanism for multiple-revision traffic splitting.

!!! note "Use session affinity conservatively"
    Microsoft Learn documents cookie-based session affinity only for HTTP ingress in single revision mode. It is most meaningful when more than one replica can serve requests; otherwise there is nothing to pin a client to. Use multiple revision mode and traffic rules for canary or blue-green routing instead of session affinity.

## Request timeout

The default HTTP ingress request timeout is **240 seconds**.

For long-running work:

- Prefer asynchronous patterns.
- Return quickly and continue processing with queues, jobs, or background workflows.
- Avoid treating ingress as a long-lived work executor.

## Maximum request body size

!!! warning "Maximum request body size is not directly documented"
    Microsoft Learn documents ingress timeout, header-count, and idle-request limits, but it does not publish a clear maximum request body size for Container Apps ingress on the cited ingress pages. Microsoft Learn does document `httpMaxRequestSize` for Dapr's HTTP server, but that is a Dapr sidecar setting rather than a documented Container Apps ingress limit. Keep body-size claims warned unless you validate them through updated Microsoft documentation or direct platform testing.

## Traffic split

Ingress routes requests to active revisions based on revision traffic configuration. Use this for canary or gradual rollout behavior, but keep the detailed revision strategy in the dedicated revision guide.

See [Revision Lifecycle in Azure Container Apps](../revisions/index.md) for the full traffic split and revision strategy guidance.

## Headers

Microsoft Learn explicitly documents these ingress-forwarded headers for HTTP ingress:

| Header | Purpose |
|---|---|
| `X-Forwarded-Proto` | Original request protocol |
| `X-Forwarded-For` | Client IP chain |
| `X-Forwarded-Client-Cert` | Client certificate metadata when client cert mode accepts or requires certificates |

!!! warning "Header coverage is documented only partially"
    The Microsoft Learn ingress overview says, "The following table lists the HTTP headers that are relevant to ingress in Container Apps," and that table lists only `X-Forwarded-Proto`, `X-Forwarded-For`, and `X-Forwarded-Client-Cert`. Because `X-Forwarded-Host` is not listed in the official ingress header table, this guide does not treat that header as verified platform behavior.

## Comparison: External vs Internal

| Dimension | External ingress | Internal ingress |
|---|---|---|
| Internet reachable | Only when the environment has a public inbound endpoint and public network access is enabled | Not through the app's own FQDN; an environment-level HTTP route can still provide an outside path |
| Same-environment reachable | Yes | Yes |
| Default naming | Public FQDN or custom domain | Internal addressing including `.internal.` pattern |
| Best fit | Public apps and partner APIs | Private microservices |
| Typical controls | TLS, custom domain, IP restrictions, optional mTLS | Service discovery, environment boundary, private network design |

## Common scenarios

| Scenario | Recommended ingress posture | Why |
|---|---|---|
| Public API | External app ingress on an environment that accepts public traffic | Public clients must reach the service through the environment boundary |
| Internal microservice | Internal ingress with no environment HTTP route targeting the app | Keeps direct app access inside the environment |
| B2B partner API with client certificates | External app ingress plus client certificate auth on an environment reachable by partners | Publishes the app at the intended environment boundary while enforcing certificate-based caller identity |
| gRPC backend | `transport: http2` | gRPC requires HTTP/2 |
| TCP database proxy or custom TCP endpoint | `transport: tcp` with explicit exposed port rules | Raw TCP listener, not HTTP |
| Multi-region app behind Azure Front Door | External app ingress behind a global edge, using either the documented public or private-link integration | Front Door handles global routing while Container Apps ingress remains the regional app entry point |

## See Also

- [Networking in Azure Container Apps](index.md)
- [VNet Integration](vnet-integration.md)
- [Private Endpoints](private-endpoints.md)
- [Service-to-Service Communication](service-to-service.md)
- [Application Gateway Integration with an Internal Container Apps Environment](application-gateway-integration.md)
- [Revision Lifecycle in Azure Container Apps](../revisions/index.md)
- [Azure Container Apps Networking Best Practices](../../best-practices/networking.md)
- [AppGW to Internal Azure Container Apps NSG Destination (Troubleshooting)](../../troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md)

## Sources

- [Ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Communicate between container apps in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps)
- [Networking in Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Configure ingress for a Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration)
- [Configure virtual networks in Azure Container Apps environments (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/custom-virtual-networks)
- [Use a private endpoint with an Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint)
- [Ingress for your app in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to)
- [Configure IP ingress restrictions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ip-restrictions)
- [az containerapp ingress access-restriction (Microsoft Learn)](https://learn.microsoft.com/en-us/cli/azure/containerapp/ingress/access-restriction?view=azure-cli-latest)
- [Configure CORS in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/cors)
- [Session affinity in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions)
- [Configure client certificate authentication in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/client-certificate-authorization)
- [Configure rule-based routing in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/rule-based-routing)
- [Use premium ingress in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/premium-ingress)
