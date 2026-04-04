# ACR Image Pull Failure Lab

Reproduce and resolve container startup failure caused by referencing a non-existent image tag in ACR.

## Scenario

- **Difficulty**: Beginner
- **Estimated duration**: 20-30 minutes
- **Failure mode**: `ImagePullBackOff` / manifest not found during revision startup

## Prerequisites

- Azure CLI with Container Apps extension
- Permissions to create resource groups and deploy Azure resources

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-acr"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-acr" --resource-group "$RG" --template-file ./labs/acr-pull-failure/infra/main.bicep --parameters baseName="labacr"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-acr" --query \"properties.outputs.containerAppName.value\" --output tsv)"
export ACR_NAME="$(az deployment group show --resource-group "$RG" --name "lab-acr" --query \"properties.outputs.containerRegistryName.value\" --output tsv)"

cd labs/acr-pull-failure
./trigger.sh
./verify.sh
./cleanup.sh
```

## Key Takeaways

- Image tag validation is the fastest first check for pull failures.
- System logs and revision health quickly confirm startup cause.
- A known-good image push + container app update is the shortest recovery path.

## See Also

- [Image Pull Failure Playbook](../playbooks/startup-and-provisioning/image-pull-failure.md)
- [Container Start Failure Playbook](../playbooks/startup-and-provisioning/container-start-failure.md)
