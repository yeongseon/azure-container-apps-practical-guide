#!/usr/bin/env bash
set -euo pipefail
: "${RG:?RG (resource group) must be set}"
echo "[cleanup] deleting resource group ${RG} (async)"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] requested. Verify with: az group show --name $RG --output none"
echo "[cleanup] Firewall Basic + 2 public IPs dominate cost — do not skip this step."
