#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG must be set}"

echo "==> Deleting resource group $RG (async, --no-wait)..."
az group delete --name "$RG" --yes --no-wait
echo "==> Cleanup initiated. Verify with: az group show --name $RG"
