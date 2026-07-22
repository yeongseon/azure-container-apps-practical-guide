#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

echo "[cleanup] deleting resource group ${RG} (async)"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] requested. Verify with: az group show --name $RG --output none"
echo "[cleanup] lab variant: aca-secret-kv-ref-mi-network-path-h4g"
echo "[cleanup] This variant deploys Azure Firewall Premium. Delete the resource group immediately after capturing evidence."
