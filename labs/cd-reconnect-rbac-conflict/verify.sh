#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
ACR_ID="${ACR_ID:-$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id --output tsv)}"
SP_NAME="${APP_NAME}-github-actions-lab"

SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv)
if [ -z "$SP_APP_ID" ] || [ "$SP_APP_ID" = "null" ]; then
    echo "FAIL: service principal $SP_NAME not found - run trigger.sh first"
    exit 1
fi
SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id --output tsv)

echo "==> Step 1: confirm pre-existing assignment exists (must reproduce conflict baseline)"
INITIAL_COUNT=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "length(@)" --output tsv)
if [ "$INITIAL_COUNT" -lt 1 ]; then
    echo "FAIL: no pre-existing AcrPush assignment for $SP_NAME on $ACR_NAME - cannot reproduce"
    exit 1
fi
echo "    Found $INITIAL_COUNT existing assignment(s)."

echo "==> Step 2: confirm second create call still conflicts"
set +e
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPush \
    --scope "$ACR_ID" 2>&1 | tee /tmp/cd-rbac-verify.log >/dev/null
set -e
if grep -qE "RoleAssignmentExists|already exists" /tmp/cd-rbac-verify.log; then
    echo "    Confirmed: conflict is reproducible."
else
    echo "FAIL: expected conflict not observed"
    exit 1
fi

echo "==> Step 3: apply recovery - delete conflicting assignment then recreate"
ASSIGNMENT_ID=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "[0].name" --output tsv)
az role assignment delete \
    --ids "/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/roleAssignments/$ASSIGNMENT_ID"

sleep 10

az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role AcrPush \
    --scope "$ACR_ID" \
    --output none

echo "==> Step 4: verify final state has exactly one active assignment"
sleep 10
FINAL_COUNT=$(az role assignment list --assignee "$SP_APP_ID" --scope "$ACR_ID" --query "length(@)" --output tsv)
if [ "$FINAL_COUNT" = "1" ]; then
    echo "PASS: recovery successful - 1 active AcrPush assignment for $SP_NAME on $ACR_NAME"
    exit 0
else
    echo "FAIL: unexpected assignment count $FINAL_COUNT (expected 1)"
    exit 1
fi
