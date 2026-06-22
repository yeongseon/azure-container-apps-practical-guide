#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?Set AZ_SUBSCRIPTION before running}"
: "${RG:?Set RG before running}"

echo "Deleting resource group ${RG} in subscription ${AZ_SUBSCRIPTION} (async, --no-wait)..."
az group delete \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --yes \
    --no-wait
echo "Delete initiated. Run 'az group show --subscription \"$AZ_SUBSCRIPTION\" --name \"$RG\"' to verify Deleting state."
