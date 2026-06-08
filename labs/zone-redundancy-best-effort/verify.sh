#!/usr/bin/env bash
# Verify that the lab infrastructure is healthy.
#
# Usage:
#   export RG="rg-aca-zr-lab"
#   ./verify.sh

set -euo pipefail

RG="${RG:-rg-aca-zr-lab}"
SUBJECT_APPS=("app-min2" "app-min3" "app-min6")

pass=0
fail=0

check() {
  local label="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  [PASS] $label"
    pass=$((pass + 1))
  else
    echo "  [FAIL] $label"
    fail=$((fail + 1))
  fi
}

echo ">> Resource group $RG"
check "Resource group exists" "az group show --name $RG"

echo
echo ">> Environment"
ENV_NAME=$(az containerapp env list --resource-group "$RG" --query '[0].name' --output tsv 2>/dev/null || true)
if [[ -n "$ENV_NAME" ]]; then
  echo "   Environment: $ENV_NAME"
  ZR=$(az containerapp env show --resource-group "$RG" --name "$ENV_NAME" --query 'properties.zoneRedundant' --output tsv 2>/dev/null || echo "")
  check "Zone redundancy enabled" "[[ '$ZR' == 'True' || '$ZR' == 'true' ]]"
else
  echo "  [FAIL] No environment found"
  fail=$((fail + 1))
fi

echo
echo ">> Subject apps"
for app in "${SUBJECT_APPS[@]}"; do
  STATE=$(az containerapp show --resource-group "$RG" --name "$app" --query 'properties.runningStatus' --output tsv 2>/dev/null || echo "missing")
  check "$app runningStatus = Running" "[[ '$STATE' == 'Running' ]]"

  MIN_REPLICAS=$(az containerapp show --resource-group "$RG" --name "$app" --query 'properties.template.scale.minReplicas' --output tsv 2>/dev/null || echo "0")
  EXPECTED=$(echo "$app" | sed 's/app-min//')
  check "$app minReplicas = $EXPECTED" "[[ '$MIN_REPLICAS' == '$EXPECTED' ]]"

  REPLICAS=$(az containerapp replica list --resource-group "$RG" --name "$app" --revision "$(az containerapp revision list --resource-group "$RG" --name "$app" --query '[?properties.active].name | [0]' --output tsv 2>/dev/null)" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
  check "$app has at least $EXPECTED running replicas" "[[ '$REPLICAS' -ge '$EXPECTED' ]]"
done

echo
echo ">> Audit job"
JOB_STATE=$(az containerapp job show --resource-group "$RG" --name "audit-sampler" --query 'properties.provisioningState' --output tsv 2>/dev/null || echo "missing")
check "Audit job provisioned" "[[ '$JOB_STATE' == 'Succeeded' ]]"

echo
echo ">> Log Analytics"
LAW_NAME=$(az monitor log-analytics workspace list --resource-group "$RG" --query '[0].name' --output tsv 2>/dev/null || true)
check "Log Analytics workspace exists" "[[ -n '$LAW_NAME' ]]"

echo
echo "================================================================"
echo "Summary: $pass passed, $fail failed"
echo "================================================================"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
