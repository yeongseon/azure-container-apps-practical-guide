#!/usr/bin/env bash
# Scenario C: Healthy baseline (control).
#   MODE=healthy.
#   Container starts immediately and stays stable. Expect a brief burst
#   of "no metrics returned" logs (~30-60s) during Kubernetes Metrics
#   Server warm-up, then no further errors. Use as a control to compare
#   log patterns with A and B.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-nometrics-healthy}"
IMAGE_TAG="${IMAGE_TAG:-nometrics:v1}"

LAB_DIR="labs/keda-no-metrics-returned"

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
    --set-env-vars "MODE=healthy"
else
  echo "[scenario-c] creating app ${APP_NAME} (healthy baseline)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 2 --max-replicas 10 \
    --ingress external --target-port 8000 \
    --scale-rule-name mem-rule --scale-rule-type memory \
    --scale-rule-metadata "type=Utilization" "value=50" \
    --env-vars "MODE=healthy"
fi

echo "[scenario-c] done. Healthy baseline — expect brief 'no metrics' logs during warm-up (~60s), then none."
echo "  Check system logs: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
