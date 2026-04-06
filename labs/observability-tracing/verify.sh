#!/bin/bash
set -e

SECRET_REF=$(az containerapp show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query "properties.template.containers[0].env[?name=='APPLICATIONINSIGHTS_CONNECTION_STRING'].secretRef | [0]" \
  --output tsv)

if [ "$SECRET_REF" = "appinsights-connection-string" ]; then
  echo "PASS: Application Insights connection string is configured on $APP_NAME."
else
  echo "FAIL: Application Insights connection string is missing or misconfigured on $APP_NAME."
  exit 1
fi

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" \
  --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" \
  --query customerId \
  --output tsv)

TRACE_COUNT=$(az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "union isfuzzy=true AppTraces, traces | where TimeGenerated > ago(15m) | summarize TraceCount=count()" \
  --query "tables[0].rows[0][0]" \
  --output tsv)

if [ -n "$TRACE_COUNT" ] && [ "$TRACE_COUNT" -gt 0 ]; then
  echo "PASS: Found $TRACE_COUNT trace record(s) in Log Analytics."
else
  echo "FAIL: No trace records found in Log Analytics."
  exit 1
fi

echo "Verification complete."
