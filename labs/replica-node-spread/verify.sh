#!/usr/bin/env bash
# Verify that the replica-node-spread lab is healthy and ready to sample.
#
# Checks:
#   1. Resource group exists
#   2. Env exists with BOTH workload profiles (Consumption + d8-dedicated)
#   3. Both apps reach runningStatus=Running
#   4. Both apps have at least one ready replica
#   5. /diag responds 200 on each app FQDN
#
# Required env:
#   RG               Resource group with the deployed lab.
#   SUBSCRIPTION_ID  Exact Azure subscription this lab targets (defensive).
#
# Usage:
#   source /tmp/rns-lab.env   # exports SUBSCRIPTION_ID, RG, ...
#   ./verify.sh

set -euo pipefail

# Defensive guard: verify is read-only but the per-check output would be
# confusing (all PASS or all FAIL) if it ran on the wrong subscription.
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be exported (e.g. source /tmp/rns-lab.env)}"
ACTIVE_SUB=$(az account show --query id --output tsv 2>/dev/null || true)
if [[ "$ACTIVE_SUB" != "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: az active subscription mismatch" >&2
  echo "  expected: $SUBSCRIPTION_ID" >&2
  echo "  active  : $ACTIVE_SUB" >&2
  echo "  fix     : az account set --subscription $SUBSCRIPTION_ID" >&2
  exit 1
fi

RG="${RG:-rg-aca-rns-lab}"
SUBJECT_APPS=("app-consumption" "app-dedicated-d8")
EXPECTED_PROFILES=("Consumption" "d8-dedicated")

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
echo ">> Environment + workload profiles"
ENV_NAME=$(az containerapp env list --resource-group "$RG" --query '[0].name' --output tsv 2>/dev/null || true)
if [[ -n "$ENV_NAME" ]]; then
  echo "   Environment: $ENV_NAME"
  for prof in "${EXPECTED_PROFILES[@]}"; do
    FOUND=$(az containerapp env workload-profile list --resource-group "$RG" --name "$ENV_NAME" \
      --query "[?name=='$prof'].name | [0]" --output tsv 2>/dev/null || echo "")
    check "Workload profile '$prof' present" "[[ '$FOUND' == '$prof' ]]"
  done
else
  echo "  [FAIL] No environment found"
  fail=$((fail + 1))
fi

echo
echo ">> Subject apps"
for app in "${SUBJECT_APPS[@]}"; do
  STATE=$(az containerapp show --resource-group "$RG" --name "$app" \
    --query 'properties.runningStatus' --output tsv 2>/dev/null || echo "missing")
  check "$app runningStatus = Running" "[[ '$STATE' == 'Running' ]]"

  REV=$(az containerapp revision list --resource-group "$RG" --name "$app" \
    --query '[?properties.active] | [0].name' --output tsv 2>/dev/null || echo "")
  if [[ -n "$REV" ]]; then
    REPLICAS=$(az containerapp replica list --resource-group "$RG" --name "$app" \
      --revision "$REV" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    check "$app has at least 1 replica" "[[ '$REPLICAS' -ge '1' ]]"
  else
    echo "  [FAIL] $app has no active revision"
    fail=$((fail + 1))
  fi

  FQDN=$(az containerapp show --resource-group "$RG" --name "$app" \
    --query 'properties.configuration.ingress.fqdn' --output tsv 2>/dev/null || echo "")
  if [[ -n "$FQDN" ]]; then
    CODE=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --max-time 10 "https://${FQDN}/diag" 2>/dev/null || echo "000")
    check "$app /diag responds 200 (got $CODE)" "[[ '$CODE' == '200' ]]"
  else
    echo "  [FAIL] $app has no FQDN"
    fail=$((fail + 1))
  fi
done

echo
echo "================================================================"
echo "Summary: $pass passed, $fail failed"
echo "================================================================"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
