#!/usr/bin/env bash
# Scenario A: Hard OOM at startup.
#   MODE=hard-oom, HARD_OOM_MB=600, memory limit 0.5Gi.
#   The container allocates 600 MiB before serving its first HTTP request.
#   The cgroup memory ceiling (~512 MiB) is breached during the allocation
#   loop. The kernel OOM killer sends SIGKILL. The platform records exit
#   code 137 + ContainerTerminated/ProcessExited and restarts the replica.
#   CrashLoopBackOff follows because every restart repeats the same alloc.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME (Container Apps environment) must be set}"

APP_NAME="${APP_NAME:-ca-oom-hard}"
IMAGE_TAG="${IMAGE_TAG:-memleak:v1}"
HARD_OOM_MB="${HARD_OOM_MB:-600}"

LAB_DIR="labs/memory-leak-oomkilled"

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
    --cpu 0.25 --memory 0.5Gi \
    --set-env-vars "MODE=hard-oom" "HARD_OOM_MB=${HARD_OOM_MB}"
else
  echo "[scenario-a] creating app ${APP_NAME} (hard OOM, ${HARD_OOM_MB} MiB alloc, 0.5Gi limit)"
  az containerapp create \
    --name "$APP_NAME" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas 1 --max-replicas 1 \
    --env-vars "MODE=hard-oom" "HARD_OOM_MB=${HARD_OOM_MB}"
fi

echo "[scenario-a] done. Expect exit code 137 + ContainerTerminated within ~30s."
echo "  Verify: APP_NAME=${APP_NAME} bash ${LAB_DIR}/verify.sh"
