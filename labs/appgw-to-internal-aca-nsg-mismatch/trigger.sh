#!/usr/bin/env bash
# trigger.sh — bring the lab from BASELINE (empty NSG, AppGW backend
# Healthy) to BROKEN (NSG rule 100 Destination pinned to staticIp/32,
# AppGW backend Unhealthy). Isolates H1 by leaving the destination-port
# list correct (443, 31443) so the ONLY failure driver is rule 100's
# Destination address.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${LAB_DIR}/evidence"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-appgw-aca-nsg-mismatch}"

mkdir -p "$EVIDENCE_DIR"

echo "[trigger] step 1: reading deployment outputs from ${DEPLOYMENT_NAME}"
az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs --output json \
  > "$EVIDENCE_DIR/deploy-outputs.json"

RG_OUT=$(jq -r '.resourceGroupName.value' "$EVIDENCE_DIR/deploy-outputs.json")
CAE_STATIC_IP=$(jq -r '.environmentStaticIp.value' "$EVIDENCE_DIR/deploy-outputs.json")
APPGW_SUBNET_PREFIX=$(jq -r '.appgwSubnetPrefix.value' "$EVIDENCE_DIR/deploy-outputs.json")
CAE_SUBNET_PREFIX=$(jq -r '.caeSubnetPrefix.value' "$EVIDENCE_DIR/deploy-outputs.json")
CAE_NSG_NAME=$(jq -r '.caeNsgName.value' "$EVIDENCE_DIR/deploy-outputs.json")
APPGW_NAME=$(jq -r '.appgwName.value' "$EVIDENCE_DIR/deploy-outputs.json")
APPGW_PUB_IP=$(jq -r '.appgwPublicIpAddress.value' "$EVIDENCE_DIR/deploy-outputs.json")
APP_FQDN=$(jq -r '.appFqdn.value' "$EVIDENCE_DIR/deploy-outputs.json")

echo "[trigger]   RG:              $RG_OUT"
echo "[trigger]   CAE staticIp:    $CAE_STATIC_IP  <-- misconfig target"
echo "[trigger]   AppGW subnet:    $APPGW_SUBNET_PREFIX"
echo "[trigger]   CAE subnet:      $CAE_SUBNET_PREFIX"
echo "[trigger]   NSG name:        $CAE_NSG_NAME"
echo "[trigger]   AppGW name:      $APPGW_NAME"
echo "[trigger]   AppGW public IP: $APPGW_PUB_IP"
echo "[trigger]   App FQDN:        $APP_FQDN"

# AppGW default probe interval is 30s and unhealthyThreshold is 3, so
# the backend can take up to 90s to converge to Healthy after deployment.
echo "[trigger] step 2: waiting 120s for AppGW backend to converge to Healthy (baseline)"
sleep 120

echo "[trigger] step 3: capturing baseline evidence"
az network application-gateway show-backend-health \
  --name "$APPGW_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/baseline-backend-health.json"

az network nsg rule list \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/baseline-nsg-rules.json"

curl -sS --connect-timeout 10 --max-time 20 \
  -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  "http://${APPGW_PUB_IP}/" \
  > "$EVIDENCE_DIR/baseline-curl.txt" 2>&1 || true

echo "[trigger] step 4: applying 3-rule misconfiguration"
# Rule 100 is the H1 misconfiguration: Destination pinned to staticIp/32.
# Rule 200 and 4096 make the NSG a realistic locked-down production NSG:
# without them, the default AllowVnetInBound (priority 65000) would let
# packets in through the vnet path and mask the rule-100 failure. The
# combination "explicit Allow at 100 + explicit LB Allow at 200 + Deny-all
# at 4096" is the same shape production operators write when they lock
# down a subnet NSG, and it is the shape that surfaces H1 as a hard block.
az network nsg rule create \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" \
  --name "allow-appgw-inbound-broken" \
  --priority 100 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$APPGW_SUBNET_PREFIX" \
  --source-port-ranges "*" \
  --destination-address-prefixes "${CAE_STATIC_IP}/32" \
  --destination-port-ranges "443" "31443" \
  --output none

az network nsg rule create \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" \
  --name "allow-azure-lb-probes" \
  --priority 200 \
  --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "AzureLoadBalancer" \
  --source-port-ranges "*" \
  --destination-address-prefixes "$CAE_SUBNET_PREFIX" \
  --destination-port-ranges "30000-32767" \
  --output none

az network nsg rule create \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" \
  --name "deny-all-inbound" \
  --priority 4096 \
  --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "*" \
  --output none

echo "[trigger] step 5: waiting 150s for AppGW probes to re-converge under the new NSG"
sleep 150

echo "[trigger] step 6: capturing broken evidence"
az network application-gateway show-backend-health \
  --name "$APPGW_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/broken-backend-health.json"

az network nsg rule list \
  --nsg-name "$CAE_NSG_NAME" --resource-group "$RG" --output json \
  > "$EVIDENCE_DIR/broken-nsg-rules.json"

curl -sS --connect-timeout 10 --max-time 20 \
  -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" \
  "http://${APPGW_PUB_IP}/" \
  > "$EVIDENCE_DIR/broken-curl.txt" 2>&1 || true

echo "[trigger] DONE. Next: bash verify.sh"
