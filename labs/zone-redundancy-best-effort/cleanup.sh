#!/usr/bin/env bash
# Cleanup the zone-redundancy-best-effort lab resources.
#
# WARNING — Resources are charged until fully deleted. Azure soft-deletes
# certain resources (Key Vault, etc.) for up to 90 days; the ACA + LAW
# resources in this lab are hard-deleted on RG removal.
#
# Usage:
#   export RG="rg-aca-zr-lab"
#   ./cleanup.sh            # interactive confirmation
#   ./cleanup.sh --yes      # non-interactive

set -euo pipefail

RG="${RG:-rg-aca-zr-lab}"
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
  - Container Apps Environment (zone-redundant)
  - Three subject apps (app-min2, app-min3, app-min6)
  - Audit Job
  - Log Analytics Workspace (raw audit data will be lost)
  - VNet + subnet
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
echo ">> The job typically completes within 10-15 minutes."
