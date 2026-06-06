#!/usr/bin/env bash
# verify.sh — confirm Scenario A BASELINE: revision is Healthy on the v1
# image, the / endpoint reports build_tag=v1 (proving a fresh pull of v1
# happened through the firewall), and ACR's network rule set contains the
# firewall public IP as the single ipRule.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-firewall-allowlist}"

echo "[verify] reading deployment outputs (with resource-lookup fallback)"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.appName.value --output tsv 2>/dev/null || true)"
if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "null" ]; then
  APP_NAME="$(az containerapp list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
ACR_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.registryName.value --output tsv 2>/dev/null || true)"
if [ -z "$ACR_NAME" ] || [ "$ACR_NAME" = "null" ]; then
  ACR_NAME="$(az acr list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
FW_PIP="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.firewallPublicIpAddress.value --output tsv 2>/dev/null || true)"
if [ -z "$FW_PIP" ] || [ "$FW_PIP" = "null" ]; then
  FW_PIP_NAME="$(az network firewall list --resource-group "$RG" \
    --query "[0].ipConfigurations[0].publicIPAddress.id" --output tsv | awk -F/ '{print $NF}')"
  FW_PIP="$(az network public-ip show --resource-group "$RG" --name "$FW_PIP_NAME" \
    --query ipAddress --output tsv)"
fi
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

echo "[verify] waiting 30s for revision propagation"
sleep 30

HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "sort_by(@, &properties.createdTime) | [-1].properties.healthState" --output tsv)"
PROVISION="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "sort_by(@, &properties.createdTime) | [-1].properties.provisioningState" --output tsv)"
LATEST_REV="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "sort_by(@, &properties.createdTime) | [-1].name" --output tsv)"

echo "[verify] latest revision: ${LATEST_REV} healthState=${HEALTH} provisioningState=${PROVISION}"

if [ "$HEALTH" != "Healthy" ]; then
  echo "[verify] FAIL: latest revision is not Healthy. Inspect with:"
  echo "  az containerapp logs show --name $APP_NAME --resource-group $RG --type system --tail 50"
  exit 1
fi

echo "[verify] inspecting ACR network rule set on ${ACR_NAME}"
DEFAULT_ACTION="$(az acr show --name "$ACR_NAME" \
  --query 'networkRuleSet.defaultAction' --output tsv)"
BYPASS="$(az acr show --name "$ACR_NAME" \
  --query 'networkRuleBypassOptions' --output tsv)"
ALLOWED_IPS="$(az acr show --name "$ACR_NAME" \
  --query 'networkRuleSet.ipRules[].ipAddressOrRange' --output tsv)"

echo "[verify]   defaultAction          = ${DEFAULT_ACTION}"
echo "[verify]   networkRuleBypassOptions = ${BYPASS}"
echo "[verify]   ipRules                  = ${ALLOWED_IPS}"

if [ "$DEFAULT_ACTION" != "Deny" ]; then
  echo "[verify] FAIL: ACR defaultAction is ${DEFAULT_ACTION}, expected Deny"
  exit 1
fi

if ! echo "$ALLOWED_IPS" | grep -qx "${FW_PIP}/32\|${FW_PIP}"; then
  echo "[verify] FAIL: ACR ipRules does not contain firewall public IP ${FW_PIP}"
  echo "[verify]       ipRules currently: ${ALLOWED_IPS}"
  exit 1
fi

echo "[verify] calling / on https://${APP_FQDN}/"
RESP_JSON=""
for attempt in 1 2 3 4 5; do
  RESP_JSON="$(curl -sS --max-time 30 "https://${APP_FQDN}/" || true)"
  if [ -n "$RESP_JSON" ] && echo "$RESP_JSON" | grep -q build_tag; then
    break
  fi
  echo "[verify]   attempt ${attempt}: no JSON response; retrying in 10s"
  sleep 10
done

if [ -z "$RESP_JSON" ] || ! echo "$RESP_JSON" | grep -q build_tag; then
  echo "[verify] FAIL: / did not return a usable JSON response"
  echo "[verify]   last response: ${RESP_JSON}"
  exit 1
fi

echo "[verify] / response:"
echo "$RESP_JSON" | python3 -m json.tool

BUILD_TAG="$(echo "$RESP_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("build_tag",""))')"

if [ "$BUILD_TAG" != "v1" ]; then
  echo "[verify] FAIL: build_tag=${BUILD_TAG}, expected v1"
  echo "[verify]       The replica is not running the freshly-pulled v1 image."
  exit 1
fi

echo "[verify] PASS: revision ${LATEST_REV} is Healthy"
echo "[verify] PASS: ACR locked down (Deny default + ipRules=[${FW_PIP}])"
echo "[verify] PASS: / returns build_tag=v1 (proves fresh pull of v1 through the firewall)"
echo "[verify] PASS: Scenario A BASELINE confirmed."
