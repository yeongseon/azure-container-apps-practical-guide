#!/usr/bin/env bash
# Cleanup the replica-node-spread lab resources.
#
# WARNING: Resources continue to incur charges until the resource group
# is fully deleted. Azure may keep delete-pending resources for up to
# 24 hours; check progress with `az group show --name $RG`.
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   ./cleanup.sh            # interactive confirmation
#   ./cleanup.sh --yes      # non-interactive

set -euo pipefail

RG="${RG:-rg-aca-rns-lab}"
ASSUME_YES="${1:-}"

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo "Resource group $RG does not exist. Nothing to do."
  exit 0
fi

cat <<EOF
================================================================
This will DELETE the following resource group and ALL contents:

  Resource group : $RG

Includes:
  - Container Apps Environment (workload profiles: Consumption + Dedicated D8)
  - ca-diag-consumption + ca-diag-dedicated
  - Azure Container Registry (Basic SKU)
  - Log Analytics Workspace
  - User-assigned managed identity + role assignments

Continuing charges stop only when the resource group is fully
deleted. Azure may keep certain delete-pending resources for up to
24 hours; check with: az group show --name $RG

================================================================
EOF

if [[ "$ASSUME_YES" != "--yes" && "$ASSUME_YES" != "-y" ]]; then
  read -r -p "Type 'delete' to proceed: " CONFIRM
  if [[ "$CONFIRM" != "delete" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo ">> Deleting resource group $RG"
az group delete --name "$RG" --yes --no-wait

echo ">> Delete submitted. Use 'az group show --name $RG' to monitor."
echo ">> Typically completes within 10-15 minutes."
