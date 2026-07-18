#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-rg-aca-basics-d38538}"

echo "Deleting resource group ${RG} (async, --no-wait)..."
az group delete --name "$RG" --yes --no-wait
echo "Delete initiated. Run 'az group show --name \"$RG\" --query properties.provisioningState --output tsv' to verify Deleting state."
echo "D4 workload-profile nodes bill continuously even when idle — do not skip this cleanup."
