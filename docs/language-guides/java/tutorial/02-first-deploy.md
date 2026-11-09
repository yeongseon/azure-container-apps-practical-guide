---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints
    - id: deployment-workflow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 02 - First Deploy to Azure

This guide walks you through the initial deployment of your Spring Boot application to Azure Container Apps. We'll use the Azure CLI to create a Container Registry, build the image in the cloud, and provision a Container App environment.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, managed identity image pull, and a private endpoint for ACR.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "12px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 100}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Java deployment tutorial
    accDescr: A client exchanges requests and responses with Java replicas through managed ingress. The infrastructure subnet associates with the environment, an identity is assigned to the app, and revision provisioning exchanges image requests and layer responses with ACR through its private endpoint.
    CLIENT["Client"]
    subgraph ENV["Container Apps<br/>environment"]
        direction TD
        INGRESS["Managed ingress"]
        APP["Container app<br/>Java 21"]
        PROVISION["Revision provisioning<br/>(platform)"]
        REPLICAS["Running replicas"]
    end
    INFRA["Subnet"]
    IDENTITY["Identity"]
    PE_ACR["ACR private<br/>endpoint"]
    ACR["Azure Container<br/>Registry"]
    DNS["ACR DNS zone"]
    CLIENT ==>|"Req"| INGRESS
    INGRESS ==>|"Resp"| CLIENT
    INGRESS ==>|"Req"| REPLICAS
    REPLICAS ==>|"Resp"| INGRESS
    APP -.-> REPLICAS
    APP -.-> IDENTITY
    INFRA -.-> ENV
    PROVISION ==>|"Pull"| PE_ACR
    PE_ACR ==>|"Req"| ACR
    ACR ==>|"Resp"| PE_ACR
    PE_ACR ==>|"Layers"| PROVISION
    DNS -.-> PE_ACR
    CLIENT ~~~ INFRA ~~~ INGRESS ~~~ APP ~~~ IDENTITY ~~~ REPLICAS ~~~ PROVISION ~~~ DNS ~~~ PE_ACR ~~~ ACR
    linkStyle 12,13,14,15,16,17,18,19,20 opacity:0
```

*Figure: The infrastructure subnet integrates with the environment, the identity is assigned to the container app, and platform revision provisioning exchanges image requests and layer responses with ACR through its private endpoint.*

## Deployment Workflow

<!-- diagram-id: deployment-workflow -->
```mermaid
flowchart TD
    accTitle: First Java deployment workflow
    accDescr: ACR Tasks builds Spring Boot source into an image, the Container App creates a revision from that image, and a caller verifies the health endpoint through managed ingress.
    SOURCE["Spring Boot source<br/>and Dockerfile"]
    BUILD["ACR Task<br/>build image"]
    IMAGE["ACR image<br/>java-guide:latest"]
    ENVIRONMENT["Container Apps environment"]
    APP["Container app<br/>select image"]
    REVISION["New immutable revision"]
    INGRESS["Managed ingress"]
    REPLICAS["Ready revision replicas"]
    CALLER["Verification caller"]
    SOURCE -->|"Submit build context"| BUILD
    BUILD -->|"Push image"| IMAGE
    ENVIRONMENT -.->|"Hosts app"| APP
    IMAGE -->|"Set image reference"| APP
    APP -->|"Create revision"| REVISION
    REVISION -.->|"Logical runtime instances"| REPLICAS
    CALLER ==>|"HTTPS GET /health"| INGRESS
    INGRESS ==>|"Routed request"| REPLICAS
    REPLICAS ==>|"Health response"| INGRESS
    INGRESS ==>|"HTTPS response"| CALLER
```

*Figure: Build the Spring Boot image in ACR, create a revision in the Container Apps environment, and verify the deployed replicas through managed ingress.*

## Prerequisites

- Azure CLI 2.57+
- Active Azure Subscription
- Terminal with common variables set

## Step 1: Environment Setup

Before running commands, set your common variables to ensure consistency.

```bash
# Variables
RG="rg-java-guide"
LOCATION="koreacentral"
ACA_ENV_NAME="cae-java-guide"
ACR_NAME="crjava$(date +%s)"
APP_NAME="ca-java-guide"
```

## Step 2: Create Infrastructure

1. **Create a Resource Group**

    ```bash
    az group create --name $RG --location $LOCATION
    ```

    | Command | Why it is used |
    |---|---|
    | `az group create ...` | Creates the isolated resource group used by the example. |

2. **Create a Container Registry (ACR)**

    ```bash
    az acr create --resource-group $RG --name $ACR_NAME --sku Basic
    ```

    | Command | Why it is used |
    |---|---|
    | `az acr create --resource-group ...` | Creates Azure Container Registry for container image storage. |

3. **Create a Container Apps Environment**

    ```bash
    az containerapp env create --resource-group $RG --name $ACA_ENV_NAME --location $LOCATION
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp env create ...` | Creates the managed Container Apps environment that hosts the app replicas. |

## Step 3: Build and Push Image

Instead of building locally and pushing, use ACR Tasks to build the image directly in Azure from your source code.

```bash
cd apps/java-springboot
az acr build --registry $ACR_NAME --image java-guide:latest .
```

| Command | Why it is used |
|---|---|
| `az acr build --registry ...` | Builds and pushes the container image to Azure Container Registry. |

???+ example "Expected output"
    ```text
    Packing source code into tar to upload...
    Uploading 1.23 MB to registry...
    Building image...
    [build 1/5] FROM docker.io/library/maven:3.9-eclipse-temurin-21
    ... (Maven build output)
    [stage-1 3/3] COPY --from=build /app/target/*.jar app.jar
    Run ID: ce1 was successful after 1m 15s
    ```

## Step 4: Create the Container App

Deploy the application using the image from your ACR. We'll configure it to listen on port `8000` with public ingress.

```bash
az containerapp create \
  --resource-group $RG \
  --name $APP_NAME \
  --environment $ACA_ENV_NAME \
  --image $ACR_NAME.azurecr.io/java-guide:latest \
  --target-port 8000 \
  --ingress external \
  --query "properties.configuration.ingress.fqdn"
```

| Command | Why it is used |
|---|---|
| `az containerapp create ...` | Creates the Container App with the documented image, ingress, scale, and environment settings. |

???+ example "Expected output"
    ```text
    "<your-app-name>.<environment-hash>.<region>.azurecontainerapps.io"
    ```

## Step 5: Verification

1. **Check the application URL**

    Visit the FQDN returned by the previous command. You should see the application's home page.

2. **Verify health endpoint**

    ```bash
    FQDN=$(az containerapp show --resource-group $RG --name $APP_NAME --query "properties.configuration.ingress.fqdn" --output tsv)
    curl https://$FQDN/health
    ```

    | Command | Purpose |
    |---|---|
    | `FQDN=$(az containerapp show --resource-group $RG --name $APP_NAME --query "properties.configuration.ingress.fqdn" --output tsv)` | Reads the live ingress hostname from Azure so the verification request targets the actual deployed Java app endpoint. |
    | `curl https://$FQDN/health` | Calls the health endpoint to confirm the deployed Spring Boot revision is reachable and healthy. |

    ???+ example "Expected output"
        ```json
        {"timestamp":"2026-04-04T16:12:58.973766483Z","status":"healthy"}
        ```

3. **Verify info endpoint**

    ```bash
    curl https://$FQDN/info
    ```

    ???+ example "Expected output"
        ```json
        {"runtime":{"vendor":"Eclipse Adoptium","java":"21.0.10"},"app":"azure-container-apps-java-guide","version":"1.0.0"}
        ```

## Deployment Verification Checklist

- [x] ACR Image build succeeded
- [x] Container App is in `Provisioned` state
- [x] Ingress FQDN is accessible
- [x] `/health` returns HTTP 200

!!! note "Managed Identity for ACR Pull"
    In this first deployment, the CLI handles authentication between ACR and Azure Container Apps. For production-ready templates, use a User-Assigned Managed Identity for the container app to pull images from the registry.

## CLI Alternative (No Bicep)

Use these commands to deploy without Bicep templates. This creates the same resources imperatively.

### Step 1: Set variables

```bash
RG="rg-springboot-containerapp"
LOCATION="koreacentral"
APP_NAME="ca-springboot-demo"
BASE_NAME="springboot-app"
ACA_ENV_NAME="cae-springboot-demo"
ACR_NAME="crspringbootdemo"
LOG_NAME="log-springboot-demo"
```

???+ example "Expected output"
    ```text
    Variables set for resource group, logging workspace, registry, environment, and app.
    ```

### Step 2: Create resource group

```bash
az group create --name $RG --location $LOCATION
```

| Command | Why it is used |
|---|---|
| `az group create ...` | Creates the isolated resource group used by the example. |

???+ example "Expected output"
    ```json
    {
      "id": "/subscriptions/<subscription-id>/resourceGroups/rg-springboot-containerapp",
      "location": "koreacentral",
      "name": "rg-springboot-containerapp",
      "properties": {
        "provisioningState": "Succeeded"
      }
    }
    ```

### Step 3: Create Log Analytics workspace

```bash
az monitor log-analytics workspace create --resource-group $RG --workspace-name $LOG_NAME --location $LOCATION
```

| Command | Why it is used |
|---|---|
| `az monitor log-analytics ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

???+ example "Expected output"
    ```json
    {
      "customerId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "id": "/subscriptions/<subscription-id>/resourceGroups/rg-springboot-containerapp/providers/Microsoft.OperationalInsights/workspaces/log-springboot-demo",
      "location": "koreacentral",
      "name": "log-springboot-demo",
      "provisioningState": "Succeeded"
    }
    ```

### Step 4: Create Azure Container Registry

```bash
az acr create --resource-group $RG --name $ACR_NAME --sku Basic
```

| Command | Why it is used |
|---|---|
| `az acr create --resource-group ...` | Creates Azure Container Registry for container image storage. |

???+ example "Expected output"
    ```json
    {
      "id": "/subscriptions/<subscription-id>/resourceGroups/rg-springboot-containerapp/providers/Microsoft.ContainerRegistry/registries/crspringbootdemo",
      "loginServer": "crspringbootdemo.azurecr.io",
      "name": "crspringbootdemo",
      "provisioningState": "Succeeded",
      "sku": {
        "name": "Basic"
      }
    }
    ```

### Step 5: Create Container Apps environment

```bash
LOG_ID=$(az monitor log-analytics workspace show --resource-group $RG --workspace-name $LOG_NAME --query customerId --output tsv)
LOG_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group $RG --workspace-name $LOG_NAME --query primarySharedKey --output tsv)
az containerapp env create --resource-group $RG --name $ACA_ENV_NAME --location $LOCATION --logs-workspace-id $LOG_ID --logs-workspace-key $LOG_KEY
```

| Command | Why it is used |
|---|---|
| `az monitor log-analytics ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

???+ example "Expected output"
    ```json
    {
      "id": "/subscriptions/<subscription-id>/resourceGroups/rg-springboot-containerapp/providers/Microsoft.App/managedEnvironments/cae-springboot-demo",
      "location": "koreacentral",
      "name": "cae-springboot-demo",
      "provisioningState": "Succeeded"
    }
    ```

### Step 6: Build and push image with ACR Tasks

```bash
az acr build --registry $ACR_NAME --image $BASE_NAME:v1 ./apps/java-springboot
```

| Command | Why it is used |
|---|---|
| `az acr build --registry ...` | Builds and pushes the container image to Azure Container Registry. |

???+ example "Expected output"
    ```text
    Packing source code into tar to upload...
    Uploading archived source code from '/tmp/build.tar.gz'...
    Queued a build with ID: cf1
    Run ID: cf1 was successful after 1m 10s
    ```

### Step 7: Create Container App

```bash
az containerapp create --resource-group $RG --name $APP_NAME --environment $ACA_ENV_NAME --image $ACR_NAME.azurecr.io/$BASE_NAME:v1 --target-port 8000 --ingress external --query "properties.configuration.ingress.fqdn"
```

| Command | Why it is used |
|---|---|
| `az containerapp create --resource-group ...` | Creates the Container App with the documented image, ingress, scale, and environment settings. |

???+ example "Expected output"
    ```text
    "<container-app-fqdn>"
    ```

### Step 8: Verify deployment

```bash
FQDN=$(az containerapp show --resource-group $RG --name $APP_NAME --query "properties.configuration.ingress.fqdn" --output tsv)
curl https://$FQDN/health
```

| Command | Purpose |
|---|---|
| `FQDN=$(az containerapp show --resource-group $RG --name $APP_NAME --query "properties.configuration.ingress.fqdn" --output tsv)` | Reads the app's current ingress hostname from Azure so the final deployment check uses the live endpoint instead of a copied URL. |
| `curl https://$FQDN/health` | Verifies the health endpoint on the deployed Java app before you move on to portal-based validation. |

???+ example "Expected output"
    ```json
    {"timestamp":"2026-04-09T09:14:22.103125Z","status":"healthy"}
    ```

### Step 9: Verify deployment in Azure Portal

![ca-java-d38538 | Container App | Overview | Stop | Refresh | Delete | Send us your feedback | Essentials | Resource group | rg-aca-basics-d38538 | Status | Running | Location | Korea Central | Subscription | Visual Studio Enterprise Subscription | Subscription ID | 00000000-0000-0000-0000-000000000000 | Aspire Dashboard | Not yet active | Tags | Add tags | Application Url | https://<app-name>.<unique-id>.<region>.azurecontainerapps.io | Container Apps Environment | cae-basics-d38538 | Environment type | Workload profiles | Log Analytics | law-basics-d38538 | Development stack | Generic | View Cost | JSON View | Get started | Properties | Monitoring | Discover Azure Container Apps Features | Upload artifact | Manage your app with revisions | Set up continuous deployment | Application | Revisions and replicas | Containers | Scale | Volumes | Networking | Ingress | Custom domains | CORS | Security | Settings | Monitoring | Log stream | Logs | Console | Alerts | Metrics](../../../assets/language-guides/java/tutorial/02-container-app-overview-after-deploy.png)

**[Observed]** `ca-java-d38538 | Container App` `Overview` `Stop` `Refresh` `Delete` `Send us your feedback` `Essentials` `Resource group` `rg-aca-basics-d38538` `Status` `Running` `Location` `Korea Central` `Subscription` `Visual Studio Enterprise Subscription` `Subscription ID` `00000000-0000-0000-0000-000000000000` `Aspire Dashboard` `Not yet active` `Tags` `Add tags` `Application Url` `https://<app-name>.<unique-id>.<region>.azurecontainerapps.io` `Container Apps Environment` `cae-basics-d38538` `Environment type` `Workload profiles` `Log Analytics` `law-basics-d38538` `Development stack` `Generic` `View Cost` `JSON View` `Get started` `Properties` `Monitoring` `Discover Azure Container Apps Features` `Upload artifact` `Manage your app with revisions` `Set up continuous deployment` `Application` `Revisions and replicas` `Containers` `Scale` `Volumes` `Networking` `Ingress` `Custom domains` `CORS` `Security` `Settings` `Monitoring` `Log stream` `Logs` `Console` `Alerts` `Metrics`.

**[Inferred]** The `Status` field value of `Running` appears consistent with the `state:properties.provisioningState` of `Succeeded` returned by the CLI verification in [Step 8: Verify deployment](#step-8-verify-deployment). The `Application Url` value `https://<app-name>.<unique-id>.<region>.azurecontainerapps.io` appears to surface the same `properties.configuration.ingress.fqdn` value queried in [Step 7: Create Container App](#step-7-create-container-app). The `Container Apps Environment` link value `cae-basics-d38538` appears to map to the `$ACA_ENV_NAME` value supplied to `--environment` in [Step 7: Create Container App](#step-7-create-container-app). The left-navigation entries `Containers`, `Scale`, `Ingress`, and `Logs` are consistent with the artifacts created across [Step 5: Create Container Apps environment](#step-5-create-container-apps-environment) and [Step 7: Create Container App](#step-7-create-container-app).

**[Not Proven]** Additional runtime detail and revision detail are not visible on this view.

## See Also
- [03 - Configuration and Secrets](03-configuration.md)
- [05 - Infrastructure as Code (Bicep)](05-infrastructure-as-code.md)
- [Operations Guide](../../../operations/index.md)

## Sources
- [Azure Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Private endpoints for Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints)
- [Quickstart: Build and deploy from source to Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud)
- [Manage ACR from Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
