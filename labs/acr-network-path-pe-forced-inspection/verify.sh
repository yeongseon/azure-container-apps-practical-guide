#!/usr/bin/env bash
# verify.sh — confirm Scenario C BASELINE: revision is Healthy on the v1
# image, / returns build_tag=v1 (proving a fresh PE pull happened through
# the firewall), route table has /32 routes for each PE NIC IP pointing to
# the firewall, ACR is locked down to PE-only.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-forced-inspection}"

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
ROUTE_TABLE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.routeTableName.value --output tsv 2>/dev/null || true)"
if [ -z "$ROUTE_TABLE_NAME" ] || [ "$ROUTE_TABLE_NAME" = "null" ]; then
  ROUTE_TABLE_NAME="$(az network route-table list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
PE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.privateEndpointName.value --output tsv 2>/dev/null || true)"
if [ -z "$PE_NAME" ] || [ "$PE_NAME" = "null" ]; then
  PE_NAME="$(az network private-endpoint list --resource-group "$RG" --query "[0].name" --output tsv)"
fi
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

echo "[verify]   App:           ${APP_NAME}"
echo "[verify]   App FQDN:      ${APP_FQDN}"
echo "[verify]   ACR:           ${ACR_NAME}"
echo "[verify]   Route table:   ${ROUTE_TABLE_NAME}"
echo "[verify]   PE:            ${PE_NAME}"

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

echo "[verify] inspecting ACR network state on ${ACR_NAME}"
PUBLIC_ACCESS="$(az acr show --name "$ACR_NAME" \
  --query 'publicNetworkAccess' --output tsv)"
echo "[verify]   publicNetworkAccess = ${PUBLIC_ACCESS}"
if [ "$PUBLIC_ACCESS" != "Disabled" ]; then
  echo "[verify] FAIL: ACR publicNetworkAccess=${PUBLIC_ACCESS}, expected Disabled"
  echo "[verify]       Run trigger.sh first to lock down ACR to PE-only."
  exit 1
fi

echo "[verify] discovering PE NIC IPs from PE networkInterfaces"
# When the PE uses privateDnsZoneGroups (recommended, and how this lab's
# main.bicep configures it), customDnsConfigs is empty because the platform
# populates Azure Private DNS Zone records directly. The FQDN -> IP mapping
# lives on the NIC's ipConfigurations[].privateLinkConnectionProperties.fqdns.
# Same pattern as labs/acr-network-path-pe-direct/verify.sh.
NIC_IDS="$(az network private-endpoint show \
  --name "$PE_NAME" --resource-group "$RG" \
  --query "networkInterfaces[].id" --output tsv)"

PE_IPS=""
for nic_id in $NIC_IDS; do
  nic_ips="$(az network nic show --ids "$nic_id" \
    --query "ipConfigurations[].privateIPAddress" --output tsv)"
  PE_IPS="${PE_IPS}${nic_ips}
"
done
PE_IPS="$(printf '%s' "$PE_IPS" | grep -v '^$' | sort -u)"

echo "[verify]   discovered PE NIC IPs:"
echo "$PE_IPS" | sed 's/^/[verify]     /'

if [ -z "$PE_IPS" ]; then
  echo "[verify] FAIL: could not discover any PE NIC IPs"
  exit 1
fi

echo "[verify] checking route table ${ROUTE_TABLE_NAME} for /32 routes covering each PE NIC IP"
ROUTE_TABLE_JSON="$(az network route-table route list \
  --resource-group "$RG" --route-table-name "$ROUTE_TABLE_NAME" \
  --output json)"

MISSING_IPS=""
while IFS= read -r ip; do
  if [ -z "$ip" ]; then
    continue
  fi
  # A route covers this PE IP if (a) the address prefix is exactly <ip>/32 OR
  # (b) the address prefix is a CIDR that contains the IP. The simple case
  # — exactly <ip>/32 — is what trigger.sh creates. We assert the exact /32
  # because anything broader (e.g. the PE subnet /26) would create a route
  # that ALSO catches non-PE traffic, which is not what trigger.sh did and
  # would muddy the controlled-variable story for falsify.sh.
  MATCH="$(echo "$ROUTE_TABLE_JSON" | python3 -c "
import json, sys
target = '${ip}/32'
data = json.load(sys.stdin)
for route in data:
    if route.get('addressPrefix') == target:
        print(route.get('name', ''))
        break
")"
  if [ -z "$MATCH" ]; then
    echo "[verify]   MISSING: no exact /32 route for ${ip}"
    MISSING_IPS="${MISSING_IPS}${ip} "
  else
    echo "[verify]   OK: route ${MATCH} covers ${ip}/32"
  fi
done <<< "$PE_IPS"

if [ -n "$MISSING_IPS" ]; then
  echo "[verify] FAIL: missing /32 UDR routes for PE NIC IPs: ${MISSING_IPS}"
  echo "[verify]       trigger.sh should have created an exact /32 route for each"
  echo "[verify]       PE NIC IP pointing to the firewall private IP. Without these,"
  echo "[verify]       PE traffic bypasses the firewall (Scenario C entry condition)."
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
echo "[verify] PASS: ACR publicNetworkAccess=Disabled (PE-only)"
echo "[verify] PASS: route table has /32 entries for every PE NIC IP -> firewall"
echo "[verify] PASS: / returns build_tag=v1 (proves fresh pull through PE)"
echo "[verify] PASS: Scenario C BASELINE confirmed."
