#!/usr/bin/env bash
set -euo pipefail

: "${AZ_SUBSCRIPTION:?AZ_SUBSCRIPTION must be set (Azure subscription ID)}"
: "${RG:?RG must be set}"
: "${APP_NAME:?APP_NAME must be set}"
: "${APP_INSIGHTS_NAME:?APP_INSIGHTS_NAME must be set}"

EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

echo "==> Reading App Insights connection string from the deployed resource..."
APPLICATIONINSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --query "connectionString" \
  --output tsv)

if [ -z "$APPLICATIONINSIGHTS_CONNECTION_STRING" ]; then
  echo "FAIL: Could not read App Insights connection string from resource $APP_INSIGHTS_NAME"
  exit 1
fi

echo "    connection string resolved (value redacted in this output)"

echo ""
echo "==> [APPLY FIX] Adding APPLICATIONINSIGHTS_CONNECTION_STRING to the Container App env vars..."
az containerapp update \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=${APPLICATIONINSIGHTS_CONNECTION_STRING}" \
  --output none

echo ""
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
echo "==> [AFTER FIX] Container App env state (expect APPLICATIONINSIGHTS_CONNECTION_STRING name present, value redacted):"
az containerapp show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "{containerName:properties.template.containers[0].name, image:properties.template.containers[0].image, envNames:properties.template.containers[0].env[].name}" \
  --output json \
  | tee "$EVIDENCE_DIR/07-env-after-fix.json"

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
echo "==> Generating 20 fresh requests against https://${APP_FQDN}/ (these will return HTTP 200 AND emit telemetry to App Insights)..."
for i in {1..20}; do
  STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "https://${APP_FQDN}/")
  printf "  request %02d → HTTP %s\n" "$i" "$STATUS"
  sleep 0.5
done

echo ""
echo "==> Recording traffic-completed timestamp (UTC)..."
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$EVIDENCE_DIR/08-traffic-completed-after-fix.txt"

echo ""
echo "==> Waiting 240 seconds for App Insights ingestion latency before querying..."
sleep 240

echo ""
echo "==> [AFTER FIX] Querying App Insights 'requests' table (expect > 0 rows — Flask auto-instrumentation now wired):"
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'requests | where timestamp > ago(15m) | summarize requestCount=count() by cloud_RoleName' \
  --output json \
  | tee "$EVIDENCE_DIR/09-ai-requests-after-fix.json"

echo ""
echo "==> [AFTER FIX] Querying App Insights 'traces' table (expect > 0 rows — logger_name routes app logs):"
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'traces | where timestamp > ago(15m) | summarize traceCount=count() by cloud_RoleName' \
  --output json \
  | tee "$EVIDENCE_DIR/10-ai-traces-after-fix.json"

echo ""
echo "==> Capturing Container App full config (after fix; APPLICATIONINSIGHTS_CONNECTION_STRING is stored under properties.template.containers[0].env)..."
az containerapp show \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output json \
  > "$EVIDENCE_DIR/11-containerapp-full-config-after-fix.json"

echo ""
echo "==> Capturing per-5m timeline of requests for the after-fix window..."
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'requests | where timestamp > ago(60m) | summarize requestCount=count() by cloud_RoleName, bin(timestamp, 5m) | order by timestamp asc' \
  --output json \
  > "$EVIDENCE_DIR/12-kql-requests-timeline.json"

echo ""
echo "==> [AFTER FIX] Capturing per-message AppTraces for trace signature evidence..."
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'traces | where timestamp > ago(15m) | project timestamp, message, severityLevel | order by timestamp asc | take 25' \
  --output json \
  > "$EVIDENCE_DIR/13-ai-traces-messages-after-fix.json"

echo ""
echo "==> Capturing full revision lifecycle (with computed hasConnStr flag)..."
az containerapp revision list \
  --subscription "$AZ_SUBSCRIPTION" \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --all \
  --output json | python3 -c "
import json, sys
revs = json.load(sys.stdin)
out = []
for r in revs:
    env = (r.get('properties', {}).get('template', {}).get('containers', [{}])[0].get('env') or [])
    has = any(e.get('name') == 'APPLICATIONINSIGHTS_CONNECTION_STRING' for e in env)
    out.append({
        'active': r.get('properties', {}).get('active'),
        'createdTime': r.get('properties', {}).get('createdTime'),
        'hasConnStr': has,
        'image': r.get('properties', {}).get('template', {}).get('containers', [{}])[0].get('image'),
        'name': r.get('name'),
    })
out.sort(key=lambda x: x['createdTime'] or '')
print(json.dumps(out, indent=2))
" > "$EVIDENCE_DIR/14-revisions-lifecycle.json"

echo ""
echo "==> [AFTER FIX] Capturing per-request AppRequests detail (timestamp, name, resultCode, success, duration, url)..."
az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'requests | where timestamp > ago(15m) | project timestamp, name, resultCode, success, duration, url | order by timestamp asc' \
  --output json \
  > "$EVIDENCE_DIR/15-ai-requests-detail-after-fix.json"

echo ""
echo "==> Recovery check:"
REQ_COUNT=$(az monitor app-insights query \
  --subscription "$AZ_SUBSCRIPTION" \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RG" \
  --analytics-query 'requests | where timestamp > ago(15m) | count' \
  --query "tables[0].rows[0][0]" \
  --output tsv 2>/dev/null || echo "0")
if [ "$REQ_COUNT" -gt 0 ] 2>/dev/null; then
  echo "PASS: After adding APPLICATIONINSIGHTS_CONNECTION_STRING, App Insights 'requests' table shows $REQ_COUNT rows."
else
  echo "WARN: 'requests' count is $REQ_COUNT. App Insights ingestion can take 2-5 minutes — re-run the query manually in a few minutes."
fi

echo ""
echo "Evidence written to $EVIDENCE_DIR/"
