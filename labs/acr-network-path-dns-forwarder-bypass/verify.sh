#!/usr/bin/env bash
# verify.sh — workload-path probe: confirm Healthy revision AND prove that
# socket.getaddrinfo() from inside the replica returns the PE NIC's RFC1918
# IP for the ACR FQDN (i.e. the dnsmasq forwarder is healthy and the
# Container App workload sees the private path).
#
# This lab is workload-path-only because in Azure Container Apps the platform's
# image puller does not appear to use the VNet custom DNS for ACR resolution.
# Breaking dnsmasq does NOT break image pulls; it breaks what application code
# resolves. The /probe endpoint is the observable signal for that failure.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-dns-forwarder-bypass}"

echo "[verify] reading deployment outputs"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
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

echo "[verify] inspecting PE NIC private IP for ${ACR_LOGIN_SERVER}"
NIC_ID="$(az network private-endpoint show \
  --name "$PE_NAME" --resource-group "$RG" \
  --query 'networkInterfaces[0].id' --output tsv)"
PE_IP="$(az network nic show --ids "$NIC_ID" \
  --query "ipConfigurations[?contains(to_string(privateLinkConnectionProperties.fqdns), '${ACR_LOGIN_SERVER}')] | [0].privateIPAddress" \
  --output tsv)"

if [ -z "$PE_IP" ]; then
  echo "[verify] FAIL: could not read PE private IP for ACR FQDN"
  exit 1
fi

if [[ "$PE_IP" != 10.* ]] && [[ "$PE_IP" != 172.* ]] && [[ "$PE_IP" != 192.168.* ]]; then
  echo "[verify] FAIL: PE NIC IP ${PE_IP} is not in RFC1918 — PE not provisioned correctly"
  exit 1
fi

echo "[verify] calling /probe on https://${APP_FQDN}/probe (workload-layer DNS view)"
PROBE_JSON=""
for attempt in 1 2 3 4 5; do
  PROBE_JSON="$(curl -sS --max-time 10 "https://${APP_FQDN}/probe" || true)"
  if [ -n "$PROBE_JSON" ] && echo "$PROBE_JSON" | grep -q first_class; then
    break
  fi
  echo "[verify] probe attempt ${attempt} did not return JSON; retrying in 10s"
  sleep 10
done

if [ -z "$PROBE_JSON" ] || ! echo "$PROBE_JSON" | grep -q first_class; then
  echo "[verify] FAIL: /probe did not return a usable JSON response"
  echo "[verify]   last response: ${PROBE_JSON}"
  exit 1
fi

echo "[verify] /probe response: ${PROBE_JSON}"

FIRST_CLASS="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("first_class",""))')"
FIRST_IP="$(echo "$PROBE_JSON" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("addresses",[{}])[0].get("ip",""))')"

if [ "$FIRST_CLASS" != "private" ]; then
  echo "[verify] FAIL: workload-side getaddrinfo returned first_class=${FIRST_CLASS}, expected private"
  echo "[verify]       This means the dnsmasq forwarder bypassed Azure DNS (Scenario E)."
  exit 1
fi

if [ "$FIRST_IP" != "$PE_IP" ]; then
  echo "[verify] FAIL: workload resolved ${ACR_LOGIN_SERVER} to ${FIRST_IP} but PE NIC IP is ${PE_IP}"
  exit 1
fi

echo "[verify] PASS: revision is Healthy"
echo "[verify] PASS: workload /probe resolved ${ACR_LOGIN_SERVER} → ${FIRST_IP} (private, matches PE NIC IP ${PE_IP})"
echo "[verify] PASS: dnsmasq forwarder is correctly routing workload DNS to Azure DNS → Private DNS Zone → PE NIC"
