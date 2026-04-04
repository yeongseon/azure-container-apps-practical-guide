# Lab: Revision Failover and Rollback

Practice safe recovery when a new revision fails after deployment.

## Scenario

Deploy a healthy revision (`v1`), then deploy a broken revision (`v2`) and observe how to restore service quickly using rollback and traffic control.

## Difficulty and Duration

- **Difficulty**: Intermediate
- **Estimated time**: 20-30 minutes

## Prerequisites

- Azure subscription and Azure CLI with Container Apps extension
- Existing Container Apps environment and ACR

```bash
az extension add --name containerapp --upgrade
az login
```

Set variables:

```bash
RG="rg-myapp"
APP_NAME="ca-lab-revision"
ENVIRONMENT_NAME="cae-myapp"
ACR_NAME="acrmyapp"
```

## Setup

### Step 1: Deploy working v1

```bash
az acr build --registry "$ACR_NAME" --image "$APP_NAME:v1" ./app
az containerapp create --name "$APP_NAME" --resource-group "$RG" --environment "$ENVIRONMENT_NAME" --image "$ACR_NAME.azurecr.io/$APP_NAME:v1" --target-port 8000 --ingress external --registry-server "$ACR_NAME.azurecr.io"
```

### Step 2: Deploy broken v2

Use an invalid port to induce health/provisioning failure:

```bash
az containerapp update --name "$APP_NAME" --resource-group "$RG" --image "$ACR_NAME.azurecr.io/$APP_NAME:v1" --target-port 9999
```

## Observe

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,active:properties.active,trafficWeight:properties.trafficWeight,health:properties.healthState}" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

Expected behavior: latest revision unhealthy; service may return failures depending on traffic mode.

## Diagnose

Identify revision-level failure and target port mismatch:

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.targetPort" --output tsv
```

Use KQL for timeline:

```kql
let AppName = "ca-lab-revision";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("probe", "failed", "timeout", "ingress")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Resolution (Rollback to v1)

List revisions and route all traffic to healthy revision:

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RG" --revision-weight <healthy-revision-name>=100
```

Correct config for next deploy:

```bash
az containerapp update --name "$APP_NAME" --resource-group "$RG" --target-port 8000
```

## Advanced: Multi-Revision Weighted Traffic

Split traffic for controlled rollout:

```bash
az containerapp ingress traffic set --name "$APP_NAME" --resource-group "$RG" --revision-weight <v1-revision>=90 <v2-revision>=10
```

Monitor logs and error rates before increasing v2 traffic.

## Validation

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,active:properties.active,health:properties.healthState,traffic:properties.trafficWeight}" --output table
```

## Key Takeaways

- Keep at least one known-good revision available.
- Use traffic control for rollback instead of emergency redeploy when possible.
- Diagnose from revision health and system logs before applying fixes.
