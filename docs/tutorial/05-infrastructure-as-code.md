# 05 - Infrastructure as Code with Bicep

Use Bicep to define your Azure Container Apps platform consistently across environments. This step focuses on repeatable provisioning and safe updates.

## Prerequisites

- Completed [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- Bicep files under `infra/`

## Step-by-step

1. **Set standard variables**

   ```bash
   RG="rg-aca-python-demo"
   APP_NAME="app-aca-python-demo"
   ENVIRONMENT_NAME="aca-env-python-demo"
   ACR_NAME="acrpythondemo12345"
   LOCATION="eastus"
   ```

2. **Validate the Bicep template**

   ```bash
   az deployment group validate \
     --resource-group "$RG" \
     --template-file infra/main.bicep \
     --parameters appName="$APP_NAME" environmentName="$ENVIRONMENT_NAME" acrName="$ACR_NAME"
   ```

3. **Preview changes with what-if**

   ```bash
   az deployment group what-if \
     --resource-group "$RG" \
     --template-file infra/main.bicep \
     --parameters appName="$APP_NAME" environmentName="$ENVIRONMENT_NAME" acrName="$ACR_NAME"
   ```

4. **Deploy infrastructure**

   ```bash
   az deployment group create \
     --resource-group "$RG" \
     --template-file infra/main.bicep \
     --parameters appName="$APP_NAME" environmentName="$ENVIRONMENT_NAME" acrName="$ACR_NAME"
   ```

5. **Verify outputs and key resources**

   ```bash
   az deployment group show \
     --resource-group "$RG" \
     --name main \
     --query properties.outputs
   ```

## Example Bicep snippet (environment + logs)

```bicep
param location string = resourceGroup().location
param environmentName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
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

- Split templates into modules (network, observability, apps, identity).
- Use parameter files per environment (dev, test, prod).
- Provision Dapr components declaratively with managed identities.

## See Also
- [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
- [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- [Managed Identity Recipe](../recipes/managed-identity.md)

## References
- [Azure Resource Manager API spec (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/azure-resource-manager-api-spec)
- [Bicep resource definition: Microsoft.App/containerApps (Microsoft Learn)](https://learn.microsoft.com/azure/templates/microsoft.app/containerapps)
