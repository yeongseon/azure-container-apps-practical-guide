#!/usr/bin/env bash
# trigger.sh — switch the Container App from the public placeholder image to
# the private ACR image, validating that the Private DNS zone holds BOTH the
# registry and the data records (baseline state for Scenario D). falsify.sh
# later deletes the data record to drive the lab into the record-level
# split-brain failure mode.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-record-split-brain}"

echo "[trigger] reading deployment outputs from ${DEPLOYMENT_NAME}"
ACR_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryName.value --output tsv)"
ACR_LOGIN_SERVER="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerRegistryLoginServer.value --output tsv)"
APP_NAME="$(az deployment group show \
  --resource-group "$RG" --name "$DEPLOYMENT_NAME" \
  --query properties.outputs.containerAppName.value --output tsv)"

IMAGE_REPO="${IMAGE_REPO:-record-split-brain-lab}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${IMAGE_TAG}"

# Same public-toggle dance as the sibling labs: the Bicep ships the registry
# with publicNetworkAccess=Disabled, ACR Tasks build agents need the public
# surface to push the freshly built image, so we briefly enable it for the
# duration of `az acr build` and disable it again before the Container App
# pull. The Container App pull still flows through the PE because the FQDN
# resolves to the PE NIC's private IP via the linked privatelink.azurecr.io
# zone.
PREV_PUBLIC="$(az acr show --name "$ACR_NAME" --resource-group "$RG" \
  --query 'publicNetworkAccess' --output tsv)"

if [ "$PREV_PUBLIC" = "Disabled" ]; then
  echo "[trigger] temporarily enabling publicNetworkAccess on $ACR_NAME for the build"
  az acr update --name "$ACR_NAME" \
    --public-network-enabled true \
    --default-action Allow --output none
  echo "[trigger] waiting 60s for the public surface to stabilize"
  sleep 60
fi

echo "[trigger] building ${FULL_IMAGE} via az acr build (server-side)"
az acr build \
  --registry "$ACR_NAME" \
  --image "${IMAGE_REPO}:${IMAGE_TAG}" \
  --file "${LAB_DIR}/workload/Dockerfile" \
  "${LAB_DIR}/workload" \
  --output none

if [ "$PREV_PUBLIC" = "Disabled" ]; then
  echo "[trigger] restoring publicNetworkAccess=Disabled on $ACR_NAME"
  az acr update --name "$ACR_NAME" --public-network-enabled false --output none
fi

echo "[trigger] waiting 30s for ACR PE / Private DNS to stabilize"
sleep 30

echo "[trigger] switching app ${APP_NAME} to ${FULL_IMAGE} (identity=system)"
az containerapp registry set \
  --name "$APP_NAME" --resource-group "$RG" \
  --identity system --server "$ACR_LOGIN_SERVER" \
  --output none

az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --image "$FULL_IMAGE" \
  --set-env-vars "BUILD_TAG=${IMAGE_TAG}" \
  --output none

echo "[trigger] done. Run verify.sh to check the /probe endpoint returns topology_class=both_private."
