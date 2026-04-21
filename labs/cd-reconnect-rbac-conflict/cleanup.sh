#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"

SP_NAME="${APP_NAME}-github-actions-lab"

echo "==> Removing service principal $SP_NAME and any role assignments"
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv)
if [ -n "$SP_APP_ID" ] && [ "$SP_APP_ID" != "null" ]; then
    az role assignment list --assignee "$SP_APP_ID" --all --query "[].id" --output tsv \
        | xargs -r -n 1 az role assignment delete --ids
    az ad sp delete --id "$SP_APP_ID"
    echo "    Service principal deleted."
else
    echo "    No service principal found - skipping."
fi

echo "==> Deleting resource group $RG (async)"
az group delete --name "$RG" --yes --no-wait
echo "Cleanup initiated."
