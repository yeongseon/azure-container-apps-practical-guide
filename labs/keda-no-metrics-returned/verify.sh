#!/usr/bin/env bash
# Verify script: check system logs for "no metrics returned" and related errors.
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${APP_NAME:?APP_NAME must be set}"

LOOKBACK="${LOOKBACK:-PT30M}"

echo "==============================================="
echo "App: $APP_NAME"
echo "Lookback: $LOOKBACK"
echo "==============================================="

# --- 1. System logs: KEDA / HPA metric errors ---
echo
echo "--- System logs: 'no metrics returned' / 'invalid metrics' / 'failed to get' ---"
LOG_ANALYTICS_WS="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query 'properties.managedEnvironmentId' --output tsv | xargs -I{} \
  az resource show --ids {} --query 'properties.appLogsConfiguration.logAnalyticsConfiguration.customerId' --output tsv 2>/dev/null)" || true

if [[ -n "$LOG_ANALYTICS_WS" ]]; then
  WORKSPACE_ID="$(az monitor log-analytics workspace list --resource-group "$RG" \
    --query "[?customerId=='${LOG_ANALYTICS_WS}'] | [0].id" --output tsv 2>/dev/null)" || true

  if [[ -n "$WORKSPACE_ID" ]]; then
    echo "(querying Log Analytics — results may have 5-10 min ingestion delay)"
    az monitor log-analytics query \
      --workspace "$WORKSPACE_ID" \
      --analytics-query "
        ContainerAppSystemLogs_CL
        | where ContainerAppName_s == '${APP_NAME}'
        | where Log_s has_any ('no metrics returned', 'invalid metrics', 'failed to get')
        | project TimeGenerated, Log_s
        | order by TimeGenerated desc
        | take 20
      " \
      --output table 2>/dev/null || echo "(query failed or no results yet)"
  else
    echo "(could not resolve Log Analytics workspace ID)"
  fi
else
  echo "(could not resolve Log Analytics workspace — trying console logs)"
fi

# --- 2. System logs: KEDA deprecation warnings ---
echo
echo "--- System logs: 'DEPRECATED' / 'metricType' warnings ---"
if [[ -n "${WORKSPACE_ID:-}" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('DEPRECATED', 'metricType')
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 10
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# --- 3. Console logs: app startup / crash messages ---
echo
echo "--- Console logs (last 20 lines) ---"
az containerapp logs show \
  --name "$APP_NAME" --resource-group "$RG" \
  --type console --follow false --tail 20 \
  2>/dev/null || echo "(no console logs available)"

# --- 4. Replica status ---
echo
echo "--- Active revision and replica count ---"
ACTIVE_REV="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query '[?properties.active]|[0].name' -o tsv 2>/dev/null)" || true

if [[ -n "$ACTIVE_REV" ]]; then
  az containerapp revision show --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" \
    --query "{name:name, replicas:properties.replicas, active:properties.active, health:properties.healthState, provisioningState:properties.provisioningState}" \
    -o table
else
  echo "(no active revision found)"
fi

# --- 5. Replica list with running state ---
echo
echo "--- Replica list ---"
if [[ -n "$ACTIVE_REV" ]]; then
  az containerapp replica list \
    --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" \
    --output table 2>/dev/null || echo "(no replicas found)"
fi

# --- 6. Azure Monitor metrics ---
APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query id --output tsv 2>/dev/null)" || true

if [[ -n "$APP_ID" ]]; then
  echo
  echo "--- Replica count (Max) over lookback ---"
  az monitor metrics list \
    --resource "$APP_ID" --metric "Replicas" \
    --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "--- Restart count over lookback ---"
  az monitor metrics list \
    --resource "$APP_ID" --metric "RestartCount" \
    --aggregation Total --interval PT5M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true
fi

echo
echo "==============================================="
echo "Verification complete for $APP_NAME"
echo "==============================================="
echo
echo "What to look for:"
echo "  - Scenario A (slow-start): 'no metrics returned' logs during the first ${DELAY_SECONDS:-120}s"
echo "  - Scenario B (crash-loop): recurring 'no metrics returned' + 'invalid metrics' every crash cycle"
echo "  - Scenario C (healthy):    no metric error logs (control baseline)"
echo "  - All scenarios:           'DEPRECATED' warnings if 'type=Utilization' metadata is used"
