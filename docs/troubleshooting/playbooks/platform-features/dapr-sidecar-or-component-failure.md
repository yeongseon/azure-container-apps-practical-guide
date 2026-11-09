---
content_sources:
  diagrams:
    - id: troubleshooting-decision-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps has built-in support for Dapr.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
      verified: true
    - claim: Dapr can be enabled for a container app with an app ID and app port configuration.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
      verified: true
---
# Dapr Sidecar or Component Failure

## 1. Summary

### Symptom

Dapr-enabled Container Apps fail service invocation, pub/sub, or state operations, or the Dapr sidecar never becomes usable. The app container may be healthy and reachable while Dapr calls return 500, 503, or timeouts.

Failures often surface in sidecar logs first, but the user-visible breakage can appear in application logs, broker logs, or secret resolution errors. The key question is whether the problem is Dapr enablement, app binding, component definition, secret access, or backend connectivity.

### Why this scenario is confusing

The workload can look "healthy" at the platform layer because the revision is ready and the app container is running. That makes it easy to misread a Dapr failure as an app bug, when the actual break is in the sidecar or its dependent component path.

The same symptom also appears for multiple root causes: wrong `dapr.appPort`, invalid component YAML, missing secrets, and blocked backend traffic. You need evidence that separates sidecar startup from component initialization and then from backend reachability.

### Troubleshooting decision flow

<!-- diagram-id: troubleshooting-decision-flow -->
```mermaid
flowchart TD
    accTitle: Isolate Dapr sidecar, component, and backend failures
    accDescr: Check app-level Dapr enablement and port, sidecar health, environment-level component initialization, app-ID scope, and backend access in that order before retesting the exact Dapr operation.

    START[Dapr operation fails] --> ENABLED{Dapr enabled with expected<br/>app ID and app port?}
    ENABLED -->|No| ENABLE[Correct Dapr app settings]
    ENABLED -->|Yes| HEALTH{Sidecar health endpoint<br/>responds?}
    HEALTH -->|No| SIDECAR[Inspect sidecar startup<br/>and app-port binding]
    HEALTH -->|Yes| COMPONENT{Component loads<br/>without errors?}
    COMPONENT -->|No| DEFINITION[Inspect component schema,<br/>metadata, secrets, and scope]
    COMPONENT -->|Yes| BACKEND{Backend reachable and<br/>authorized?}
    BACKEND -->|No| ACCESS[Fix DNS, network, TLS,<br/>identity, or firewall]
    BACKEND -->|Yes| OPERATION[Retest the exact invocation,<br/>state, or pub/sub operation]
    ENABLE --> OPERATION
    SIDECAR --> OPERATION
    DEFINITION --> OPERATION
    ACCESS --> OPERATION
    OPERATION --> PASS{Operation succeeds?}
    PASS -->|Yes| DONE[Record verified path]
    PASS -->|No| EVIDENCE[Collect sidecar and<br/>component evidence]
```

*Figure: Sidecar health proves only the runtime endpoint; component loading and backend authorization remain independent prerequisites.*

## 2. Common Misreadings

- "The application endpoint is broken." — Dapr can reject or hang requests before they reach the app handler.
- "The revision is ready, so Dapr is fine." — Revision readiness does not guarantee Dapr sidecar health or component loading.
- "The broker or state store is down." — The backend may be reachable, but the component YAML or secret reference is invalid.
- "Managed identity failed everywhere." — Often only the component path fails because one secret or resource ID is wrong.
- "Dapr disabled itself after deployment." — In practice, the app spec often omits `dapr.enabled` or points at the wrong port.

## 3. Competing Hypotheses

| Hypothesis | Typical Evidence For | Typical Evidence Against |
|---|---|---|
| H1: Dapr not enabled on the Container App | `properties.configuration.dapr` is empty; no sidecar logs; port 3500 health check fails | `dapr.enabled` present and sidecar responds on `http://localhost:3500/v1.0/healthz` |
| H2: App port mismatch | Sidecar starts, but calls fail; logs show app health or connection errors; `dapr.appPort` differs from the app listener | App listens on the declared port and local app endpoint responds inside the container |
| H3: Component metadata invalid | Component init logs mention missing fields, unsupported metadata, or schema errors | Component loads successfully and Dapr lists it as initialized |
| H4: Component secret reference failure | Logs mention secret resolution, Key Vault access, or missing secret names | Secret exists, identity can read it, and component resolves credentials cleanly |
| H5: Backend service unreachable | Timeouts, DNS failures, TLS failures, firewall errors, or 403/401 from the backend | Backend is reachable from the same environment and the same credential path works |

## 4. What to Check First

### Metrics

- Dapr request failure count by operation type (`invoke`, `state`, `publish`).
- Sidecar startup duration and revision provisioning time.
- Backend dependency latency and timeout rate.
- App container restarts that coincide with Dapr failures.

### Logs (with KQL)

```kusto
let AppName = "ca-myapp";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("dapr", "component", "pubsub", "state", "sidecar", "healthz")
| project TimeGenerated, ContainerAppName_s, RevisionName_s, ReplicaName_s, Log_s
| order by TimeGenerated desc
```

```kusto
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("dapr", "component", "secret", "init", "health")
| project TimeGenerated, ContainerAppName_s, RevisionName_s, Log_s
| order by TimeGenerated desc
```

### Platform Signals (with CLI)

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr" --output json
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers" --output json
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
```

| Command or parameter | Purpose |
| --- | --- |
| `az containerapp show` | Reveals whether Dapr is declared in the spec and which port the sidecar should bind to. |
| `az containerapp logs show` | Returns sidecar startup logs and app-side Dapr call failures, showing init errors or connection breakage. |
| `az containerapp revision list` | Identifies when the failure began relative to deployments. |
| `--name` | Routes the query to the affected app. |
| `--output` | JSON for structural parsing; table for quick scan of revisions and their timestamps. |
| `--query` | Filters results to only Dapr metadata or container specs, reducing signal-to-noise. |
| `--resource-group` | Restricts the lookup to the resource group containing the app. |
| `--type` | Requests console layer (app and sidecar output) rather than platform system logs. |

## 5. Evidence to Collect

### Required Evidence

| Evidence | Command/Query | Purpose |
|---|---|---|
| Dapr config on the app | `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr" --output json` | Confirms whether Dapr is enabled and which app ID/port is configured |
| Revision and container state | `az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table` | Shows whether the bad behavior is tied to a revision rollout |
| Sidecar health | `az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "curl -fsS http://127.0.0.1:3500/v1.0/healthz"` | Confirms the Dapr sidecar is listening and healthy |
| App listener check | `az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "curl -fsS http://127.0.0.1:${CONTAINER_PORT}/"` | Confirms the app is listening on the port Dapr expects |
| Console logs | `az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console` | Captures app-side and sidecar-side failure messages |
| Secrets metadata | `az containerapp secret list --name "$APP_NAME" --resource-group "$RG"` | Verifies whether referenced secrets exist |

### Useful Context

- Note the first bad revision and whether the symptom started immediately after deploy.
- Capture the exact Dapr operation: service invocation, state read/write, pub/sub publish/subscribe.
- Compare failures across replicas; a single replica may indicate rollout drift.
- Record whether the backend is public, private, or behind an identity boundary.
- Save the component manifest name, type, and secret names exactly as deployed.

## 6. Validation and Disproof by Hypothesis

### H1: Dapr not enabled on the Container App

**Signals that support:**

- `properties.configuration.dapr` is null, empty, or missing `enabled: true`.
- Sidecar health check fails at `http://127.0.0.1:3500/v1.0/healthz`.
- No Dapr startup lines appear in console logs.

**Signals that weaken:**

- Dapr health returns 200 and component logs appear normally.
- The app can invoke other Dapr services from the same revision.

**What to verify:**

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr" --output yaml
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "curl -i http://127.0.0.1:3500/v1.0/healthz"
```

| Command or parameter | Purpose |
| --- | --- |
| `az containerapp show` | Retrieves the Dapr configuration block to verify `enabled: true` is present. |
| `az containerapp exec` | Tests sidecar reachability from within the container using the health endpoint. |
| `--command` | Runs curl against the Dapr health port (3500) to confirm the runtime process is up. |
| `--name` | Targets the app for the exec and show queries. |
| `--output` | YAML format shows nested Dapr structure (enabled, appID, appPort) more clearly. |
| `--query` | Extracts only the Dapr config block to eliminate noise from the full app definition. |
| `--resource-group` | Routes queries to the resource group holding the app. |

### H2: App port mismatch

**Signals that support:**

- `dapr.appPort` differs from the container process port.
- Logs show connection refused, timeout, or readiness mismatch against the app port.
- The app responds on one port locally but Dapr targets another.

**Signals that weaken:**

- The app responds correctly on the declared port and Dapr calls reach it.
- The failure happens before any app connection attempt.

**What to verify:**

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr.appPort" --output tsv
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "sh -c 'printenv | sort | grep -E \"^(PORT|CONTAINER_APP_PORT|DAPR_)\"'"
```

| Command or parameter | Purpose |
| --- | --- |
| `az containerapp show` | Returns the Dapr appPort setting declared in the app spec. |
| `az containerapp exec` | Runs printenv inside the container to see which ports the app actually listens on. |
| `--command` | Uses grep to filter for PORT-family variables that reveal the actual listener port. |
| `--name` | Targets the app whose port configuration and runtime state are being compared. |
| `--output` | TSV format simplifies shell scripting to extract just the port number. |
| `--query` | Filters to dapr.appPort so you can directly compare it against the runtime environment. |
| `--resource-group` | Routes queries to the resource group containing the affected app. |

### H3: Component metadata invalid

**Signals that support:**

- Logs mention missing required metadata, invalid schema, unsupported type, or malformed YAML.
- Only one component fails while others load.
- The failure starts immediately after a component manifest change.

**Signals that weaken:**

- The component loads cleanly and the backend path is the only failing step.
- The same manifest works in another environment.

**What to verify:**

```kusto
let AppName = "ca-myapp";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("metadata", "schema", "yaml", "component", "invalid")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

### H4: Component secret reference failure

**Signals that support:**

- Logs mention secret lookup failures or Key Vault access denied.
- The referenced secret name does not exist in the app.
- Managed identity permissions were changed recently.

**Signals that weaken:**

- The secret list includes the referenced secret and identity can read Key Vault.
- The component uses no secrets and still fails.

**What to verify:**

```bash
az containerapp secret list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp identity show --name "$APP_NAME" --resource-group "$RG" --output json
```

| Command or parameter | Purpose |
| --- | --- |
| `az containerapp secret list` | Lists all secrets deployed with the app; compare against names referenced in the component manifest. |
| `az containerapp identity show` | Reports the managed identity assigned to the app, confirming it can be used for Key Vault access. |
| `--name` | Targets the app whose secrets and identity role are being verified. |
| `--output` | Table for secrets; JSON for identity to see role assignments and tenant context. |
| `--resource-group` | Routes queries to the resource group holding the app. |

```kusto
let AppName = "ca-myapp";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("secret", "Key Vault", "access denied", "forbidden")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

### H5: Backend service unreachable

**Signals that support:**

- Timeouts, DNS resolution errors, TLS handshake failures, 401/403, or 5xx from the backend.
- Backend is private and the app environment lacks the required network path.
- The same component works from another subnet, environment, or identity.

**Signals that weaken:**

- Backend calls succeed from the same container using the same identity and hostname.
- Only the Dapr sidecar health check fails, not the backend call itself.

**What to verify:**

```bash
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "curl -vk https://backend.example.internal/health"
```

| Command or parameter | Purpose |
| --- | --- |
| `az containerapp exec` | Runs a curl test from inside the app container, simulating the network and identity context the Dapr sidecar uses. |
| `--command` | Targets the backend hostname with curl's verbose and insecure flags to log DNS, TLS negotiation, and HTTP response. |
| `--name` | Targets the app container so the curl inherits its network interface and managed identity. |
| `--resource-group` | Routes the exec to the resource group containing the app. |

## 7. Likely Root Cause Patterns

| Pattern | Frequency | First Signal | Typical Resolution |
|---|---|---|---|
| Dapr disabled or omitted | High | No sidecar health response; empty Dapr config | Enable Dapr and redeploy with the correct app ID and port |
| App port mismatch after app refactor | High | Sidecar healthy, app connection refused | Align `dapr.appPort` with the real listener port |
| Component YAML typo or missing metadata | Medium | Init error only for one component | Fix the manifest schema and redeploy the component |
| Secret reference or identity drift | Medium | Secret lookup or Key Vault error | Restore secret name, identity permissions, or Key Vault access |
| Backend firewall / DNS / private endpoint block | Medium | Timeout or name resolution failure | Repair network route, DNS, or backend allowlist |

## 8. Immediate Mitigations

1. Confirm the Dapr config is actually enabled and pinned to the correct port.

    ```bash
    az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr" --output yaml
    ```

    | Command or parameter | Purpose |
    | --- | --- |
    | `az containerapp show` | Retrieves the full Dapr configuration block (enabled, appID, appPort). |
    | `--name` | Targets the app whose Dapr enablement is in question. |
    | `--output` | YAML shows nested structure; identifies which port is declared. |
    | `--query` | Filters to dapr config only. |
    | `--resource-group` | Scopes the Dapr-configuration mitigation to the affected app deployment. |

2. Check the sidecar health endpoint from inside the app container.

    ```bash
    az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "curl -i http://127.0.0.1:3500/v1.0/healthz"
    ```

    | Command or parameter | Purpose |
    | --- | --- |
    | `az containerapp exec` | Runs the health probe inside the container; response code shows sidecar liveness. |
    | `--command` | Invokes curl -i (with response headers) against the standard Dapr health port. |
    | `--name` | Targets the app container so curl uses its network namespace. |
    | `--resource-group` | Runs the in-container listener check against the app in its owning resource group. |

3. If the app port is wrong, update the revision with the real listener port and redeploy.

    ```bash
    az containerapp dapr enable --name "$APP_NAME" --resource-group "$RG" --dapr-app-port 8000
    ```

    | Command or parameter | Purpose |
    | --- | --- |
    | `az containerapp dapr enable` | Enables or updates Dapr on the container app with the application listener port Dapr should call. |
    | `--dapr-app-port` | Sets the application listener port to `8000` so the sidecar forwards requests to the correct endpoint. |
    | `--name` | Targets the app to be corrected. |
    | `--resource-group` | Applies the Dapr app-port correction within the workload resource group. |

4. If a component is failing, temporarily remove or disable the broken component so the rest of the app can recover.

    ```bash
    az containerapp env dapr-component list --name "$ACA_ENV_NAME" --resource-group "$RG" --output table
    ```

    | Command or parameter | Purpose |
    | --- | --- |
    | `az containerapp env dapr-component list` | Lists all Dapr components in the environment; use to identify and remove the failing one. |
    | `--name` | Targets the container apps environment holding the components. |
    | `--output` | Table format shows names and types for quick identification. |
    | `--resource-group` | Routes to the resource group containing the environment. |

5. If secret resolution is the blocker, restore the secret or identity path before retrying the component.

    ```bash
    az containerapp secret list --name "$APP_NAME" --resource-group "$RG" --output table
    ```

    | Command or parameter | Purpose |
    | --- | --- |
    | `az containerapp secret list` | Lists deployed secrets to verify the component can reference them by name. |
    | `--name` | Targets the app whose secrets are being verified. |
    | `--output` | Table format shows secret names and types. |
    | `--resource-group` | Lists component and secret evidence from the environment resource group. |

6. Re-test the exact Dapr operation that failed, not just the app homepage.

    ```bash
    curl -fsS http://127.0.0.1:3500/v1.0/invoke/otherapp/method/health
    ```

## 9. Prevention

- Keep Dapr app ID, app port, and component manifests in source control with the app code.
- Add a smoke test that calls `http://127.0.0.1:3500/v1.0/healthz` after deployment.
- Validate component YAML in CI before applying it to the environment.
- Treat secret names and Key Vault references as deployment contracts.
- Add log alerts for component init errors, secret resolution failures, and repeated Dapr timeouts.
- Verify backend reachability from the same Container Apps environment during every release.
- Review port changes whenever the app framework, container image, or startup command changes.

## See Also

- [Service-to-Service Connectivity Failure](../ingress-and-networking/service-to-service-connectivity-failure.md)
- [Secret and Key Vault Reference Failure](../identity-and-configuration/secret-and-key-vault-reference-failure.md)
- [Dapr Sidecar Logs KQL](../../kql/dapr-and-jobs/dapr-sidecar-logs.md)

## Sources

- https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
- https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
- https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
