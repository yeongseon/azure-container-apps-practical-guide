# 02 - First Deploy to Azure Container Apps

In this step, you provision the core Azure resources, build your image in Azure Container Registry, and deploy your first revision to Azure Container Apps.

## Prerequisites

- Completed [01 - Run Locally with Docker](01-local-run.md)
- Azure CLI logged in
- Bicep template at `infra/main.bicep`

## Step-by-step

1. **Set standard variables**

   ```bash
   RG="rg-aca-python-demo"
   APP_NAME="app-aca-python-demo"
   ENVIRONMENT_NAME="aca-env-python-demo"
   ACR_NAME="acrpythondemo12345"
   LOCATION="eastus"
   ```

2. **Create a resource group**

   ```bash
   az group create --name "$RG" --location "$LOCATION"
   ```

3. **Deploy infrastructure (environment, Log Analytics, ACR)**

   ```bash
   az deployment group create \
     --resource-group "$RG" \
     --template-file infra/main.bicep \
     --parameters appName="$APP_NAME" environmentName="$ENVIRONMENT_NAME" acrName="$ACR_NAME"
   ```

4. **Build and push container image with ACR Tasks**

   ```bash
   az acr build \
     --registry "$ACR_NAME" \
     --image "$APP_NAME:v1" \
     .
   ```

5. **Create the Container App**

   ```bash
   az containerapp create \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --environment "$ENVIRONMENT_NAME" \
     --image "$ACR_NAME.azurecr.io/$APP_NAME:v1" \
     --target-port 8000 \
     --ingress external \
     --registry-server "$ACR_NAME.azurecr.io"
   ```

6. **Verify deployment state and URL**

   ```bash
   az containerapp show \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --query "{state:properties.provisioningState,url:properties.configuration.ingress.fqdn}"
   ```

7. **Deploy an update (creates a new revision)**

   ```bash
   az acr build --registry "$ACR_NAME" --image "$APP_NAME:v2" .

   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --image "$ACR_NAME.azurecr.io/$APP_NAME:v2"
   ```

## What to validate

- Image exists in ACR: `v1` and `v2`
- App endpoint responds with HTTP 200 for `/health`
- A new revision appears after `az containerapp update`

## Advanced Topics

- Move to internal ingress for private APIs and pair with VNet integration.
- Add workload profiles and min/max replicas for predictable performance.
- Use managed identity-based ACR pull for stronger credential hygiene.

## See Also

- [Get started (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/get-started)
- [05 - Infrastructure as Code with Bicep](05-infrastructure-as-code.md)
- [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)
- [Networking VNet Recipe](../recipes/networking-vnet.md)
