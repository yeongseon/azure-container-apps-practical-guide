#!/usr/bin/env bash
set -euo pipefail

AZ_SUBSCRIPTION="${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (the lab subscription GUID)}"
RG="${RG:?RG must be set (the lab resource group)}"

echo "Deleting resource group ${RG} (async, --no-wait)..."
az group delete \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --yes \
    --no-wait
echo "Delete initiated. Run 'az group show --subscription \"\$AZ_SUBSCRIPTION\" --name \"$RG\"' to verify Deleting state."
