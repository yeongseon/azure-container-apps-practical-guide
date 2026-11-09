---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
  diagrams:
    - id: dapr-state-store-failure-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-component-connection
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Dapr components in Azure Container Apps are defined at the environment scope.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
      verified: true
    - claim: Dapr component scopes can limit which apps load a component.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
      verified: true
---
# Dapr State Store Failure

Use this playbook when state reads or writes through Dapr fail even though the application itself is reachable.

## Symptom

- Application requests that use Dapr state APIs return errors or time out.
- The app starts, but state-dependent features fail.
- Sidecar or component logs show metadata, secret, or connectivity problems.
- One app fails while another app in the same environment works, which often indicates a scopes mismatch.

<!-- diagram-id: dapr-state-store-failure-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose a Dapr state store failure
    accDescr: Verify Dapr enablement, the environment-level state component, app-ID scopes, component metadata and credentials, then test backend connectivity before retrying state operations.

    START[State read or write fails] --> ENABLED{Dapr enabled with<br/>expected app ID?}
    ENABLED -->|No| APP[Correct Dapr app settings]
    ENABLED -->|Yes| EXISTS{State component exists<br/>in the environment?}
    EXISTS -->|No| RESTORE[Create or restore component]
    EXISTS -->|Yes| SCOPED{Calling app ID<br/>is in scope?}
    SCOPED -->|No| SCOPE[Correct component scopes]
    SCOPED -->|Yes| CONFIG{Component type, metadata,<br/>and credentials valid?}
    CONFIG -->|No| DEFINITION[Correct component definition]
    CONFIG -->|Yes| BACKEND{State service reachable<br/>and authorized?}
    BACKEND -->|No| ACCESS[Fix DNS, network, secret,<br/>or identity access]
    BACKEND -->|Yes| TEST[Retest a known state<br/>write and read]
    APP --> TEST
    RESTORE --> TEST
    SCOPE --> TEST
    DEFINITION --> TEST
    ACCESS --> TEST
```

*Figure: Environment-level component existence, Dapr app-ID scope, and backend access are separate gates in the state path.*

## Possible Causes

- The Dapr component definition uses the wrong component type or metadata.
- Component secrets or connection information are missing or invalid.
- The app name is missing from the component `scopes` list.
- The container app does not have Dapr enabled or uses the wrong app ID.
- The backend state store is unavailable or blocked by identity or network policy.

## Diagnosis Steps

1. Confirm the app has Dapr enabled and uses the expected app ID.
2. List environment-scoped Dapr components and inspect the state store definition.
3. Check whether `scopes` excludes the failing app.
4. Validate the metadata and connectivity path to the backing service.

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.configuration.dapr" \
    --output json

az containerapp env dapr-component list \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG" \
    --output table

az containerapp env dapr-component show \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG" \
    --dapr-component-name "statestore" \
    --output yaml
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp show` | Retrieve the app's Dapr configuration to confirm the app-ID and Dapr enablement status |
| `az containerapp env dapr-component list` | List all Dapr components in the environment to confirm the state component exists and its name |
| `az containerapp env dapr-component show` | Retrieve the state component definition to inspect its backend type, connection metadata, and scope list |
| `--dapr-component-name` | Target the state component by name to fetch its full configuration and scope constraints |
| `--name` | Specify the app name and environment name to isolate configuration from other apps or environments |
| `--output` | Use JSON for the app config (structured diff-friendly), table for component lists (quick scan), and YAML for component definition (human-readable) |
| `--query` | Extract only properties.configuration.dapr to focus on the app's Dapr enablement and app-ID |
| `--resource-group` | Restrict queries to the resource group containing the affected app and environment |

KQL for Dapr-oriented log review:

```kusto
let AppName = "ca-myapp";
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(4h)
| where ContainerAppName_s == AppName
| where Log_s has_any ("dapr", "state", "component", "statestore", "error", "failed")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Resolution

1. Correct the component definition so the name, type, metadata, and version match the backend.
2. Add the failing app to `scopes` when access should be limited but not denied.
3. Refresh secret references or managed identity permissions for the backing state service.
4. Reapply the component and retest from the affected app.

```bash
az containerapp env dapr-component set \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG" \
    --dapr-component-name "statestore" \
    --yaml "./statestore.yaml"
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp env dapr-component set` | Apply the corrected state component definition to the environment to update backend metadata, scope list, and credentials |
| `--dapr-component-name` | Specify the state component name (must match the name referenced in app code) to update the correct component |
| `--name` | Target the environment where the component is deployed |
| `--resource-group` | Restrict the update to the resource group containing the affected environment |
| `--yaml` | Pass the corrected component YAML file containing fixed backend configuration, scopes, and secret references |

## Prevention

- Keep Dapr components in source control with explicit `scopes` comments.
- Standardize component naming so application code and component definitions cannot drift.
- Validate secret rotation and managed identity access before production rollout.
- Test state operations from every app that is intentionally in scope.

## See Also

- [Dapr Sidecar or Component Failure](./dapr-sidecar-or-component-failure.md)
- [Dapr Pub/Sub Failure](./dapr-pubsub-failure.md)
- [Dapr State Store Failure Lab](../../lab-guides/dapr-state-store-failure.md)

## Sources

- [Dapr components in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-components)
- [Connect Dapr components to Azure services](https://learn.microsoft.com/en-us/azure/container-apps/dapr-component-connection)
- [Azure CLI `az containerapp env dapr-component` reference](https://learn.microsoft.com/en-us/cli/azure/containerapp/env/dapr-component)
