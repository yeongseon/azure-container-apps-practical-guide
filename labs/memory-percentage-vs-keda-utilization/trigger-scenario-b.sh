#!/usr/bin/env bash
# Scenario B: Just-above threshold.
#   MODE=rss, TARGET_MB=560 (~55% of 1024Mi memory limit).
#   KEDA computes ceil(2 * 55 / 50) = ceil(2.2) = 3 and scales out by one.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-mempct-b-above}"
IMAGE_TAG="${IMAGE_TAG:-mempct-rss:v1}"
TARGET_MB="${TARGET_MB:-560}"

echo "[scenario-b] building ${IMAGE_TAG} in ACR ${ACR_NAME}"
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_TAG" \
  --file labs/memory-percentage-vs-keda-utilization/workload/Dockerfile \
  labs/memory-percentage-vs-keda-utilization/workload

ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)"
FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_TAG}"
ACR_USERNAME="$(az acr credential show --name "$ACR_NAME" --query username --output tsv)"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' --output tsv)"

if az containerapp show --name "$APP_NAME" --resource-group "$RG" --output none 2>/dev/null; then
  echo "[scenario-b] updating existing app ${APP_NAME} to ${FULL_IMAGE}"
  az containerapp update \
    --name "$APP_NAME" --resource-group "$RG" \
    --image "$FULL_IMAGE" \
    --set-env-vars "MODE=rss" "TARGET_MB=${TARGET_MB}"
else
  echo "[scenario-b] creating app ${APP_NAME} (just-above: rss, ${TARGET_MB}MB)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 2 --max-replicas 20 \
    --ingress external --target-port 8000 \
    --scale-rule-name memory-rule --scale-rule-type memory \
    --scale-rule-metadata "type=Utilization" "value=50" \
    --env-vars "MODE=rss" "TARGET_MB=${TARGET_MB}"
fi

echo "[scenario-b] done. Wait ~15 min, then APP_NAME=${APP_NAME} bash verify.sh"
