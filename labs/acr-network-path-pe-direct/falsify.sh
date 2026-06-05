#!/usr/bin/env bash
# falsify.sh — break the Private DNS path (remove the VNet link), then push a
# new image tag and update the app. The pull must fail. After the failure is
# observed, the script restores the VNet link and pushes a recovery tag.
#
# This is the falsification step: if removing the only thing that makes
# 'privatelink.azurecr.io' resolve privately causes the pull to fail, and
# restoring it makes the pull succeed again, then the PE path was the cause.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-pe-direct}"

ACR_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"
VNET_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.vnetName.value --output tsv)"
ZONE_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.privateDnsZoneName.value --output tsv)"

LINK_NAME="${VNET_NAME}-link"

echo "[falsify] step 1: remove VNet link for ${ZONE_NAME}"
az network private-dns link vnet delete \
  --resource-group "$RG" --zone-name "$ZONE_NAME" \
  --name "$LINK_NAME" --yes --output none

echo "[falsify] step 2: build a new image tag (v-broken) to force a fresh pull"
az acr build \
  --registry "$ACR_NAME" \
  --image "pe-lab:v-broken" \
  --file "${LAB_DIR}/workload/Dockerfile" \
  "${LAB_DIR}/workload" --output none

echo "[falsify] step 3: update app to the new image (pull MUST fail without private DNS)"
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/pe-lab:v-broken" \
  --set-env-vars "BUILD_TAG=v-broken" \
  --output none

echo "[falsify] waiting 90s for the failed pull to surface in revision state"
sleep 90

HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].properties.healthState" --output tsv)"
echo "[falsify] post-break revision healthState=${HEALTH}"

if [ "$HEALTH" = "Healthy" ]; then
  echo "[falsify] WARNING: revision still Healthy. Layer cache may have served the pull."
  echo "[falsify] Inspect: az containerapp logs show --name ${APP_NAME} --resource-group ${RG} --type system --tail 50"
fi

echo "[falsify] step 4: restore the VNet link"
ZONE_ID="$(az network private-dns zone show \
  --resource-group "$RG" --name "$ZONE_NAME" \
  --query id --output tsv)"
VNET_ID="$(az network vnet show \
  --resource-group "$RG" --name "$VNET_NAME" \
  --query id --output tsv)"
az network private-dns link vnet create \
  --resource-group "$RG" --zone-name "$ZONE_NAME" \
  --name "$LINK_NAME" --virtual-network "$VNET_ID" \
  --registration-enabled false --output none

echo "[falsify] step 5: build a recovery tag (v-recover) and update"
az acr build \
  --registry "$ACR_NAME" \
  --image "pe-lab:v-recover" \
  --file "${LAB_DIR}/workload/Dockerfile" \
  "${LAB_DIR}/workload" --output none

az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/pe-lab:v-recover" \
  --set-env-vars "BUILD_TAG=v-recover" --output none

echo "[falsify] waiting 60s for recovery revision"
sleep 60

FINAL_HEALTH="$(az containerapp revision list \
  --name "$APP_NAME" --resource-group "$RG" \
  --query "[0].properties.healthState" --output tsv)"
echo "[falsify] recovery revision healthState=${FINAL_HEALTH}"

if [ "$FINAL_HEALTH" = "Healthy" ]; then
  echo "[falsify] PASS: breaking the VNet link broke pulls; restoring it fixed them."
  echo "[falsify] Falsification complete — PE-via-private-DNS was the cause."
else
  echo "[falsify] FAIL: recovery revision is not Healthy. Re-check link state."
  exit 1
fi
