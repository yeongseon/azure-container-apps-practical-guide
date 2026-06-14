#!/usr/bin/env bash
# Cleanup wrapper for the startup-degraded-transient-failure lab.
#
# Issues `az group delete --yes --no-wait` on the lab resource group
# after explicit confirmation. Azure may keep delete-pending resources
# for up to 24 hours; charges stop once the deletion completes.

set -euo pipefail

RG="${RG:?RG must be set, e.g. rg-aca-startup-degraded}"

echo ">> About to DELETE resource group: $RG"
echo ">> This will permanently destroy the env, all apps, jobs, ACR role"
echo "   assignments, the LAW, VNet, and UAMI. The audit logs already"
echo "   ingested into Log Analytics will be retained per the workspace"
echo "   retention policy (90 days), so re-deploying later does NOT lose"
echo "   prior evidence."
echo
read -r -p ">> Type the resource group name to confirm: " confirm
if [[ "$confirm" != "$RG" ]]; then
  echo "ABORTED. Confirmation did not match."
  exit 1
fi

echo ">> Submitting az group delete --no-wait"
az group delete --name "$RG" --yes --no-wait

echo ">> Delete submitted. Check status with:"
echo "   az group show --name $RG --query properties.provisioningState --output tsv"
