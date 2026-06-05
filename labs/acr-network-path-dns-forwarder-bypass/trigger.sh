#!/usr/bin/env bash
# trigger.sh — switch the Container App from the public placeholder image to
# the private ACR image, validating that the dnsmasq forwarder is wired
# correctly (HEALTHY state for Scenario E). falsify.sh later removes the
# conditional forward to drive the lab into the bypass failure mode.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-acr-dns-forwarder-bypass}"

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

IMAGE_REPO="${IMAGE_REPO:-dns-forwarder-bypass-lab}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${IMAGE_TAG}"

# The Bicep ships the registry with publicNetworkAccess=Disabled so the only
# data-plane path is the Private Endpoint. ACR Tasks build agents, however,
# come from a public Azure pool that needs the registry's public surface to
# push the freshly built image. We temporarily enable public access for the
# build, then disable it again so the lab's "Disabled" pedagogical state is
# restored before verify.sh runs. The Container App pull still flows through
# the PE because the FQDN resolves to the PE NIC's private IP via the linked
# privatelink.azurecr.io zone (provided the dnsmasq forwarder rule is in
# place).
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

echo "[trigger] waiting 30s for ACR PE / Private DNS / dnsmasq to stabilize"
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

echo "[trigger] done. Run verify.sh to check the new revision pulled through the dnsmasq forwarder."
