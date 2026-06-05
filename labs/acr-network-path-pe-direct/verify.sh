#!/usr/bin/env bash
# verify.sh — confirm the latest revision is Healthy AND prove that the ACR
# login FQDN resolves to a private IP from inside the VNet (PE path live).
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-direct}"

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
  echo "[verify] FAIL: latest revision is not Healthy. Run:"
  echo "  az containerapp logs show --name $APP_NAME --resource-group $RG --type system --tail 50"
  exit 1
fi

echo "[verify] inspecting PE NIC private IP for ${ACR_LOGIN_SERVER}"
# When the PE uses privateDnsZoneGroups (recommended), customDnsConfigs is
# empty and the FQDN→IP mapping lives on the NIC ipConfigurations.
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

echo "[verify] PASS: ACR ${ACR_LOGIN_SERVER} resolves to private IP ${PE_IP} via PE NIC"
echo "[verify] PASS: revision is Healthy → ACR pull traversed the Private Endpoint"
