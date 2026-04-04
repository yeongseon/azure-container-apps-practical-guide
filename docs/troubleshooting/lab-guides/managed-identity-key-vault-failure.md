# Managed Identity Key Vault Failure Lab

Reproduce Key Vault access denial by running a managed-identity-enabled app without the required RBAC role assignment.

## Scenario

- **Difficulty**: Intermediate
- **Estimated duration**: 25-35 minutes
- **Failure mode**: app returns 500 when reading secret because identity lacks `Key Vault Secrets User`

## Prerequisites

- Azure CLI with Container Apps extension
- Permissions for role assignments (`Microsoft.Authorization/roleAssignments/write`)

```bash
az extension add --name containerapp --upgrade
az login
```

## Quick Start

```bash
export RG="rg-aca-lab-kv"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create --name "lab-kv" --resource-group "$RG" --template-file ./labs/managed-identity-key-vault-failure/infra/main.bicep --parameters baseName="labkv"

export APP_NAME="$(az deployment group show --resource-group "$RG" --name "lab-kv" --query \"properties.outputs.containerAppName.value\" --output tsv)"
export ACR_NAME="$(az deployment group show --resource-group "$RG" --name "lab-kv" --query \"properties.outputs.containerRegistryName.value\" --output tsv)"
export KV_NAME="$(az deployment group show --resource-group "$RG" --name "lab-kv" --query \"properties.outputs.keyVaultName.value\" --output tsv)"

cd labs/managed-identity-key-vault-failure
./trigger.sh
./verify.sh
./cleanup.sh
```

## Expected Diagnostic Output Pattern

```text
Managed identity failures commonly present as 401/403 in app logs while revision stays Running:

Name               Active    TrafficWeight    Replicas    HealthState    RunningState
-----------------  --------  ---------------  ----------  -------------  ------------
ca-myapp--0000001  True      100              1           Healthy        Running
```

## Key Takeaways

- System-assigned identity alone is not enough; RBAC role assignment is mandatory.
- Secret access failures often surface as 500 errors in app routes.
- Restart/new revision after RBAC assignment helps validate full recovery path.

## See Also

- [Managed Identity Auth Failure Playbook](../playbooks/identity-and-configuration/managed-identity-auth-failure.md)
- [Secret and Key Vault Reference Failure Playbook](../playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md)
