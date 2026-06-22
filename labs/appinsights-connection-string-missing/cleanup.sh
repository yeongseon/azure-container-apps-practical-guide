#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (Azure subscription ID)}"
: "${RG:?RG must be set}"

echo "==> Deleting resource group $RG (async, --no-wait)..."
az group delete --subscription "$AZ_SUBSCRIPTION" --name "$RG" --yes --no-wait
echo "==> Cleanup initiated. Verify with: az group show --subscription $AZ_SUBSCRIPTION --name $RG"
