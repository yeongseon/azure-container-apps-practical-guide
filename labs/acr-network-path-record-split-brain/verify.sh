#!/usr/bin/env bash
# verify.sh — confirm Healthy revision AND prove that the 4-layer /probe from
# inside the replica reports topology_class=both_private (registry and data
# both resolving to PE NIC private IPs). This is the Scenario D BASELINE
# state. falsify.sh later deletes the data record and the probe should flip
# to topology_class=data_nxdomain.
#
# Empirical note: the ACR registry endpoint returns HTTP 401 on /v2/ via the
# private path (auth challenge from the ACR backend), but the ACR data
# endpoint returns HTTP 403 on /v2/ via the private path even in the BASELINE
# state. Both responses prove the PE path is alive end-to-end (TCP+TLS+HTTP
# all succeed against the PE NIC IP); the 401 vs 403 difference is just how
# the two ACR endpoint types respond to an unauthenticated /v2/ probe. The
# strongest single signal in this lab is therefore the DNS IP class (private
# vs NXDOMAIN), not the HTTP status code.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-record-split-brain}"

echo "[verify] reading deployment outputs"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
ACR_DATA_FQDN="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryDataFqdn.value --output tsv)"
PE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.privateEndpointName.value --output tsv)"
APP_FQDN="$(az containerapp show \
  --name "$APP_NAME" --resource-group "$RG" \
  --query properties.configuration.ingress.fqdn --output tsv)"

echo "[verify] waiting 30s for revision propagation"
sleep 30

HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].properties.healthState" --output tsv)"
PROVISION="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].properties.provisioningState" --output tsv)"

echo "[verify] latest revision: healthState=${HEALTH} provisioningState=${PROVISION}"

if [ "$HEALTH" != "Healthy" ]; then
  echo "[verify] FAIL: latest revision is not Healthy. Inspect with:"
  echo "  az containerapp logs show --name $APP_NAME --resource-group $RG --type system --tail 50"
  exit 1
fi

echo "[verify] inspecting PE NIC private IPs for ${ACR_LOGIN_SERVER} and ${ACR_DATA_FQDN}"
NIC_ID="$(az network private-endpoint show \
  --name "$PE_NAME" --resource-group "$RG" \
  --query 'networkInterfaces[0].id' --output tsv)"
REGISTRY_PE_IP="$(az network nic show --ids "$NIC_ID" \
  --query "ipConfigurations[?contains(to_string(privateLinkConnectionProperties.fqdns), '${ACR_LOGIN_SERVER}')] | [0].privateIPAddress" \
  --output tsv)"
DATA_PE_IP="$(az network nic show --ids "$NIC_ID" \
  --query "ipConfigurations[?contains(to_string(privateLinkConnectionProperties.fqdns), '${ACR_DATA_FQDN}')] | [0].privateIPAddress" \
  --output tsv)"

if [ -z "$REGISTRY_PE_IP" ] || [ -z "$DATA_PE_IP" ]; then
  echo "[verify] FAIL: could not read both PE private IPs"
  echo "[verify]   registry: ${REGISTRY_PE_IP}"
  echo "[verify]   data    : ${DATA_PE_IP}"
  exit 1
fi

echo "[verify] PE NIC IPs: registry=${REGISTRY_PE_IP}, data=${DATA_PE_IP}"

echo "[verify] calling /probe on https://${APP_FQDN}/probe (4-layer dual-FQDN view)"
PROBE_JSON=""
for attempt in 1 2 3 4 5; do
  PROBE_JSON="$(curl -sS --max-time 30 "https://${APP_FQDN}/probe" || true)"
  if [ -n "$PROBE_JSON" ] && echo "$PROBE_JSON" | grep -q topology_class; then
    break
  fi
  echo "[verify] probe attempt ${attempt} did not return JSON; retrying in 10s"
  sleep 10
done

if [ -z "$PROBE_JSON" ] || ! echo "$PROBE_JSON" | grep -q topology_class; then
  echo "[verify] FAIL: /probe did not return a usable JSON response"
  echo "[verify]   last response: ${PROBE_JSON}"
  exit 1
fi

echo "[verify] /probe response:"
echo "$PROBE_JSON" | python3 -m json.tool

TOPOLOGY="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("topology_class",""))')"
REG_IP="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["registry"]["dns"].get("ip",""))')"
REG_CLASS="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["registry"]["dns"].get("class",""))')"
REG_HTTP="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["registry"]["http"].get("status",""))')"
DAT_IP="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["dns"].get("ip",""))')"
DAT_CLASS="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["dns"].get("class",""))')"
DAT_HTTP="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["http"].get("status",""))')"

if [ "$TOPOLOGY" != "both_private" ]; then
  echo "[verify] FAIL: topology_class=${TOPOLOGY}, expected both_private"
  echo "[verify]       Baseline state requires BOTH FQDNs to resolve privately."
  exit 1
fi

if [ "$REG_CLASS" != "private" ] || [ "$REG_IP" != "$REGISTRY_PE_IP" ]; then
  echo "[verify] FAIL: registry probe DNS mismatch — class=${REG_CLASS} ip=${REG_IP} (expected private ${REGISTRY_PE_IP})"
  exit 1
fi

if [ "$DAT_CLASS" != "private" ] || [ "$DAT_IP" != "$DATA_PE_IP" ]; then
  echo "[verify] FAIL: data probe DNS mismatch — class=${DAT_CLASS} ip=${DAT_IP} (expected private ${DATA_PE_IP})"
  exit 1
fi

if [ "$REG_HTTP" != "401" ]; then
  echo "[verify] WARN: registry HTTP status=${REG_HTTP}, expected 401 (auth required from ACR backend)"
fi

if [ "$DAT_HTTP" != "403" ] && [ "$DAT_HTTP" != "401" ]; then
  echo "[verify] WARN: data HTTP status=${DAT_HTTP}, expected 403 (ACR data endpoint default) or 401"
fi

echo "[verify] PASS: revision is Healthy"
echo "[verify] PASS: workload /probe topology_class=both_private"
echo "[verify] PASS: registry ${ACR_LOGIN_SERVER} -> ${REG_IP} (private, matches PE NIC IP ${REGISTRY_PE_IP}), HTTP ${REG_HTTP}"
echo "[verify] PASS: data     ${ACR_DATA_FQDN} -> ${DAT_IP} (private, matches PE NIC IP ${DATA_PE_IP}), HTTP ${DAT_HTTP}"
echo "[verify] PASS: Scenario D BASELINE confirmed. Both records present in the private DNS zone."
