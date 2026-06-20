#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

echo "[cleanup] deleting resource group ${RG}"
az group delete --name "$RG" --yes --no-wait
echo "[cleanup] delete submitted (async). Track with: az group show -n $RG"
