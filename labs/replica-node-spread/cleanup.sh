#!/usr/bin/env bash
# Cleanup the replica-node-spread lab resources.
#
# WARNING — Resources are charged until fully deleted. Azure soft-deletes
# certain resources (Key Vault, etc.) for up to 90 days; the ACA + LAW +
# ACR resources in this lab are hard-deleted on RG removal.
#
# Required env:
#   RG               Resource group to DELETE.
#   SUBSCRIPTION_ID  Exact Azure subscription this lab targets (defensive).
#                    This is the highest-stakes guard in the lab: a
#                    mismatch here would delete the wrong RG in the wrong
#                    subscription. Failure is fatal and intentional.
#
# Usage:
#   source /tmp/rns-lab.env   # exports SUBSCRIPTION_ID, RG, ...
#   ./cleanup.sh              # interactive confirmation
#   ./cleanup.sh --yes        # non-interactive

set -euo pipefail

# Defensive guard: cleanup is DESTRUCTIVE. Refuse to run unless the
# operator's active subscription exactly matches the recorded
# SUBSCRIPTION_ID — otherwise we could delete the wrong RG.
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be exported (e.g. source /tmp/rns-lab.env)}"
ACTIVE_SUB=$(az account show --query id --output tsv 2>/dev/null || true)
if [[ "$ACTIVE_SUB" != "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: az active subscription mismatch — refusing to delete" >&2
  echo "  expected: $SUBSCRIPTION_ID" >&2
  echo "  active  : $ACTIVE_SUB" >&2
  echo "  fix     : az account set --subscription $SUBSCRIPTION_ID" >&2
  exit 1
fi

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
  - Container Apps Environment (workload-profile)
  - Both subject apps (app-consumption, app-dedicated-d8)
  - Azure Container Registry (diag image will be lost)
  - Log Analytics Workspace (raw logs will be lost)
  - VNet + subnet
  - User-assigned managed identity + role assignments

Evidence JSONL files in labs/replica-node-spread/evidence/ are NOT
touched. Charges stop only after the resource group fully deletes;
check with: az group show --name $RG

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
