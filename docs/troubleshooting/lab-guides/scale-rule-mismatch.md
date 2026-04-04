# Scale Rule Mismatch Lab

Diagnose non-scaling behavior caused by unrealistic HTTP concurrency thresholds, then tune scale settings.

## Scenario

- **Difficulty**: Intermediate
- **Estimated duration**: 25-35 minutes
- **Failure mode**: sustained load does not increase replica count because scale rule threshold is too high

## Prerequisites

- Azure CLI with Container Apps extension
- `hey` load generator (optional; script falls back to `curl` loop)

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-scale"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-scale" --resource-group "$RG" --template-file ./labs/scale-rule-mismatch/infra/main.bicep --parameters baseName="labscale"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-scale" --query \"properties.outputs.containerAppName.value\" --output tsv)"
export ACR_NAME="$(az deployment group show --resource-group "$RG" --name "lab-scale" --query \"properties.outputs.containerRegistryName.value\" --output tsv)"

cd labs/scale-rule-mismatch
./trigger.sh
./verify.sh
./cleanup.sh
```

## Expected Diagnostic Output Pattern

```text
Reason_s             Type_s
-------------------  --------
KEDAScalersStarted   Normal
```

Replica baseline used during verification:

```text
ca-myapp--0000001-646779b4c5-bhc2v  Running
```

## Key Takeaways

- Replica behavior depends heavily on matching threshold values to real traffic patterns.
- `maxReplicas` can silently cap expected scaling even with valid rules.
- Validate with both load generation and replica/system-log checks.

## See Also

- [HTTP Scaling Not Triggering Playbook](../playbooks/scaling-and-runtime/http-scaling-not-triggering.md)
- [Event Scaler Mismatch Playbook](../playbooks/scaling-and-runtime/event-scaler-mismatch.md)
