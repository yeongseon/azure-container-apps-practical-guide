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
    accTitle: Production-ready Container Apps context for the Python tutorial
    accDescr: Client requests and responses pass through managed ingress to Python replicas. The customer VNet contains infrastructure and private-endpoint subnets associated with the environment and ACR private endpoint. Managed identity is assigned to the app, and platform provisioning exchanges image pull requests and layer responses with ACR through that endpoint.
    CALLER(["Client"])
    VNET["Customer VNet<br/>infra + PE subnets"]
    IDENTITY["Managed identity"]
    PE_ACR["ACR PE"]
    ACR["ACR"]
    DNS["ACR DNS zone"]
    subgraph ENV["ACA environment"]
        INGRESS["Ingress"]
        APP["Container app<br/>Python"]
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

*Figure: Client traffic crosses managed ingress to Python replicas. The customer VNet's infrastructure subnet associates with the environment, and its private-endpoint subnet associates with the ACR private endpoint. Managed identity is assigned to the app and authorizes registry pulls; platform provisioning sends pull requests and receives image layers through that endpoint.*

## Configuration Flow

<!-- diagram-id: configuration-flow -->
```mermaid
flowchart TD
    accTitle: Container Apps configuration flow for Python
    accDescr: An operator defines environment variables, application-level secrets, and Dapr settings. The revision template delivers referenced values to a new revision, while the Dapr settings enable a sidecar that communicates with the Python app on its configured port.

    OPERATOR["Operator or deployment workflow"]
    PLAIN["Plain environment variable<br/>name and value"]
    SECRET["Application-level secret<br/>direct value or Key Vault reference"]
    TEMPLATE["Revision template<br/>container environment variables"]
    REFERENCE["Secret reference<br/>secretref:secret-name"]
    REVISION["New revision"]
    APP["Python app<br/>reads runtime environment"]
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

1. **Set standard variables (reuse Bicep outputs from Step 02)**

    ```bash
    RG="rg-aca-python-demo"
    BASE_NAME="pycontainer"
    DEPLOYMENT_NAME="main"

    APP_NAME=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerAppName.value" \
     --output tsv)

    ACA_ENV_NAME=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerAppEnvName.value" \
     --output tsv)

    ACR_NAME=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerRegistryName.value" \
     --output tsv)
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az deployment group show` | Reads the Python app, environment, and registry names produced by Step 02. |
    | `--name` | Selects the `main` infrastructure deployment for each output lookup. |
    | `--resource-group` | Opens the deployment in `rg-aca-python-demo`. |
    | `--query` | Chooses the app, environment, or registry output needed by the current shell assignment. |
    | `--output` | Emits each output as plain tab-separated text without JSON quoting. |

    ???+ example "Expected output"
        The commands above set shell variables silently. Verify them with:

        ```bash
        echo "APP_NAME=$APP_NAME"
        echo "ACA_ENV_NAME=$ACA_ENV_NAME"
        echo "ACR_NAME=$ACR_NAME"
        ```

        ```text
        APP_NAME=<your-app-name>
        ACA_ENV_NAME=<your-env-name>
        ACR_NAME=<acr-name>
        ```

2. **Set environment variables**

    ```bash
    az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
      --set-env-vars "LOG_LEVEL=INFO" "FEATURE_FLAG=true"
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp update` | Creates a Python app revision with the sample log level and feature flag. |
    | `--name` | Identifies the Flask app receiving the runtime settings. |
    | `--resource-group` | Applies the settings to the app in `rg-aca-python-demo`. |
    | `--set-env-vars` | Adds `LOG_LEVEL=INFO` and `FEATURE_FLAG=true` to the container environment. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-pycontainer-<unique-suffix>",
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
    | `az containerapp secret set` | Stores the Python sample's database password at application scope. |
    | `--name` | Selects the Python app that will own `db-password`. |
    | `--resource-group` | Finds the secret owner in `rg-aca-python-demo`. |
    | `--secrets` | Creates or replaces `db-password` with the supplied sample value. |

    ???+ example "Expected output"
        ```text
        Containerapp must be restarted in order for secret changes to take effect.
        ```
        ```json
        [
          {
            "name": "appinsights-connection-string"
          },
          {
            "name": "registry-password"
          },
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
    | `az containerapp update` | Creates a revision that makes the stored password available to Python code. |
    | `--name` | Targets the Flask app whose environment receives the secret reference. |
    | `--resource-group` | Restricts the update to the Python tutorial resource group. |
    | `--set-env-vars` | Maps `DB_PASSWORD` to `secretref:db-password` for `os.environ`. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-pycontainer-<unique-suffix>",
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
    | `az containerapp update` | Configures HTTP-driven replica scaling for the Flask endpoint. |
    | `--name` | Selects the Python API whose request load controls scaling. |
    | `--resource-group` | Locates that API in `rg-aca-python-demo`. |
    | `--min-replicas` | Allows scale-to-zero during idle periods. |
    | `--max-replicas` | Caps this demonstration at ten replicas. |
    | `--scale-rule-name` | Saves the rule under the name `http-scale`. |
    | `--scale-rule-type` | Selects request-based HTTP scaling. |
    | `--scale-rule-http-concurrency` | Targets 50 concurrent requests on each Python replica. |

    ???+ example "Expected output"
        ```json
        {
          "name": "ca-pycontainer-<unique-suffix>",
          "provisioningState": "Succeeded"
        }
        ```

!!! tip "Choosing HTTP concurrency threshold"
    A lower value (e.g., 50) triggers scale-out more aggressively, suitable for latency-sensitive APIs. A higher value (e.g., 100, used in `infra/main.bicep`) delays scale-out for cost efficiency. Choose based on your latency SLO and budget. The Bicep template in `infra/main.bicep` defaults to `maxReplicas=3` for cost safety. Override with `--parameters maxReplicas=10` when deploying infrastructure.

5. **Configure queue-driven KEDA scaling (example)**

    ```bash
    az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --scale-rule-name "queue-scale" \
     --scale-rule-type "azure-servicebus" \
     --scale-rule-metadata "queueName=orders" "namespace=sb-namespace" \
     --scale-rule-auth "connection=servicebus-connection"
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp update` | Adds an Azure Service Bus queue scaler to the Python worker example. |
    | `--name` | Chooses the app that processes messages from the orders queue. |
    | `--resource-group` | Applies queue scaling within `rg-aca-python-demo`. |
    | `--scale-rule-name` | Registers the scaler as `queue-scale`. |
    | `--scale-rule-type` | Uses the `azure-servicebus` KEDA scaler. |
    | `--scale-rule-metadata` | Points the scaler to queue `orders` in namespace `sb-namespace`. |
    | `--scale-rule-auth` | Resolves the scaler's `connection` setting from `servicebus-connection`. |

    ???+ example "Expected output"
        ```json
        {
          "name": "<your-app-name>",
          "provisioningState": "Succeeded"
        }
        ```

    Verify pushed repositories in ACR:

    ```bash
    az acr repository list \
     --name "$ACR_NAME" \
     --output json
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az acr repository list` | Lists image repositories to verify the API and job images reached ACR. |
    | `--name` | Queries the registry discovered earlier as `$ACR_NAME`. |
    | `--output` | Formats the repository-name collection as JSON for comparison with the expected pair. |

    ???+ example "Expected output"
        ```json
        ["myapp", "myapp-job"]
        ```

6. **Enable Dapr sidecar**

    ```bash
    az containerapp dapr enable \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --dapr-app-id "$APP_NAME" \
     --dapr-app-port 8000
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az containerapp dapr enable` | Enables the Python app's Dapr sidecar and app channel. |
    | `--name` | Selects the Python Container App that hosts the sidecar. |
    | `--resource-group` | Resolves the sidecar host in `rg-aca-python-demo`. |
    | `--dapr-app-id` | Reuses `$APP_NAME` as the Dapr service identifier. |
    | `--dapr-app-port` | Sends Dapr-to-Flask requests to port `8000`. |

    ???+ example "Expected output"
        ```json
        {
          "appId": "ca-pycontainer-<unique-suffix>",
          "appPort": 8000,
          "appProtocol": "http",
          "enableApiLogging": false,
          "enabled": true,
          "httpMaxRequestSize": null,
          "httpReadBufferSize": null,
          "logLevel": "info"
        }
        ```

### Verify configuration in Azure Portal

![ca-sample-d38538 | Containers | Properties | Environment variables | Health probes | Volume mounts | Container details | Name | Image source | Image type | Registry login server | Image and tag | Command override | Arguments override | Container resource allocation | CPU cores | Memory (Gi) | Application | Revisions and replicas | Containers | Scale | Volumes | Settings | Networking | Ingress | Custom domains | CORS | Security | Monitoring | Log stream | Logs | Console | Alerts | Metrics](../../../assets/language-guides/python/tutorial/03-containers-blade.png)

**[Observed]** `ca-sample-d38538`. `Container App`. `Containers`. `Refresh`. `Send us your feedback`. `Based on revision`. `ca-sample-d38538--0uzoi59`. `Container`. `Create new container`. `Delete this container`. `Properties`. `Environment variables`. `Health probes`. `Volume mounts`. `Container details`. `Name`. `Image source`. `Azure Container Registry`. `Docker Hub or other registries`. `Image type`. `Public`. `Private`. `Registry login server`. `mcr.microsoft.com`. `Image and tag`. `k8se/quickstart:latest`. `Command override`. `Arguments override`. `Container resource allocation`. `CPU cores`. `0.5`. `Min: 0.1, Max: 4`. `Memory (Gi)`. `1`. `Min: 0.1, Max: 8`. `Save as a new revision`. `Discard`. `Application`. `Revisions and replicas`. `Containers`. `Scale`. `Volumes`. `Settings`. `Networking`. `Ingress`. `Custom domains`. `CORS`. `Security`. `Monitoring`. `Log stream`. `Logs`. `Console`. `Alerts`. `Metrics`.

**[Inferred]** The `Environment variables` tab appears to map to the same `name=value` pairs supplied via `--set-env-vars` in [Step-by-step](#step-by-step) Step 2. The left-navigation entry `Scale` is consistent with the `--scale-rule-*` levers configured in [Step-by-step](#step-by-step) Steps 4 and 5. The `Based on revision` field is consistent with the `az containerapp update` operations issued throughout [Step-by-step](#step-by-step). The `Save as a new revision` action is consistent with the revision-creating effect of `az containerapp update` invoked across [Step-by-step](#step-by-step).

**[Not Proven]** Additional configuration detail, secret-binding detail, and integration detail are not visible on this view.

## Python example: read config safely

```python
import os

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
FEATURE_FLAG = os.environ.get("FEATURE_FLAG", "false").lower() == "true"
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
```

## Advanced Topics

- Use Key Vault + managed identity instead of direct secret values.
- Tune KEDA thresholds differently for API and background worker apps.
- Add Dapr pub/sub and state store components for event-driven workflows.

## See Also
- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)
- [Dapr Integration Recipe](../recipes/dapr-integration.md)

## Sources
- [Networking in an Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Azure Container Apps image pull from ACR with managed identity (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry private link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [Manage environment variables on Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Containers (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Manage secrets in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Dapr integration with Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
