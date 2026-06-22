#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (Azure subscription ID)}"
: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
: "${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER must be set (e.g. acrappiconnXXXXXX.azurecr.io)}"
: "${IMAGE_TAG:?IMAGE_TAG must be set (e.g. hellotelemetry:v3)}"
: "${APP_INSIGHTS_NAME:?APP_INSIGHTS_NAME must be set}"

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

echo "==> Switching Container App to the instrumented Python image WITHOUT APPLICATIONINSIGHTS_CONNECTION_STRING..."
# --remove-env-vars ensures the new revision starts with NO connection string,
# even if a previous run of verify.sh left it set on the current revision.
# The CLI tolerates --remove-env-vars when the var is already absent (no-op).
az containerapp update \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_TAG}" \
  --remove-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING \
  --output none

echo "==> Waiting up to 3 minutes for the new revision to become Healthy..."
for i in {1..18}; do
  LATEST_NAME=$(az containerapp show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.latestRevisionName" \
    --output tsv)
  STATE=$(az containerapp revision show \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "$LATEST_NAME" \
    --query "properties.provisioningState" \
    --output tsv 2>/dev/null || echo "Unknown")
  REPLICA_STATE=$(az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "$LATEST_NAME" \
    --query "[0].properties.runningState" \
    --output tsv 2>/dev/null || echo "Unknown")
  CONTAINER_STATE=$(az containerapp replica list \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "$LATEST_NAME" \
    --query "[0].properties.containers[0].runningState" \
    --output tsv 2>/dev/null || echo "Unknown")
  printf "  [%02d/18] revision=%s provisioningState=%s replica=%s container=%s\n" \
    "$i" "$LATEST_NAME" "$STATE" "$REPLICA_STATE" "$CONTAINER_STATE"
  if [ "$STATE" = "Provisioned" ] && [ "$CONTAINER_STATE" = "Running" ]; then
    break
  fi
  sleep 10
done

echo ""
echo "==> [BEFORE FIX] Container App env state (expect env=null — APPLICATIONINSIGHTS_CONNECTION_STRING absent):"
az containerapp show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{containerName:properties.template.containers[0].name, image:properties.template.containers[0].image, env:properties.template.containers[0].env}" \
  --output json \
  | tee "$EVIDENCE_DIR/01-env-before-fix.json"

echo ""
echo "==> Resolving Container App FQDN..."
APP_FQDN=$(az containerapp show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)
echo "    FQDN: $APP_FQDN"

echo ""
echo "==> Generating 20 requests against https://${APP_FQDN}/ (these will return HTTP 200 but emit NO telemetry because the SDK guard skipped configure_azure_monitor())..."
for i in {1..20}; do
  STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "https://${APP_FQDN}/")
  printf "  request %02d → HTTP %s\n" "$i" "$STATUS"
  sleep 0.5
done

echo ""
echo "==> Recording traffic-completed timestamp (UTC)..."
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$EVIDENCE_DIR/02-traffic-completed-before-fix.txt"

echo ""
echo "==> Waiting 240 seconds for App Insights ingestion latency before querying..."
sleep 240

echo ""
echo "==> [BEFORE FIX] Querying App Insights 'requests' table (expect 0 rows — SDK never wired):"
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'requests | where timestamp > ago(15m) | summarize requestCount=count() by cloud_RoleName' \
  --output json \
  | tee "$EVIDENCE_DIR/03-ai-requests-before-fix.json"

echo ""
echo "==> [BEFORE FIX] Querying App Insights 'traces' table (expect 0 rows):"
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'traces | where timestamp > ago(15m) | summarize traceCount=count() by cloud_RoleName' \
  --output json \
  | tee "$EVIDENCE_DIR/04-ai-traces-before-fix.json"

echo ""
echo "==> Capturing Container App full config (before fix)..."
az containerapp show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json \
  > "$EVIDENCE_DIR/05-containerapp-full-config-before-fix.json"

echo ""
echo "==> Capturing environment-level telemetry config (expect 'not configured' — this lab uses the SDK path, not the env-level OTel agent):"
az containerapp env telemetry app-insights show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$(az containerapp env list --subscription "$AZ_SUBSCRIPTION" --resource-group "$RG" --query '[0].name' --output tsv)" \
  --resource-group "$RG" \
  --output json \
  > "$EVIDENCE_DIR/06-env-telemetry-config.json" \
  2>&1 || echo "(env-level telemetry not configured — expected for this lab)" >> "$EVIDENCE_DIR/06-env-telemetry-config.json"

echo ""
echo "==> Run verify.sh to apply the fix (add APPLICATIONINSIGHTS_CONNECTION_STRING) and re-query telemetry."
