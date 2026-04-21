#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv | tr -d '\r')}"
ACR_ID="${ACR_ID:-$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id --output tsv | tr -d '\r')}"
SP_NAME="${APP_NAME}-github-actions-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/infra/role-assignment.bicep"

echo "==> 1) Create service principal that simulates the CD identity ($SP_NAME)"
# We only need the principal object for RBAC; no client secret is required for this lab.
# Using `az ad app create` + `az ad sp create` avoids tenant credential lifetime policies
# that block `az ad sp create-for-rbac`.
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv | tr -d '\r')
if [ -z "$SP_APP_ID" ] || [ "$SP_APP_ID" = "null" ]; then
    APP_ID=$(az ad app list --display-name "$SP_NAME" --query "[0].appId" --output tsv | tr -d '\r')
    if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
        APP_ID=$(az ad app create --display-name "$SP_NAME" --query appId --output tsv | tr -d '\r')
    fi
    az ad sp create --id "$APP_ID" --output none
    SP_APP_ID="$APP_ID"
fi
SP_OBJECT_ID=""
for i in 1 2 3 4 5 6; do
    SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id --output tsv 2>/dev/null | tr -d '\r' || true)
    [ -n "$SP_OBJECT_ID" ] && break
    echo "    Waiting for SP propagation in Microsoft Entra ID (attempt $i/6)..."
    sleep 10
done
[ -n "$SP_OBJECT_ID" ] || { echo "FAIL: SP object id not resolvable for $SP_APP_ID"; exit 1; }
echo "    appId=$SP_APP_ID objectId=$SP_OBJECT_ID"

echo "==> 2) Initial CD setup: ARM deployment that grants AcrPush on registry"
# This deployment mirrors what `az containerapp github-action add` does internally:
# it creates a Microsoft.Authorization/roleAssignments resource via ARM. The default
# resource name is a GUID derived from (scope, principal, role).
az deployment group create \
    --resource-group "$RG" \
    --name "lab-ra-initial" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" \
    --query "properties.{state:provisioningState, name:outputs.roleAssignmentName.value}" \
    --output table

echo "    Waiting 15s for RBAC propagation..."
sleep 15
az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --output table

echo "==> 3) Simulated 'Disconnect' (only GitHub-side artifacts removed in real life)"
echo "    No Azure cleanup performed - service principal and role assignment remain."

echo "==> 4) Attempt 'Reconnect' - second ARM deployment with a fresh role assignment GUID"
# Real CD reconnect generates a new role assignment GUID on each invocation. Same scope
# + same principal + same role with a different assignment name triggers the RBAC unique
# key violation, surfaced as RoleAssignmentExists / AppRbacDeployment in the Portal.
NEW_NAME=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
set +e
az deployment group create \
    --resource-group "$RG" \
    --name "lab-ra-reconnect" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME" \
    --output json 2>&1 | tee /tmp/cd-rbac-conflict.log
RESULT=${PIPESTATUS[0]}
set -e

if grep -qE "RoleAssignmentExists|already exists" /tmp/cd-rbac-conflict.log; then
    EXISTING_ID=$(grep -oE 'existing role assignment is [a-f0-9]{32}' /tmp/cd-rbac-conflict.log | awk '{print $NF}' | head -1)
    echo ""
    echo "PASS: RoleAssignmentExists conflict reproduced."
    echo "    Existing assignment ID (no hyphens): $EXISTING_ID"
    echo "    GUID format: $(echo "$EXISTING_ID" | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')"
    echo "    This is the same error returned by 'az containerapp github-action add' on reconnect."
    exit 0
elif [ "$RESULT" -eq 0 ]; then
    echo "FAIL: Second deployment succeeded - conflict not reproduced."
    exit 1
else
    echo "FAIL: Unexpected error - check /tmp/cd-rbac-conflict.log"
    exit 1
fi
