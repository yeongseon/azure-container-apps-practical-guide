#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"

SP_NAME="${APP_NAME}-github-actions-lab"

echo "==> Removing service principal $SP_NAME and any role assignments"
SP_APP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv | tr -d '\r')
if [ -n "$SP_APP_ID" ] && [ "$SP_APP_ID" != "null" ]; then
    SP_OBJECT_ID=$(az ad sp show --id "$SP_APP_ID" --query id --output tsv 2>/dev/null | tr -d '\r' || true)
    if [ -n "$SP_OBJECT_ID" ]; then
        az role assignment list --assignee "$SP_OBJECT_ID" --all --query "[].id" --output tsv \
            | tr -d '\r' \
            | xargs -r -n 1 az role assignment delete --ids
    fi
    az ad sp delete --id "$SP_APP_ID" 2>/dev/null || true
    APP_OBJECT_ID=$(az ad app list --display-name "$SP_NAME" --query "[0].id" --output tsv | tr -d '\r')
    if [ -n "$APP_OBJECT_ID" ] && [ "$APP_OBJECT_ID" != "null" ]; then
        az ad app delete --id "$APP_OBJECT_ID" 2>/dev/null || true
    fi
    echo "    Service principal and app registration deleted."
else
    echo "    No service principal found - skipping."
fi

echo "==> Deleting resource group $RG (async)"
az group delete --name "$RG" --yes --no-wait
echo "Cleanup initiated."
