# Lab: ACR Image Pull Failure

Reproduce and fix the most common ACR pull issues for Azure Container Apps in a controlled environment.

## Scenario

Your Container App deployment completes, but the revision fails and replicas never start because image pull cannot succeed (`ImagePullBackOff`).

## Difficulty and Duration

- **Difficulty**: Beginner
- **Estimated time**: 20-30 minutes

## Prerequisites

- Azure subscription with permissions to deploy Container Apps and assign RBAC
- Azure CLI with Container Apps extension
- Existing Container Apps environment and ACR

```bash
az extension add --name containerapp --upgrade
az login
```

Set variables:

```bash
RG="rg-myapp"
APP_NAME="ca-lab-acr-pull"
ENVIRONMENT_NAME="cae-myapp"
ACR_NAME="acrmyapp"
LOCATION="koreacentral"
```

## Setup

Deploy the app with a non-existent image tag to force an image pull failure.

```bash
az containerapp create --name "$APP_NAME" --resource-group "$RG" --environment "$ENVIRONMENT_NAME" --image "$ACR_NAME.azurecr.io/$APP_NAME:does-not-exist" --target-port 8000 --ingress external --registry-server "$ACR_NAME.azurecr.io"
```

## Observe

Check revision and replica status:

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

Expected result: image pull errors in system logs and no stable running replica.

## Diagnose

Run KQL in Log Analytics to isolate pull failures:

```kql
let AppName = "ca-lab-acr-pull";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("ImagePull", "manifest", "unauthorized", "denied")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

Validate image/tag exists:

```bash
az acr repository list --name "$ACR_NAME" --output table
az acr repository show-tags --name "$ACR_NAME" --repository "$APP_NAME" --output table
```

## Causes Covered and Fixes

### Cause 1: Wrong image tag

Push a valid image and deploy with real tag:

```bash
az acr build --registry "$ACR_NAME" --image "$APP_NAME:v1" ./app
az containerapp update --name "$APP_NAME" --resource-group "$RG" --image "$ACR_NAME.azurecr.io/$APP_NAME:v1"
```

### Cause 2: ACR admin disabled + no managed identity RBAC

Assign identity and grant `AcrPull`:

```bash
az containerapp identity assign --name "$APP_NAME" --resource-group "$RG" --system-assigned
APP_PRINCIPAL_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query identity.principalId --output tsv)"
ACR_ID="$(az acr show --name "$ACR_NAME" --query id --output tsv)"
az role assignment create --assignee "$APP_PRINCIPAL_ID" --role "AcrPull" --scope "$ACR_ID"
```

### Cause 3: Private ACR without correct network path

- Confirm private endpoint and private DNS zone links are present.
- Confirm NSG permits required outbound paths from Container Apps environment.

```bash
az network private-endpoint list --resource-group "$RG" --output table
az network private-dns zone list --resource-group "$RG" --output table
```

## Resolution Validation

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,health:properties.healthState,running:properties.runningState}" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

Healthy state indicates pull/auth/network path is fixed.

## Cleanup

```bash
az containerapp delete --name "$APP_NAME" --resource-group "$RG" --yes
```

## Key Takeaways

- Start with system logs for pull failures.
- Verify image tag existence before changing identity/network settings.
- Managed identity + `AcrPull` is the preferred authentication path.
- Private ACR requires DNS and network correctness, not only RBAC.
