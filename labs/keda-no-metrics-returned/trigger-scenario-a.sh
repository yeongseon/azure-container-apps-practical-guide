#!/usr/bin/env bash
# Scenario A: Slow startup (readiness probe fails → metrics gap).
#   MODE=slow-start, DELAY_SECONDS=120.
#   Container takes 2 minutes to start serving. During this window the
#   replica is Not Ready, and the Kubernetes Metrics Server returns no
#   data → "no metrics returned from resource metrics API".
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-nometrics-slow}"
IMAGE_TAG="${IMAGE_TAG:-nometrics:v1}"
DELAY_SECONDS="${DELAY_SECONDS:-120}"

LAB_DIR="labs/keda-no-metrics-returned"

echo "[scenario-a] building ${IMAGE_TAG} in ACR ${ACR_NAME}"
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
  echo "[scenario-a] updating existing app ${APP_NAME}"
  az containerapp update \
    --name "$APP_NAME" --resource-group "$RG" \
    --image "$FULL_IMAGE" \
    --set-env-vars "MODE=slow-start" "DELAY_SECONDS=${DELAY_SECONDS}"
else
  echo "[scenario-a] creating app ${APP_NAME} (slow-start, ${DELAY_SECONDS}s delay)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 1 --max-replicas 10 \
    --ingress external --target-port 8000 \
    --scale-rule-name mem-rule --scale-rule-type memory \
    --scale-rule-metadata "type=Utilization" "value=50" \
    --env-vars "MODE=slow-start" "DELAY_SECONDS=${DELAY_SECONDS}"
fi

echo "[scenario-a] done. Container will be Not Ready for ${DELAY_SECONDS}s."
echo "  Check system logs: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
