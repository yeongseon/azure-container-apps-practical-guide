#!/usr/bin/env bash
# Scenario B: CrashLoopBackOff (repeated exits → recurring metrics gaps).
#   MODE=crash-loop, DELAY_SECONDS=30.
#   Container starts, runs 30s, then exits. Kubernetes restarts it with
#   exponential backoff. Each restart cycle creates a window where the
#   Metrics Server has no data → "no metrics returned" + "invalid metrics".
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-nometrics-crash}"
IMAGE_TAG="${IMAGE_TAG:-nometrics:v1}"
DELAY_SECONDS="${DELAY_SECONDS:-30}"

LAB_DIR="labs/keda-no-metrics-returned"

echo "[scenario-b] building ${IMAGE_TAG} in ACR ${ACR_NAME}"
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
  echo "[scenario-b] updating existing app ${APP_NAME}"
  az containerapp update \
    --name "$APP_NAME" --resource-group "$RG" \
    --image "$FULL_IMAGE" \
    --set-env-vars "MODE=crash-loop" "DELAY_SECONDS=${DELAY_SECONDS}"
else
  echo "[scenario-b] creating app ${APP_NAME} (crash-loop, exits every ${DELAY_SECONDS}s)"
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
    --env-vars "MODE=crash-loop" "DELAY_SECONDS=${DELAY_SECONDS}"
fi

echo "[scenario-b] done. Container will crash every ${DELAY_SECONDS}s."
echo "  Check system logs: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
