# Revision Failover and Rollback Lab

Practice safe rollback by intentionally creating an unhealthy revision and routing traffic back to a healthy one.

## Scenario

- **Difficulty**: Intermediate
- **Estimated duration**: 20-30 minutes
- **Failure mode**: latest revision unhealthy after ingress target port is changed to the wrong value

## Prerequisites

- Azure CLI with Container Apps extension
- Permissions to deploy resources and update Container Apps

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-revision"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-revision" --resource-group "$RG" --template-file ./labs/revision-failover/infra/main.bicep --parameters baseName="labrevision"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-revision" --query \"properties.outputs.containerAppName.value\" --output tsv)"
export ACR_NAME="$(az deployment group show --resource-group "$RG" --name "lab-revision" --query \"properties.outputs.containerRegistryName.value\" --output tsv)"

cd labs/revision-failover
./trigger.sh
./verify.sh
./cleanup.sh
```

## Key Takeaways

- Keep multiple revisions available when testing risky updates.
- Traffic shifting and rollback are faster than full redeploy during incidents.
- Always validate revision health after config changes.

## See Also

- [Bad Revision Rollout and Rollback Playbook](../playbooks/platform-features/bad-revision-rollout-and-rollback.md)
- [Probe Failure and Slow Start Playbook](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md)
