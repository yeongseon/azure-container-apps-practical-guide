# Lab: CD Reconnect RBAC Conflict

Reproduces the `AppRbacDeployment: The role assignment already exists` error that occurs when GitHub Actions continuous deployment is reconnected to a Container App after a previous disconnect that left RBAC role assignments behind.

## Structure

```text
labs/cd-reconnect-rbac-conflict/
├── infra/
│   ├── main.bicep              # Log Analytics + ACR + Container Apps Env + placeholder app
│   └── role-assignment.bicep   # ARM template that reproduces the AcrPush assignment conflict
├── trigger.sh                  # Provisions SP and runs two ARM deployments to reproduce the conflict
├── verify.sh                   # Confirms conflict, applies recovery, verifies success
└── cleanup.sh                  # Removes SP, app registration, and resource group
```

## Quick Start

```bash
export RG="rg-aca-lab-cd-rbac"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --name "lab-cd-rbac" \
    --resource-group "$RG" \
    --template-file ./infra/main.bicep \
    --parameters baseName="labcdrbac"

# Capture deployment outputs that the scripts require
export APP_NAME=$(az deployment group show -g "$RG" -n lab-cd-rbac \
    --query properties.outputs.containerAppName.value -o tsv | tr -d '\r')
export ACR_NAME=$(az deployment group show -g "$RG" -n lab-cd-rbac \
    --query properties.outputs.containerRegistryName.value -o tsv | tr -d '\r')
export SUBSCRIPTION_ID=$(az account show --query id -o tsv | tr -d '\r')
export ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id -o tsv | tr -d '\r')

./trigger.sh   # reproduces the RoleAssignmentExists failure
./verify.sh    # validates that delete + redeploy is the working recovery
./cleanup.sh   # tears down SP, app registration, and resource group
```

## Notes

- The lab simulates the CD identity by creating a regular service principal (`<APP_NAME>-github-actions-lab`) and granting it `AcrPush` on the registry. This mirrors what `az containerapp github-action add` does internally.
- "Disconnect" is simulated by skipping all Azure-side cleanup, which is the failure mode the Portal disconnect exhibits in practice.
- The conflict is reproduced via two ARM deployments of `infra/role-assignment.bicep` with different `roleAssignmentName` values but the same `(scope, principal, role)` triple. ARM enforces RBAC's uniqueness constraint and surfaces it as `RoleAssignmentExists`, which is the same error CD setup produces.
- `az role assignment create` alone does **not** reproduce this — modern Azure CLI is idempotent and returns the existing assignment instead of failing. The ARM-level deployment is what causes the user-visible failure.
- The trigger script uses `az ad app create` + `az ad sp create` instead of `az ad sp create-for-rbac` so it works in tenants that block credential creation via policy.
- No GitHub repository or real `az containerapp github-action add` call is required.

## Related Documentation

- [CD Reconnect RBAC Conflict Lab Guide](../../docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md)
- [Continuous Deployment RBAC Role Assignment Conflict Playbook](../../docs/troubleshooting/playbooks/identity-and-configuration/cd-rbac-role-assignment-conflict.md)
