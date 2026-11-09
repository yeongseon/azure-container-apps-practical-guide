---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
  diagrams:
    - id: dapr-pubsub-failure-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps can use Dapr building blocks, including pub/sub components.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
      verified: true
    - claim: Dapr components are applied at the environment scope and can be constrained with scopes.
      source: https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
      verified: true
---
# Dapr Pub/Sub Failure

Use this playbook when publish or subscribe paths fail, messages disappear, or only some apps can see the topic traffic.

## Symptom

- Publishers return errors when sending to the Dapr pub/sub component.
- Subscribers never receive events even though publishers report success.
- Only some apps consume messages in the same environment.
- The incident begins after a component edit, secret rotation, or app rename.

<!-- diagram-id: dapr-pubsub-failure-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose a Dapr pub/sub failure
    accDescr: Verify Dapr enablement, the environment-level pub/sub component, app-ID scopes, component metadata and credentials, then test broker transport and end-to-end publish and delivery.

    START[Publish or delivery fails] --> ENABLED{Dapr enabled with<br/>expected app IDs?}
    ENABLED -->|No| APP[Correct Dapr app settings]
    ENABLED -->|Yes| EXISTS{Pub/sub component exists<br/>in the environment?}
    EXISTS -->|No| RESTORE[Create or restore component]
    EXISTS -->|Yes| SCOPED{Publisher and subscriber<br/>app IDs in scope?}
    SCOPED -->|No| SCOPE[Correct component scopes]
    SCOPED -->|Yes| CONFIG{Metadata, secret references,<br/>and identity valid?}
    CONFIG -->|No| CREDENTIALS[Correct component configuration]
    CONFIG -->|Yes| BROKER{Broker reachable and<br/>authorized?}
    BROKER -->|No| PATH[Fix DNS, network, TLS,<br/>or broker authorization]
    BROKER -->|Yes| TEST[Publish a known event<br/>and verify subscriber delivery]
    APP --> TEST
    RESTORE --> TEST
    SCOPE --> TEST
    CREDENTIALS --> TEST
    PATH --> TEST
```

*Figure: Component scope uses Dapr application IDs, while broker transport and authorization are separate checks after the component loads.*

## Possible Causes

- The pub/sub component is missing or misnamed.
- The component type or broker metadata is wrong.
- Publisher or subscriber apps are excluded by `scopes`.
- Secret or managed identity configuration for the broker is invalid.
- The application points to the wrong pub/sub component or topic name.

## Diagnosis Steps

1. Check the publisher and subscriber Dapr settings.
2. Inspect the environment-level pub/sub component definition.
3. Compare the component name in the app code or sidecar call with the actual component name.
4. Verify that all intended apps are allowed by `scopes`.

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
    --dapr-component-name "pubsub" \
    --output yaml
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp show` | Retrieve the app's Dapr configuration to confirm the app-ID and Dapr enablement status |
| `az containerapp env dapr-component list` | List all Dapr components in the environment to confirm the pub/sub component exists and its name |
| `az containerapp env dapr-component show` | Retrieve the pub/sub component definition to inspect its type, broker metadata, and scope list |
| `--dapr-component-name` | Target the pub/sub component by name to fetch its full configuration and scope constraints |
| `--name` | Specify the app name and environment name to isolate configuration from other apps or environments |
| `--output` | Use JSON for the app config (structured diff-friendly), table for component lists (quick scan), and YAML for component definition (human-readable) |
| `--query` | Extract only properties.configuration.dapr to focus on the app's Dapr enablement and app-ID |
| `--resource-group` | Restrict queries to the resource group containing the affected app and environment |

KQL for symptom capture:

```kusto
let AppName = "ca-myapp";
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(4h)
| where ContainerAppName_s == AppName
| where Log_s has_any ("dapr", "pubsub", "publish", "subscribe", "topic", "error", "failed")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Resolution

1. Reconcile the component name used by the application with the deployed component name.
2. Fix `scopes` so both the publisher and subscriber apps can load the component.
3. Correct broker metadata, credentials, or network reachability.
4. Reapply the component and test a single known topic end to end.

```bash
az containerapp env dapr-component set \
    --name "$ACA_ENV_NAME" \
    --resource-group "$RG" \
    --dapr-component-name "pubsub" \
    --yaml "./pubsub.yaml"
```

| Command or parameter | Purpose |
|---|---|
| `az containerapp env dapr-component set` | Apply the corrected pub/sub component definition to the environment to refresh broker credentials, scope list, and metadata |
| `--dapr-component-name` | Specify the pub/sub component name (must match the name used in app code) to update the correct component |
| `--name` | Target the environment where the component is deployed |
| `--resource-group` | Restrict the update to the resource group containing the affected environment |
| `--yaml` | Pass the corrected component YAML file containing fixed scopes, broker metadata, and secret references |

## Prevention

- Version-control Dapr component YAML alongside app configuration.
- Use explicit component names and topic names across environments.
- Include pub/sub smoke tests in deployment validation.
- Review `scopes` whenever an app is renamed or newly added to the environment.

## See Also

- [Dapr State Store Failure](./dapr-state-store-failure.md)
- [Dapr Sidecar or Component Failure](./dapr-sidecar-or-component-failure.md)
- [Dapr Pub/Sub Failure Lab](../../lab-guides/dapr-pubsub-failure.md)

## Sources

- [Dapr components in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-components)
- [Dapr overview for Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
- [Azure CLI `az containerapp env dapr-component` reference](https://learn.microsoft.com/en-us/cli/azure/containerapp/env/dapr-component)
