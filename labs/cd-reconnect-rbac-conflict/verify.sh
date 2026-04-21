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

SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv | tr -d '\r')
[ -n "$SP_APP_ID" ] && [ "$SP_APP_ID" != "null" ] || { echo "FAIL: service principal $SP_NAME not found - run trigger.sh first"; exit 1; }
SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id --output tsv | tr -d '\r')

echo "==> Step 1: confirm pre-existing assignment exists (must reproduce conflict baseline)"
INITIAL_COUNT=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "length(@)" --output tsv | tr -d '\r')
[ "$INITIAL_COUNT" -ge 1 ] || { echo "FAIL: no pre-existing AcrPush assignment for $SP_NAME on $ACR_NAME - cannot reproduce"; exit 1; }
echo "    Found $INITIAL_COUNT existing assignment(s)."

echo "==> Step 2: confirm second ARM deployment still conflicts"
NEW_NAME=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
set +e
az deployment group create \
    --resource-group "$RG" \
    --name "lab-ra-verify-conflict" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME" \
    --output json 2>&1 | tee /tmp/cd-rbac-verify.log >/dev/null
set -e
if grep -qE "RoleAssignmentExists|already exists" /tmp/cd-rbac-verify.log; then
    echo "    Confirmed: conflict is reproducible."
else
    echo "FAIL: expected RoleAssignmentExists not observed in second deployment"
    exit 1
fi

echo "==> Step 3: apply recovery - delete conflicting assignment"
ASSIGNMENT_ID=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "[0].name" --output tsv | tr -d '\r')
echo "    Deleting role assignment $ASSIGNMENT_ID"
az role assignment delete \
    --ids "${ACR_ID}/providers/Microsoft.Authorization/roleAssignments/$ASSIGNMENT_ID"
sleep 15

echo "==> Step 4: retry the second deployment - should now succeed"
az deployment group create \
    --resource-group "$RG" \
    --name "lab-ra-verify-recovery" \
    --template-file "$TEMPLATE" \
    --parameters principalObjectId="$SP_OBJECT_ID" registryName="$ACR_NAME" roleAssignmentName="$NEW_NAME" \
    --query "properties.{state:provisioningState, name:outputs.roleAssignmentName.value}" \
    --output table

echo "==> Step 5: verify final state has exactly one active assignment"
sleep 15
FINAL_COUNT=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "length(@)" --output tsv | tr -d '\r')
if [ "$FINAL_COUNT" = "1" ]; then
    echo "PASS: recovery successful - 1 active AcrPush assignment for $SP_NAME on $ACR_NAME"
    exit 0
else
    echo "FAIL: unexpected assignment count $FINAL_COUNT (expected 1)"
    exit 1
fi
