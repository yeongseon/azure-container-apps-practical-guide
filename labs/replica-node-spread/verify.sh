#!/usr/bin/env bash
# Verify that the replica-node-spread lab is healthy and ready to sample.
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   ./verify.sh

set -uo pipefail

RG="${RG:-rg-aca-rns-lab}"
CONSUMPTION_APP="${CONSUMPTION_APP:-ca-diag-consumption}"
DEDICATED_APP="${DEDICATED_APP:-ca-diag-dedicated}"

# az containerapp exec requires a PTY. See sample.sh for full rationale.
exec_in_pty() {
  if script --version >/dev/null 2>&1; then
    script -q -c "$*" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

pass=0
fail=0

check() {
  local label="$1" cmd="$2"
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
  PROFILES=$(az containerapp env workload-profile list --resource-group "$RG" --name "$ENV_NAME" --query '[].name' --output tsv 2>/dev/null || echo "")
  check "Consumption profile present" "echo '$PROFILES' | grep -qx Consumption"
  check "Dedicated profile present" "echo '$PROFILES' | grep -qi dedicated"
else
  echo "  [FAIL] No environment found"
  fail=$((fail + 1))
fi

for app in "$CONSUMPTION_APP" "$DEDICATED_APP"; do
  echo
  echo ">> App $app"
  STATE=$(az containerapp show --resource-group "$RG" --name "$app" --query 'properties.runningStatus' --output tsv 2>/dev/null || echo "missing")
  check "$app runningStatus = Running" "[[ '$STATE' == 'Running' ]]"

  REV=$(az containerapp revision list --resource-group "$RG" --name "$app" --query '[?properties.active].name | [0]' --output tsv 2>/dev/null)
  if [[ -n "$REV" ]]; then
    REPLICAS=$(az containerapp replica list --resource-group "$RG" --name "$app" --revision "$REV" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    check "$app has at least 1 replica" "[[ '$REPLICAS' -ge '1' ]]"
  else
    echo "  [FAIL] $app has no active revision"
    fail=$((fail + 1))
  fi
done

echo
echo ">> Probing diag.sh on first Consumption replica"
FIRST_REV=$(az containerapp revision list --resource-group "$RG" --name "$CONSUMPTION_APP" --query '[?properties.active].name | [0]' --output tsv 2>/dev/null)
FIRST_REPLICA=$(az containerapp replica list --resource-group "$RG" --name "$CONSUMPTION_APP" --revision "$FIRST_REV" --query '[0].name' --output tsv 2>/dev/null)
if [[ -n "$FIRST_REPLICA" ]]; then
  echo "   Replica: $FIRST_REPLICA"
  OUT=$(exec_in_pty az containerapp exec \
    --resource-group "$RG" \
    --name "$CONSUMPTION_APP" \
    --revision "$FIRST_REV" \
    --replica "$FIRST_REPLICA" \
    --container diag \
    --command "/usr/local/bin/diag.sh" 2>/dev/null \
    | tr -d '\r' \
    | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
    | grep -E '^\{' \
    | head -n1)
  if [[ -n "$OUT" ]] && echo "$OUT" | jq -e .boot_id >/dev/null 2>&1; then
    echo "  [PASS] diag.sh returns parseable JSON with boot_id"
    echo "         $OUT" | head -c 200
    echo
    pass=$((pass + 1))
  else
    echo "  [FAIL] diag.sh did not return parseable JSON"
    echo "         raw output: $OUT"
    fail=$((fail + 1))
  fi
fi

echo
echo "================================================================"
echo "Summary: $pass passed, $fail failed"
echo "================================================================"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
