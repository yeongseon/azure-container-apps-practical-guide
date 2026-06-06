#!/usr/bin/env bash
# cleanup.sh — delete the lab resource group asynchronously.
set -euo pipefail
: "${RG:?RG (resource group) must be set}"
echo "[cleanup] deleting resource group ${RG} (async)"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] requested. Verify with: az group show --name $RG --output none"
