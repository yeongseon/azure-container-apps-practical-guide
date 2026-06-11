#!/usr/bin/env bash
# Deploy the replica-node-spread lab.
#
# Stage 1: create resource group + ACR.
# Stage 2: build the diag image with `az acr build`.
# Stage 3: deploy main.bicep with diagAcrName + diagImage wired.
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   export LOCATION="koreacentral"
#   export ACR_NAME="acrrnslab<random>"
#   ./deploy.sh
#
# Optional:
#   export BASE_NAME="rnslab"
#   export EXPIRY_HOURS=24
#   export DIAG_IMAGE_TAG="diag:latest"

set -euo pipefail

RG="${RG:-rg-aca-rns-lab}"
LOCATION="${LOCATION:-koreacentral}"
ACR_NAME="${ACR_NAME:-acrrnslab$(date +%s | tail -c 6)}"
BASE_NAME="${BASE_NAME:-rnslab}"
EXPIRY_HOURS="${EXPIRY_HOURS:-24}"
DIAG_IMAGE_TAG="${DIAG_IMAGE_TAG:-diag:latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/infra"
APP_DIR="${SCRIPT_DIR}/app"

echo ">> replica-node-spread lab deploy"
echo "   Resource group   : $RG"
echo "   Location         : $LOCATION"
echo "   ACR name         : $ACR_NAME"
echo "   Base name        : $BASE_NAME"
echo "   Expiry hours     : $EXPIRY_HOURS"
echo "   Diag image tag   : $DIAG_IMAGE_TAG"
echo

if ! az group show --name "$RG" --output none 2>/dev/null; then
  echo ">> Creating resource group $RG"
  az group create --name "$RG" --location "$LOCATION" --output none
fi

if ! az acr show --name "$ACR_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  echo ">> Creating ACR $ACR_NAME (Basic SKU, admin disabled)"
  az acr create \
    --resource-group "$RG" \
    --name "$ACR_NAME" \
    --sku Basic \
    --admin-enabled false \
    --output none
fi

echo ">> Building diag image with az acr build"
az acr build \
  --registry "$ACR_NAME" \
  --image "$DIAG_IMAGE_TAG" \
  --file "${APP_DIR}/Dockerfile" \
  "$APP_DIR" \
  --output none

FULL_IMAGE="${ACR_NAME}.azurecr.io/${DIAG_IMAGE_TAG}"

DEPLOYMENT_NAME="rnslab-$(date -u +%Y%m%d%H%M%S)"
echo ">> Submitting Bicep deployment $DEPLOYMENT_NAME"
az deployment group create \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "${INFRA_DIR}/main.bicep" \
  --parameters "${INFRA_DIR}/main.parameters.json" \
  --parameters \
      baseName="$BASE_NAME" \
      expiryHours="$EXPIRY_HOURS" \
      diagImage="$FULL_IMAGE" \
      diagAcrName="$ACR_NAME" \
  --output none

echo ">> Deployment complete. Outputs:"
az deployment group show \
  --resource-group "$RG" \
  --name "$DEPLOYMENT_NAME" \
  --query 'properties.outputs' \
  --output json

cat <<EOF

Next steps:
  1. Verify the deployment is healthy:
       export RG="$RG"
       ./verify.sh

  2. Run the scale sequence + sampling:
       ./trigger.sh

  3. After analysis, clean up:
       ./cleanup.sh
EOF
