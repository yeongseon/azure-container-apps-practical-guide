#!/usr/bin/env bash
# Scenario B: Gradual memory leak.
#   MODE=leak, LEAK_MB_PER_TICK=30, LEAK_INTERVAL_SECONDS=20, memory 0.5Gi.
#   The container starts cleanly, serves requests, then accumulates 30 MiB
#   every 20 seconds in a background thread. Around the 12-15th tick (~6 min)
#   the resident set crosses the cgroup ceiling and the OOM killer fires.
#   This mimics a slow production memory leak: minutes of healthy operation
#   followed by a single OOMKill, then CrashLoopBackOff once the leak repeats.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-oom-leak}"
IMAGE_TAG="${IMAGE_TAG:-memleak:v1}"
LEAK_MB_PER_TICK="${LEAK_MB_PER_TICK:-30}"
LEAK_INTERVAL_SECONDS="${LEAK_INTERVAL_SECONDS:-20}"

LAB_DIR="labs/memory-leak-oomkilled"

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
    --cpu 0.25 --memory 0.5Gi \
    --set-env-vars "MODE=leak" \
      "LEAK_MB_PER_TICK=${LEAK_MB_PER_TICK}" \
      "LEAK_INTERVAL_SECONDS=${LEAK_INTERVAL_SECONDS}"
else
  echo "[scenario-b] creating app ${APP_NAME} (gradual leak, ${LEAK_MB_PER_TICK} MiB / ${LEAK_INTERVAL_SECONDS}s, 0.5Gi limit)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas 1 --max-replicas 1 \
    --ingress external --target-port 8000 \
    --env-vars "MODE=leak" \
      "LEAK_MB_PER_TICK=${LEAK_MB_PER_TICK}" \
      "LEAK_INTERVAL_SECONDS=${LEAK_INTERVAL_SECONDS}"
fi

echo "[scenario-b] done. Expect first OOM around minute 5-7 of replica uptime."
echo "  Verify: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
