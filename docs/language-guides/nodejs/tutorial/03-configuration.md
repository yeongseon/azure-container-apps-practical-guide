---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link
    - id: configuration-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/containers
        - https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 03 - Configuration, Secrets, and Dapr

This step configures runtime settings in Azure Container Apps, including environment variables, secrets, KEDA scaling rules, and Dapr sidecar options.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet and private ACR access using managed identity.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "10px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 55}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Node.js tutorial
    accDescr: Client requests and responses pass through managed ingress to Node.js replicas. The customer VNet contains infrastructure and private-endpoint subnets associated with the environment and ACR private endpoint. Managed identity is assigned to the app, and platform provisioning exchanges image pull requests and layer responses with ACR through that endpoint.
    CALLER(["Client"])
    VNET["Customer VNet<br/>infra + PE subnets"]
    IDENTITY["Managed identity"]
    PE_ACR["ACR PE"]
    ACR["ACR"]
    DNS["ACR DNS zone"]
    subgraph ENV["ACA environment"]
        INGRESS["Ingress"]
        APP["Container app<br/>Node.js"]
        REVISION["Revision config"]
        REPLICAS["Replicas"]
        PLATFORM["Provisioning<br/>(platform)"]
    end
    CALLER ~~~ INGRESS ~~~ REPLICAS ~~~ REVISION ~~~ APP ~~~ IDENTITY ~~~ ACR ~~~ PE_ACR ~~~ PLATFORM ~~~ DNS ~~~ VNET
    CALLER ==>|"Request"| INGRESS
    INGRESS ==>|"Response"| CALLER
    INGRESS ==>|"Request"| REPLICAS
    REPLICAS ==>|"Response"| INGRESS
    VNET -.-> ENV
    VNET -.-> PE_ACR
    APP -.-> IDENTITY
    IDENTITY -.-> ACR
    APP -.-> REVISION
    REVISION -.-> REPLICAS
    PLATFORM -.-> REVISION
    PLATFORM ==>|"Pull"| PE_ACR
    PE_ACR ==>|"Pull"| ACR
    ACR ==>|"Layers"| PE_ACR
    PE_ACR ==>|"Layers"| PLATFORM
    PE_ACR -.-> DNS
```

*Figure: Client traffic crosses managed ingress to Node.js replicas. The customer VNet's infrastructure subnet associates with the environment, and its private-endpoint subnet associates with the ACR private endpoint. Managed identity is assigned to the app and authorizes registry pulls; platform provisioning sends pull requests and receives image layers through that endpoint.*

## Configuration Flow

<!-- diagram-id: configuration-flow -->
```mermaid
flowchart TD
    accTitle: Container Apps configuration flow for Node.js
    accDescr: An operator defines environment variables, application-level secrets, and Dapr settings. The revision template delivers referenced values to a new revision, while the Dapr settings enable a sidecar that communicates with the Node.js app on its configured port.

    OPERATOR["Operator or deployment workflow"]
    PLAIN["Plain environment variable<br/>name and value"]
    SECRET["Application-level secret<br/>direct value or Key Vault reference"]
    TEMPLATE["Revision template<br/>container environment variables"]
    REFERENCE["Secret reference<br/>secretref:secret-name"]
    REVISION["New revision"]
    APP["Node.js app<br/>reads runtime environment"]
    DAPR_CONFIG["Dapr configuration<br/>app ID and app port"]
    SIDECAR["Dapr sidecar<br/>enabled for the app"]

    OPERATOR -->|"Set non-sensitive value"| PLAIN
    OPERATOR -->|"Define sensitive value"| SECRET
    OPERATOR -->|"Enable Dapr"| DAPR_CONFIG
    PLAIN --> TEMPLATE
    SECRET -.->|"Available to revisions"| REFERENCE
    REFERENCE --> TEMPLATE
    TEMPLATE -->|"Revision-scope change"| REVISION
    REVISION -->|"Load at runtime"| APP
    DAPR_CONFIG -->|"Apply sidecar settings"| SIDECAR
    SIDECAR -->|"Call app on configured port"| APP

    LEGEND["Arrow key<br/>solid = configuration or Dapr traffic<br/>dotted = application-level secret availability"]
```

*Figure: Environment-variable changes are revision-scoped, while secrets are application-scoped and become runtime configuration only when referenced. Dapr settings form a separate branch that enables a sidecar and identifies the app port the sidecar calls.*

## Prerequisites

- Completed [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- A running Container App

## Step-by-step

1. **Set standard variables**

    ```bash
    RG="rg-nodejs-guide"
    BASE_NAME="nodejs-guide"
    DEPLOYMENT_NAME="main"

    APP_NAME=$(az deployment group show \
      --name "$DEPLOYMENT_NAME" \
      --resource-group "$RG" \
      --query "properties.outputs.containerAppName.value" \
      --output tsv)
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az deployment group show` | Reads the deployed Node.js app name from the infrastructure deployment. |
    | `--name` | Opens the `main` deployment used in Step 02. |
    | `--resource-group` | Searches for that deployment in `rg-nodejs-guide`. |
    | `--query` | Extracts `properties.outputs.containerAppName.value` for `APP_NAME`. |
    | `--output` | Returns only the app-name text so the shell can capture it. |

2. **Set environment variables**

    ```bash
    az containerapp update \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --set-env-vars "LOG_LEVEL=INFO" "FEATURE_FLAG=true"
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp update` | Creates a Node.js revision with the tutorial log level and feature flag. |
    | `--name` | Selects the Node.js app receiving `LOG_LEVEL` and `FEATURE_FLAG`. |
    | `--resource-group` | Applies this environment update within `rg-nodejs-guide`. |
    | `--set-env-vars` | Sets `LOG_LEVEL=INFO` and turns `FEATURE_FLAG` on. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-nodejs-guide-<unique-suffix>",
          "provisioningState": "Succeeded"
        }
        ```

3. **Store and reference a secret**

    ```bash
    az containerapp secret set \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --secrets "db-password=<secret-value>"
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp secret set` | Adds the database password to the Node.js app's secret store. |
    | `--name` | Identifies the app that owns the `db-password` secret. |
    | `--resource-group` | Resolves that app in the Node.js tutorial resource group. |
    | `--secrets` | Stores `<secret-value>` under `db-password`. |

    ???+ example "Expected output"
        ```text
        Containerapp must be restarted in order for secret changes to take effect.
        ```
        ```json
        [
          {
            "name": "db-password"
          }
        ]
        ```

    ```bash
    az containerapp update \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --set-env-vars "DB_PASSWORD=secretref:db-password"
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp update` | Creates a revision that injects the stored password into the Node.js process. |
    | `--name` | Chooses the app whose runtime receives `DB_PASSWORD`. |
    | `--resource-group` | Scopes the secret-reference update to `rg-nodejs-guide`. |
    | `--set-env-vars` | Binds `DB_PASSWORD` to `secretref:db-password` instead of exposing its value. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-nodejs-guide-<unique-suffix>",
          "provisioningState": "Succeeded"
        }
        ```

4. **Configure KEDA HTTP autoscaling**

    ```bash
    az containerapp update \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --min-replicas 0 \
      --max-replicas 10 \
      --scale-rule-name "http-scale" \
      --scale-rule-type "http" \
      --scale-rule-http-concurrency 50
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp update` | Adds HTTP concurrency scaling to the Express service. |
    | `--name` | Targets the Node.js app whose replicas handle incoming requests. |
    | `--resource-group` | Locates the Express workload in `rg-nodejs-guide`. |
    | `--min-replicas` | Allows the service to reach zero replicas when no requests arrive. |
    | `--max-replicas` | Prevents this tutorial workload from exceeding ten replicas. |
    | `--scale-rule-name` | Names the request rule `http-scale`. |
    | `--scale-rule-type` | Chooses the Container Apps HTTP scaler for Express traffic. |
    | `--scale-rule-http-concurrency` | Uses 50 simultaneous requests per replica as the scaling target. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-nodejs-guide-<unique-suffix>",
          "provisioningState": "Succeeded"
        }
        ```

5. **Enable Dapr sidecar**

    ```bash
    az containerapp dapr enable \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --dapr-app-id "$APP_NAME" \
      --dapr-app-port 8000
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp dapr enable` | Attaches and configures a Dapr sidecar for the Node.js app. |
    | `--name` | Selects the same app name used as the Dapr service identity. |
    | `--resource-group` | Finds the sidecar host in `rg-nodejs-guide`. |
    | `--dapr-app-id` | Uses `$APP_NAME` as the service's Dapr application ID. |
    | `--dapr-app-port` | Routes Dapr app-channel traffic to port `8000`. |

    ???+ example "Expected output"
        ```json
        {
          "appId": "ca-nodejs-guide-<unique-suffix>",
          "appPort": 8000,
          "appProtocol": "http",
          "enabled": true
        }
        ```

### Verify configuration in Azure Portal

![ca-nodejs-d38538 | Container App | Containers | Refresh | Send us your feedback | Container | Properties | Environment variables | Health probes | Volume mounts | Container details | Name | ca-nodejs-d38538 | Image source | Azure Container Registry | Authentication | Managed identity | Subscription | Visual Studio Enterprise Subscription | Registry | acrbasicsd38538.azurecr.io | Image | nodejs-sample | Image tag | v1 | Command override | Arguments override | Application | Revisions and replicas | Containers | Scale | Volumes | Settings | Networking | Ingress | Custom domains | CORS | Security | Monitoring | Log stream | Logs | Console | Alerts | Metrics](../../../assets/language-guides/nodejs/tutorial/03-containers-blade.png)

**[Observed]** `ca-nodejs-d38538`. `Container App`. `Containers`. `Refresh`. `Send us your feedback`. `Container`. `Properties`. `Environment variables`. `Health probes`. `Volume mounts`. `Container details`. `Name`. `ca-nodejs-d38538`. `Image source`. `Azure Container Registry`. `Docker Hub or other registries`. `Authentication`. `Managed identity`. `Secrets`. `Identity`. `System assigned`. `Subscription`. `Visual Studio Enterprise Subscription`. `Registry`. `acrbasicsd38538.azurecr.io`. `Image`. `nodejs-sample`. `Image tag`. `v1`. `Command override`. `Arguments override`. `Application`. `Revisions and replicas`. `Containers`. `Scale`. `Volumes`. `Settings`. `Networking`. `Ingress`. `Custom domains`. `CORS`. `Security`. `Monitoring`. `Log stream`. `Logs`. `Console`. `Alerts`. `Metrics`.

**[Inferred]** The `Environment variables` tab appears to map to the same `name=value` pairs supplied via `--set-env-vars` in [Step-by-step](#step-by-step). The `Image` field value `nodejs-sample` and `Image tag` value `v1` appear consistent with the `--image` reference set across [Step-by-step](#step-by-step). The `Registry` field value `acrbasicsd38538.azurecr.io` is consistent with the ACR login server referenced throughout [Step-by-step](#step-by-step). The left-navigation entry `Scale` is consistent with the `--scale-rule-*` levers configurable via the operations referenced in [Step-by-step](#step-by-step).

**[Not Proven]** Additional configuration detail, secret-binding detail, and integration detail are not visible on this view.

## Node.js example: read config safely

In Node.js, environment variables are accessed via `process.env`. Use the `dotenv` package (already included in the reference app) for local development.

```javascript
// src/config.js
const LOG_LEVEL = process.env.LOG_LEVEL || 'INFO';
const FEATURE_FLAG = process.env.FEATURE_FLAG === 'true';
const DB_PASSWORD = process.env.DB_PASSWORD;

module.exports = { LOG_LEVEL, FEATURE_FLAG, DB_PASSWORD };
```

## Advanced Topics

- Use Managed Identity to pull secrets directly from Azure Key Vault.
- Implement a custom KEDA scaler (e.g., Azure Service Bus) for event-driven processing.
- Use Dapr components for state management and pub/sub without writing SDK-specific code.

## See Also

- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)
- [Recipes Index](../recipes/index.md)

## Sources
- [Networking in an Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Azure Container Apps image pull from ACR with managed identity (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry private link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [Manage environment variables on Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Containers (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Manage secrets in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Dapr integration with Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
