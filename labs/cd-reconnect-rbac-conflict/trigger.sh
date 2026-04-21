#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
ACR_ID="${ACR_ID:-$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id --output tsv)}"
SP_NAME="${APP_NAME}-github-actions-lab"

echo "==> 1) Create service principal that simulates the CD identity ($SP_NAME)"
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv)
if [ -z "$SP_APP_ID" ] || [ "$SP_APP_ID" = "null" ]; then
    SP_APP_ID=$(az ad sp create-for-rbac --name "$SP_NAME" --skip-assignment --query appId --output tsv)
fi
SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id --output tsv)
echo "    appId=$SP_APP_ID objectId=$SP_OBJECT_ID"

echo "==> 2) Initial CD setup: assign AcrPush on registry scope"
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPush \
    --scope "$ACR_ID" \
    --output none || true

echo "    Waiting 15s for RBAC propagation..."
sleep 15

az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --output table

echo "==> 3) Simulated 'Disconnect' (only GitHub-side artifacts removed in real life)"
echo "    No Azure cleanup performed - service principal and role assignment remain."

echo "==> 4) Attempt 'Reconnect' - recreate the same role assignment"
set +e
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPush \
    --scope "$ACR_ID" 2>&1 | tee /tmp/cd-rbac-conflict.log
RESULT=$?
set -e

if grep -qE "RoleAssignmentExists|already exists" /tmp/cd-rbac-conflict.log; then
    echo "PASS: RoleAssignmentExists conflict reproduced (this is the AppRbacDeployment failure)."
    exit 0
elif [ "$RESULT" -eq 0 ]; then
    echo "FAIL: Second create call succeeded - conflict not reproduced."
    exit 1
else
    echo "FAIL: Unexpected error - check /tmp/cd-rbac-conflict.log"
    exit 1
fi
