#!/usr/bin/env bash
# fix.sh — apply the H1 fix (rewrite NSG rule 100 Destination from
# staticIp/32 to the CAE subnet CIDR) and capture the fixed evidence.
# All other rule properties (Source, ports, protocol, priority) are
# preserved so the only variable that changes between broken and fixed
# states is rule 100's Destination address.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${LAB_DIR}/evidence"

if [[ ! -f "$EVIDENCE_DIR/deploy-outputs.json" ]]; then
  echo "[fix] FAIL: $EVIDENCE_DIR/deploy-outputs.json is missing. Run trigger.sh first."
  exit 1
fi

CAE_SUBNET_PREFIX=$(jq -r '.caeSubnetPrefix.value' "$EVIDENCE_DIR/deploy-outputs.json")
CAE_NSG_NAME=$(jq -r '.caeNsgName.value' "$EVIDENCE_DIR/deploy-outputs.json")
APPGW_NAME=$(jq -r '.appgwName.value' "$EVIDENCE_DIR/deploy-outputs.json")
APPGW_PUB_IP=$(jq -r '.appgwPublicIpAddress.value' "$EVIDENCE_DIR/deploy-outputs.json")

echo "[fix] step 1: rewriting NSG rule 100 Destination to $CAE_SUBNET_PREFIX"
az network nsg rule update \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" \
  --name "allow-appgw-inbound-broken" \
  --destination-address-prefixes "$CAE_SUBNET_PREFIX" \
  --output none

echo "[fix] step 2: waiting 150s for AppGW probes to re-converge under the fixed NSG"
sleep 150

echo "[fix] step 3: capturing fixed evidence"
az network application-gateway show-backend-health \
  --name "$APPGW_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/fixed-backend-health.json"

az network nsg rule list \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/fixed-nsg-rules.json"

curl -sS --connect-timeout 10 --max-time 20 \
  -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  "http://${APPGW_PUB_IP}/" \
  > "$EVIDENCE_DIR/fixed-curl.txt" 2>&1 || true

echo "[fix] DONE. Next: bash verify.sh (expect falsification == FIX_VERIFIED)"
