#!/usr/bin/env bash
# Fix: Apply the documented remediation to Scenario A.
#   1. Switch MODE from hard-oom to healthy (removes the allocation path).
#   2. Raise memory ceiling from 0.5Gi to 1.0Gi (gives headroom even if the
#      workload changes again).
#   This produces a new revision. The OLD failing revision is retained for
#   evidence collection (Revisions blade still shows it as Unhealthy).
set -euo pipefail

: "${RG:?RG (resource group) must be set}"

APP_NAME="${APP_NAME:-ca-oom-hard}"

echo "[fix] applying fix to ${APP_NAME}: MODE=healthy, memory=1.0Gi"
az containerapp update \
  --name "$APP_NAME" --resource-group "$RG" \
  --cpu 0.5 --memory 1.0Gi \
  --set-env-vars "MODE=healthy"

echo "[fix] done. New revision should reach HealthState=Healthy within ~60s."
echo "  Verify: APP_NAME=${APP_NAME} bash labs/memory-leak-oomkilled/verify.sh"
