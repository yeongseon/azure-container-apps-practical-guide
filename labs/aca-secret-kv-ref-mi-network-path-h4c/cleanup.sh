#!/usr/bin/env bash
set -euo pipefail
: "${RG:?RG (resource group) must be set}"
echo "[cleanup] deleting resource group ${RG} (async)"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] requested. Verify with: az group show --name $RG --output none"
echo "[cleanup] lab variant: aca-secret-kv-ref-mi-network-path-h4c"
echo "[cleanup] This variant is cheaper than H4a/H4b because it deploys no Azure Firewall and no UDR, but delete the group promptly anyway."
