---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/azure-resource-manager-api-spec
        - https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
    - id: infrastructure-lifecycle
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/azure-resource-manager-api-spec
        - https://learn.microsoft.com/azure/templates/microsoft.app/containerapps
---

# 05 - Infrastructure as Code with Bicep

Use Bicep to define your Azure Container Apps platform consistently across environments. This step focuses on repeatable provisioning and safe updates.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, ACR with managed identity pull, and private endpoints for backend services.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
flowchart TD
    INET[Internet] -->|HTTPS| CA["Container App\nConsumption\nLinux Node 18 LTS"]

    subgraph VNET["VNet 10.0.0.0/16"]
        subgraph ENV_SUB["Environment Subnet 10.0.0.0/23\nDelegation: Microsoft.App/environments"]
            CAE[Container Apps Environment]
            CA
        end
        subgraph PE_SUB["Private Endpoint Subnet 10.0.2.0/24"]
            PE_ACR[PE: ACR]
            PE_KV[PE: Key Vault]
            PE_ST[PE: Storage]
        end
    end

    PE_ACR --> ACR[Azure Container Registry]
    PE_KV --> KV[Key Vault]
    PE_ST --> ST[Storage Account]

    subgraph DNS[Private DNS Zones]
        DNS_ACR[privatelink.azurecr.io]
        DNS_KV[privatelink.vaultcore.azure.net]
        DNS_ST[privatelink.blob.core.windows.net]
    end

    PE_ACR -.-> DNS_ACR
    PE_KV -.-> DNS_KV
    PE_ST -.-> DNS_ST

    CA -.->|System-Assigned MI| ENTRA[Microsoft Entra ID]
    CAE --> LOG[Log Analytics]
    CA --> AI[Application Insights]

    style CA fill:#107c10,color:#fff
    style VNET fill:#E8F5E9,stroke:#4CAF50
    style DNS fill:#E3F2FD
```

## Infrastructure Lifecycle

<!-- diagram-id: infrastructure-lifecycle -->
```mermaid
graph LR
    WRITE[Write Bicep] --> VAL[Validate]
    VAL --> WHAT[What-If]
    WHAT --> DEPLOY[Deploy]
    DEPLOY --> VERIFY[Verify Outputs]
```

## Prerequisites

- Completed [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- Bicep files under `infra/`

!!! info "Naming Convention"
    The shared `infra/main.bicep` template generates unique resource names using `uniqueString(resourceGroup().id)` (e.g., `ca-nodejs-guide-abc123def`). Earlier tutorials in this guide use simplified names like `ca-nodejs-guide` for readability. When deploying via Bicep, always capture actual names from deployment outputs using `az deployment group show`.

!!! tip "Run validate and what-if before every apply"
    Treat `az deployment group validate` and `az deployment group what-if` as required safety checks to prevent accidental production-impacting infrastructure changes.

## Step-by-step

1. **Set standard variables**

    ```bash
    RG="rg-nodejs-guide"
    BASE_NAME="nodejs-guide"
    LOCATION="koreacentral"
    DEPLOYMENT_NAME="main"
    ```

2. **Validate the Bicep template**

    ```bash
    az deployment group validate \
      --resource-group "$RG" \
      --template-file infra/main.bicep \
      --parameters baseName="$BASE_NAME" location="$LOCATION"
    ```

    ???+ example "Expected output"
        ```json
        {
          "status": "Succeeded",
          "error": null
        }
        ```

3. **Preview changes with what-if**

    ```bash
    az deployment group what-if \
      --resource-group "$RG" \
      --template-file infra/main.bicep \
      --parameters baseName="$BASE_NAME" location="$LOCATION"
    ```

    ???+ example "Expected output"
        ```text
        Resource and property changes are indicated with these symbols:
          + Create
          ~ Modify

        The deployment will update the following scope:
        Scope: /subscriptions/<subscription-id>/resourceGroups/rg-nodejs-guide

          ~ Microsoft.App/containerApps/<your-app-name> [2024-03-01]
            ~ properties.template.containers[0].image: "<acr-name>.azurecr.io/nodejs-guide:v1"
        ```

4. **Deploy infrastructure**

    ```bash
    az deployment group create \
      --name "$DEPLOYMENT_NAME" \
      --resource-group "$RG" \
      --template-file infra/main.bicep \
      --parameters baseName="$BASE_NAME" location="$LOCATION"
    ```

    ???+ example "Expected output"
        ```json
        {
          "id": "/subscriptions/<subscription-id>/resourceGroups/rg-nodejs-guide/providers/Microsoft.Resources/deployments/main",
          "name": "main",
          "properties": {
            "provisioningState": "Succeeded",
            "outputs": {
              "containerAppName": { "type": "String", "value": "ca-nodejs-guide-<unique-suffix>" },
              "containerAppEnvName": { "type": "String", "value": "cae-nodejs-guide-<unique-suffix>" },
              "containerRegistryName": { "type": "String", "value": "crnodejsguide<unique-suffix>" },
              "containerAppUrl": { "type": "String", "value": "https://ca-nodejs-guide-<unique-suffix>.<env-suffix>.koreacentral.azurecontainerapps.io" }
            }
          }
        }
        ```

        !!! note "Unique suffix"
            The `<unique-suffix>` is generated by `uniqueString(resourceGroup().id)` in Bicep to ensure globally unique resource names.

5. **Verify outputs and key resources**

    ```bash
    az deployment group show \
      --resource-group "$RG" \
      --name "$DEPLOYMENT_NAME" \
      --query properties.outputs
    ```

    ???+ example "Expected output"
        ```json
        {
          "containerAppName": {
            "type": "String",
            "value": "ca-nodejs-guide-<unique-suffix>"
          },
          "containerAppEnvName": {
            "type": "String",
            "value": "cae-nodejs-guide-<unique-suffix>"
          },
          "containerRegistryName": {
            "type": "String",
            "value": "crnodejsguide<unique-suffix>"
          },
          "containerRegistryLoginServer": {
            "type": "String",
            "value": "crnodejsguide<unique-suffix>.azurecr.io"
          },
          "containerAppUrl": {
            "type": "String",
            "value": "https://ca-nodejs-guide-<unique-suffix>.<env-suffix>.koreacentral.azurecontainerapps.io"
          }
        }
        ```

## Example Bicep snippet (environment + logs)

```bicep
param baseName string
var uniqueSuffix = uniqueString(resourceGroup().id)
var containerAppEnvName = 'cae-${baseName}-${uniqueSuffix}'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${baseName}-${uniqueSuffix}'
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: resourceGroup().location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}
```

## Advanced Topics

- Use Node.js specific health probe configurations in your Bicep templates.
- Define environment variables and secrets for your Express app in the Container App resource.
- Automate the entire deployment process with GitHub Actions using the Bicep template.

!!! warning "Avoid out-of-band portal edits"
    Manual portal changes can create drift from your Bicep templates. Prefer template updates and redeployment so environments remain reproducible and auditable.

## CLI Alternative (No Bicep)

Use these commands when you need an imperative deployment path without Bicep.

### Step 1: Set variables

```bash
RG="rg-express-containerapp"
APP_NAME="ca-express-demo"
BASE_NAME="express-app"
ENVIRONMENT_NAME="cae-express-demo"
ACR_NAME="crexpressdemo"
LOG_NAME="log-express-demo"
LOCATION="koreacentral"
```

???+ example "Expected output"
    ```text
    Variables set for rg-express-containerapp, ca-express-demo, and crexpressdemo.
    ```

### Step 2: Create resource group and Log Analytics workspace

```bash
az group create --name "$RG" --location "$LOCATION"

az monitor log-analytics workspace create --resource-group "$RG" --workspace-name "$LOG_NAME" --location "$LOCATION"

LOG_ID=$(az monitor log-analytics workspace show --resource-group "$RG" --workspace-name "$LOG_NAME" --query customerId --output tsv)
```

???+ example "Expected output"
    ```json
    {
      "resourceGroup": "rg-express-containerapp",
      "workspace": "log-express-demo",
      "workspaceId": "11111111-2222-3333-4444-555555555555",
      "provisioningState": "Succeeded"
    }
    ```

### Step 3: Create ACR and Container Apps environment

```bash
az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic

az containerapp env create --resource-group "$RG" --name "$ENVIRONMENT_NAME" --location "$LOCATION" --logs-workspace-id "$LOG_ID"

az acr build --registry "$ACR_NAME" --image "$BASE_NAME:v1" ./apps/nodejs
```

???+ example "Expected output"
    ```text
    ACR crexpressdemo created.
    Container Apps environment cae-express-demo provisioned.
    Image pushed: crexpressdemo.azurecr.io/express-app:v1
    ```

### Step 4: Create Container App with environment variables

```bash
az containerapp create --resource-group "$RG" --name "$APP_NAME" --environment "$ENVIRONMENT_NAME" --image "$ACR_NAME.azurecr.io/$BASE_NAME:v1" --target-port 8000 --ingress external --env-vars NODE_ENV=production --query "properties.configuration.ingress.fqdn"
```

???+ example "Expected output"
    ```text
    "ca-express-demo.gentlehill-1a2b3c4d.koreacentral.azurecontainerapps.io"
    ```

### Step 5: Validate configuration

```bash
az containerapp show --resource-group "$RG" --name "$APP_NAME" --query "{state:properties.provisioningState,fqdn:properties.configuration.ingress.fqdn,env:properties.template.containers[0].env}"
```

???+ example "Expected output"
    ```json
    {
      "state": "Succeeded",
      "fqdn": "ca-express-demo.gentlehill-1a2b3c4d.koreacentral.azurecontainerapps.io",
      "env": [
        {
          "name": "NODE_ENV",
          "value": "production"
        }
      ]
    }
    ```

## See Also
- [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- [Managed Identity Recipe](../../../platform/identity-and-secrets/managed-identity.md)

## Sources
- [Azure Resource Manager API spec (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/azure-resource-manager-api-spec)
- [Bicep resource definition: Microsoft.App/containerApps (Microsoft Learn)](https://learn.microsoft.com/azure/templates/microsoft.app/containerapps)
