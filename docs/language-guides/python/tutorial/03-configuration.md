---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns
    - id: configuration-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/containers
        - https://learn.microsoft.com/en-us/azure/container-apps/environment-variables
        - https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets
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

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, ACR with managed identity pull, and private endpoints for backend services.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
flowchart TD
    accTitle: Production-ready Container Apps context for the Python tutorial
    accDescr: A caller reaches managed ingress and an active Python revision. The app uses managed identity for an Azure Container Registry image pull and reaches backend services through private endpoints whose DNS zones are linked to the virtual network.

    CALLER["Request caller"]
    ACR["Azure Container Registry"]
    KV["Azure Key Vault"]
    STORAGE["Storage account"]
    ENTRA["Microsoft Entra ID"]
    DNS["Private DNS zones<br/>linked to the VNet"]

    subgraph VNET["Customer virtual network"]
        INFRA["Dedicated Container Apps<br/>infrastructure subnet"]
        subgraph PESUBNET["Private endpoint subnet"]
            PE_ACR["ACR private endpoint"]
            PE_KV["Key Vault private endpoint"]
            PE_STORAGE["Storage private endpoint"]
        end
    end

    subgraph ENV["Managed Container Apps environment"]
        INGRESS["Managed Envoy ingress<br/>TLS and request routing"]
        APP["Container app<br/>Python"]
        REVISION["Active revision<br/>immutable app version"]
        REPLICAS["Revision replicas<br/>running instances"]
    end

    CALLER ==>|"HTTPS request"| INGRESS
    INGRESS ==>|"Routed request"| REVISION
    INFRA -.->|"Environment VNet integration"| APP
    APP -.-> REVISION
    REVISION ==>|"Serve request"| REPLICAS
    REPLICAS -.->|"Managed identity"| ENTRA
    ENTRA -.->|"Registry authorization"| ACR
    ACR ==>|"Image pull"| PE_ACR
    PE_ACR ==>|"Private connection"| REPLICAS
    REPLICAS ==>|"Private connection"| PE_KV
    PE_KV ==>|"Secret retrieval"| KV
    REPLICAS ==>|"Private connection"| PE_STORAGE
    PE_STORAGE ==>|"Data access"| STORAGE
    DNS -.->|"Name resolution"| PE_ACR
    DNS -.->|"Name resolution"| PE_KV
    DNS -.->|"Name resolution"| PE_STORAGE

    LEGEND["Arrow key<br/>thick = request or data transport<br/>dotted = identity, authorization, DNS, or logical association"]
```

*Figure: The tutorial's shared production context. The Container Apps environment is a managed logical boundary integrated with a dedicated subnet; ACR, Key Vault, Storage, private DNS zones, and Microsoft Entra ID remain separate Azure resources.*

## Configuration Flow

<!-- diagram-id: configuration-flow -->
```mermaid
flowchart TD
    accTitle: Container Apps configuration flow for Python
    accDescr: An operator defines plain environment variables or application-level secrets. A revision template references those values, a new revision receives them at runtime, and the Python app reads the resulting environment variables.

    OPERATOR["Operator or deployment workflow"]
    PLAIN["Plain environment variable<br/>name and value"]
    SECRET["Application-level secret<br/>direct value or Key Vault reference"]
    TEMPLATE["Revision template<br/>container environment variables"]
    REFERENCE["Secret reference<br/>secretref:secret-name"]
    REVISION["New revision"]
    APP["Python app<br/>reads runtime environment"]

    OPERATOR -->|"Set non-sensitive value"| PLAIN
    OPERATOR -->|"Define sensitive value"| SECRET
    PLAIN --> TEMPLATE
    SECRET -.->|"Available to revisions"| REFERENCE
    REFERENCE --> TEMPLATE
    TEMPLATE -->|"Revision-scope change"| REVISION
    REVISION -->|"Load at runtime"| APP

    LEGEND["Arrow key<br/>solid = configuration flow<br/>dotted = application-level secret availability"]
```

*Figure: Environment-variable changes are revision-scoped, while secrets are application-scoped. A secret becomes runtime configuration only when the revision template references it.*

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

    | Command | Purpose |
    |---|---|
    | `APP_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RG" --query "properties.outputs.containerAppName.value" --output tsv)` | Captures the existing Container App name from the deployment outputs so configuration changes apply to the correct Python app. |
    | `ACA_ENV_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RG" --query "properties.outputs.containerAppEnvName.value" --output tsv)` | Captures the environment name from the same deployment so later config and secret examples stay aligned with the deployed environment. |
    | `ACR_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RG" --query "properties.outputs.containerRegistryName.value" --output tsv)` | Captures the registry name used by the app image so subsequent configuration and deployment examples reference the same registry. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp secret set ...` | Manages Container Apps secrets without exposing secret values in plain configuration. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

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

   | Command | Why it is used |
   |---|---|
   | `az acr repository list ...` | Inspects or manages repositories and tags inside Azure Container Registry. |

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

   | Command | Why it is used |
   |---|---|
   | `az containerapp dapr enable ...` | Configures Dapr sidecar settings for the Container App. |

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
- [Private endpoints and DNS for Container Apps environments (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns)
- [Manage environment variables on Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Containers (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/containers)
- [Manage secrets in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
