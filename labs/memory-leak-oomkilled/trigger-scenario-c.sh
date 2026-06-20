#!/usr/bin/env bash
# Scenario C: Healthy control.
#   MODE=healthy, memory 1.0Gi (double the failing scenarios).
#   Same image as A and B. No leak path is started. Container serves /health
#   and /info indefinitely at baseline RSS (~30-50 MiB). Used as a control
#   to confirm that the OOMs in A and B are caused by the workload, not by
#   the image, the environment, the network, or the platform.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-oom-healthy}"
IMAGE_TAG="${IMAGE_TAG:-memleak:v1}"

LAB_DIR="labs/memory-leak-oomkilled"

echo "[scenario-c] building ${IMAGE_TAG} in ACR ${ACR_NAME}"
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_TAG" \
  --file "${LAB_DIR}/workload/Dockerfile" \
  "${LAB_DIR}/workload"

ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_TAG}"
ACR_USERNAME="$(az acr credential show --name "$ACR_NAME" --query username --output tsv)"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' --output tsv)"

if az containerapp show --name "$APP_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  echo "[scenario-c] updating existing app ${APP_NAME}"
  az containerapp update \
    --name "$APP_NAME" --resource-group "$RG" \
    --image "$FULL_IMAGE" \
    --cpu 0.5 --memory 1.0Gi \
    --set-env-vars "MODE=healthy"
else
  echo "[scenario-c] creating app ${APP_NAME} (healthy control, 1.0Gi limit)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 1 --max-replicas 1 \
    --ingress external --target-port 8000 \
    --env-vars "MODE=healthy"
fi

echo "[scenario-c] done. Expect stable baseline, RestartCount=0, HealthState=Healthy."
echo "  Verify: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
