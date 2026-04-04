# Probe and Port Mismatch Lab

Reproduce probe failures when the container process listens on one port while ingress/probes target a different port.

## Scenario

- **Difficulty**: Beginner
- **Estimated duration**: 20-25 minutes
- **Failure mode**: app listens on 3000 but Container App ingress targets 8000

## Prerequisites

- Azure CLI with Container Apps extension
- Permissions to deploy Container Apps and ACR resources

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-port"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-port" --resource-group "$RG" --template-file ./labs/probe-and-port-mismatch/infra/main.bicep --parameters baseName="labport"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-port" --query \"properties.outputs.containerAppName.value\" --output tsv)"
export ACR_NAME="$(az deployment group show --resource-group "$RG" --name "lab-port" --query \"properties.outputs.containerRegistryName.value\" --output tsv)"

cd labs/probe-and-port-mismatch
./trigger.sh
./verify.sh
./cleanup.sh
```

## Key Takeaways

- Target port and process bind port must match.
- Probe failures can look like app crashes if port mapping is wrong.
- Recovery is usually a simple target-port correction and new revision rollout.

## See Also

- [Probe Failure and Slow Start Playbook](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md)
- [Ingress Not Reachable Playbook](../playbooks/ingress-and-networking/ingress-not-reachable.md)
