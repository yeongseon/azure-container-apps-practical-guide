# Revision Provisioning Failure Lab

Reproduce provisioning failure when a container environment variable references a non-existent secret.

## Scenario

- **Difficulty**: Intermediate
- **Estimated duration**: 20-30 minutes
- **Failure mode**: revision fails because `secretRef` points to `missing-secret`

## Prerequisites

- Azure CLI with Container Apps extension
- Permissions to deploy Container Apps resources

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-revprov"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-revprov" --resource-group "$RG" --template-file ./labs/revision-provisioning-failure/infra/main.bicep --parameters baseName="labrevprov"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-revprov" --query \"properties.outputs.containerAppName.value\" --output tsv)"

cd labs/revision-provisioning-failure
./trigger.sh
./verify.sh
./cleanup.sh
```

## Expected Diagnostic Output Pattern

```text
ContainerAppUpdate  → Updating containerApp: ca-myapp
RevisionCreation    → Creating new revision
ProbeFailed         → Probe of StartUp failed with status code: 1
RevisionReady       → Revision ready
ContainerAppReady   → Running state reached
```

## Key Takeaways

- Missing secret references can block revision provisioning even when image/runtime are valid.
- Revision-level health and system logs reveal configuration failures quickly.
- Add missing secret, then roll a new revision to validate recovery.

## See Also

- [Revision Provisioning Failure Playbook](../playbooks/startup-and-provisioning/revision-provisioning-failure.md)
- [Container Start Failure Playbook](../playbooks/startup-and-provisioning/container-start-failure.md)
