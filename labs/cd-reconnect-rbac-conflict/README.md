# Lab: CD Reconnect RBAC Conflict

Reproduces the `AppRbacDeployment: The role assignment already exists` error that occurs when GitHub Actions continuous deployment is reconnected to a Container App after a previous disconnect that left RBAC role assignments behind.

## Structure

```text
labs/cd-reconnect-rbac-conflict/
├── infra/main.bicep
├── trigger.sh
├── verify.sh
└── cleanup.sh
```

## Quick Start

```bash
export RG="rg-aca-lab-cd-rbac"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"
az deployment group create \
    --resource-group "$RG" \
    --template-file ./infra/main.bicep \
    --parameters baseName="labcdrbac"

export APP_NAME=$(az deployment group show -g "$RG" -n lab-cd-rbac --query properties.outputs.containerAppName.value -o tsv 2>/dev/null \
    || az containerapp list -g "$RG" --query "[0].name" -o tsv)
export ACR_NAME=$(az acr list -g "$RG" --query "[0].name" -o tsv)

./trigger.sh
./verify.sh
./cleanup.sh
```

## Notes

- The lab simulates the CD identity by creating a regular service principal (`<APP_NAME>-github-actions-lab`) and granting it `AcrPush` on the registry. This mirrors what `az containerapp github-action add` does internally.
- "Disconnect" is simulated by skipping all Azure-side cleanup, which is the failure mode the Portal disconnect exhibits in practice.
- The conflict is the RBAC uniqueness constraint on `(scope, principal, role)`, the same constraint enforced when the real CD deployment template runs.
- No GitHub repository or real `az containerapp github-action add` call is required - the lab proves the RBAC mechanism that produces the deployment error.

## Related Documentation

- [CD Reconnect RBAC Conflict Lab Guide](../../docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md)
- [Continuous Deployment RBAC Role Assignment Conflict Playbook](../../docs/troubleshooting/playbooks/identity-and-configuration/cd-rbac-role-assignment-conflict.md)
