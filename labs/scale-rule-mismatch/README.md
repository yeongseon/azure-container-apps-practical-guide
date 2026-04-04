# Lab: Scale Rule Mismatch

Learn to diagnose and correct autoscaling behavior when replicas do not change as expected under load.

## Scenario

Your app receives traffic, but replica count stays fixed or scales unpredictably because scale rule settings do not match workload behavior.

## Difficulty and Duration

- **Difficulty**: Intermediate
- **Estimated time**: 20-30 minutes

## Prerequisites

- Azure subscription and Azure CLI with Container Apps extension
- Existing Container Apps environment and ACR
- A simple load tool (for example, `hey` or `ab`)

```bash
az extension add --name containerapp --upgrade
az login
```

Set variables:

```bash
RG="rg-myapp"
APP_NAME="ca-lab-scale"
ENVIRONMENT_NAME="cae-myapp"
ACR_NAME="acrmyapp"
```

## Setup

Deploy app with intentionally mismatched HTTP scaling threshold.

```bash
az acr build --registry "$ACR_NAME" --image "$APP_NAME:v1" ./app
az containerapp create --name "$APP_NAME" --resource-group "$RG" --environment "$ENVIRONMENT_NAME" --image "$ACR_NAME.azurecr.io/$APP_NAME:v1" --target-port 8000 --ingress external --min-replicas 0 --max-replicas 2 --scale-rule-name "http-rule" --scale-rule-type "http" --scale-rule-metadata "concurrentRequests=500"
```

## Observe

Generate load that should scale in a normal configuration:

```bash
APP_FQDN="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.configuration.ingress.fqdn --output tsv)"
hey -z 60s -c 50 "https://$APP_FQDN/health"
```

Check replicas and scale logs:

```bash
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

## Diagnose

Inspect scale template and compare threshold to observed concurrency.

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale" --output json
```

Use KQL to inspect scaling events:

```kql
let AppName = "ca-lab-scale";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("keda", "scale", "replica")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Resolution

Set realistic HTTP threshold and wider max replicas:

```bash
az containerapp update --name "$APP_NAME" --resource-group "$RG" --min-replicas 0 --max-replicas 10 --scale-rule-name "http-rule" --scale-rule-type "http" --scale-rule-metadata "concurrentRequests=20"
```

Re-run load and verify replicas increase, then return toward minimum after idle period.

## Advanced

- Add queue-based scale rule for event workloads (Service Bus, Storage Queue).
- Compare HTTP scale behavior with custom KEDA rules.
- Tune polling interval and cooldown settings for bursty traffic.

## Validation

```bash
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale" --output json
```

## Key Takeaways

- Scale outcomes depend on rule type, metric source, and threshold realism.
- Min/max settings can hide scale-rule problems.
- Use controlled load and system logs to validate scaling behavior before production rollout.
