#!/usr/bin/env bash
# Verify script: collect ALL available evidence for "no metrics returned" reproduction.
# Outputs a structured report per app. Run once per scenario to avoid duplicate queries.
#
# Usage: APP_NAME=ca-nometrics-slow bash verify.sh
#        APP_NAME=ca-nometrics-crash LOOKBACK=PT1H bash verify.sh
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${APP_NAME:?APP_NAME must be set}"

LOOKBACK="${LOOKBACK:-PT30M}"
OUTDIR="${OUTDIR:-labs/keda-no-metrics-returned/evidence}"
APP_DIR="${OUTDIR}/${APP_NAME}"
mkdir -p "$APP_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${APP_DIR}/report-${TS}.txt"

tee_report() { tee -a "$REPORT"; }

{
echo "========================================================"
echo "KEDA No-Metrics-Returned Lab — Evidence Report"
echo "========================================================"
echo "App:       $APP_NAME"
echo "RG:        $RG"
echo "Lookback:  $LOOKBACK"
echo "Timestamp: $TS"
echo "========================================================"

# ---------------------------------------------------------------
# 1. App metadata
# ---------------------------------------------------------------
echo
echo "=== 1. App configuration ==="
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "{name:name, location:location, provisioningState:properties.provisioningState, revisionMode:properties.configuration.activeRevisionsMode, cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas, scaleRules:properties.template.scale.rules, envVars:properties.template.containers[0].env}" \
  --output json 2>/dev/null || echo "(failed to get app config)"

# ---------------------------------------------------------------
# 2. Active revision & replica status
# ---------------------------------------------------------------
echo
echo "=== 2. Active revision ==="
ACTIVE_REV="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query '[?properties.active]|[0].name' -o tsv 2>/dev/null)" || true
echo "Active revision: ${ACTIVE_REV:-<none>}"

if [[ -n "$ACTIVE_REV" ]]; then
  az containerapp revision show --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" \
    --query "{name:name, replicas:properties.replicas, active:properties.active, healthState:properties.healthState, provisioningState:properties.provisioningState, createdTime:properties.createdTime, runningState:properties.runningState}" \
    -o json
fi

echo
echo "=== 3. Replica list ==="
if [[ -n "$ACTIVE_REV" ]]; then
  az containerapp replica list \
    --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" \
    --output table 2>/dev/null || echo "(no replicas found)"
fi

# ---------------------------------------------------------------
# 4. Resolve Log Analytics workspace
# ---------------------------------------------------------------
echo
echo "=== 4. Log Analytics workspace ==="
ENV_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query 'properties.managedEnvironmentId' --output tsv 2>/dev/null)" || true
WORKSPACE_CUSTOMER_ID=""
WORKSPACE_ID=""

if [[ -n "$ENV_ID" ]]; then
  WORKSPACE_CUSTOMER_ID="$(az resource show --ids "$ENV_ID" \
    --query 'properties.appLogsConfiguration.logAnalyticsConfiguration.customerId' \
    --output tsv 2>/dev/null)" || true
fi

if [[ -n "$WORKSPACE_CUSTOMER_ID" ]]; then
  WORKSPACE_ID="$(az monitor log-analytics workspace list --resource-group "$RG" \
    --query "[?customerId=='${WORKSPACE_CUSTOMER_ID}'] | [0].id" --output tsv 2>/dev/null)" || true
fi
echo "Workspace ID: ${WORKSPACE_ID:-<not resolved>}"

# ---------------------------------------------------------------
# 5. System logs: "no metrics returned" / "invalid metrics" / "failed to get"
# ---------------------------------------------------------------
echo
echo "=== 5. System logs: metric errors ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  echo "(Log Analytics ingestion delay: 5-10 min)"
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('no metrics returned', 'invalid metrics', 'failed to get')
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 30
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
else
  echo "(skipped — workspace not resolved)"
fi

# ---------------------------------------------------------------
# 6. System logs: "no metrics" count per 5-min bin (for timeline chart)
# ---------------------------------------------------------------
echo
echo "=== 6. Metric error count timeline (5-min bins) ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('no metrics returned', 'invalid metrics', 'failed to get')
      | summarize ErrorCount=count() by bin(TimeGenerated, 5m)
      | order by TimeGenerated asc
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# ---------------------------------------------------------------
# 7. System logs: DEPRECATED / metricType warnings
# ---------------------------------------------------------------
echo
echo "=== 7. System logs: DEPRECATED warnings ==="
if [[ -n "$WORKSPACE_ID" ]]; then
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

# ---------------------------------------------------------------
# 8. System logs: ALL KEDA/scaler logs (broader view)
# ---------------------------------------------------------------
echo
echo "=== 8. System logs: all scaler-related logs (last 30) ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('keda', 'scaler', 'scale', 'hpa', 'metric', 'replica')
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 30
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# ---------------------------------------------------------------
# 9. System logs: container lifecycle events (start, stop, crash)
# ---------------------------------------------------------------
echo
echo "=== 9. System logs: container lifecycle events ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('started', 'stopped', 'killed', 'backoff', 'crash', 'OOM', 'unhealthy', 'probe', 'ready', 'pulling', 'pulled')
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 30
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# ---------------------------------------------------------------
# 10. Console logs (application stdout/stderr)
# ---------------------------------------------------------------
echo
echo "=== 10. Console logs (last 30 lines) ==="
az containerapp logs show \
  --name "$APP_NAME" --resource-group "$RG" \
  --type console --follow false --tail 30 \
  2>/dev/null || echo "(no console logs available)"

# ---------------------------------------------------------------
# 11. System logs (platform-level, last 30 lines)
# ---------------------------------------------------------------
echo
echo "=== 11. System logs via CLI (last 30 lines) ==="
az containerapp logs show \
  --name "$APP_NAME" --resource-group "$RG" \
  --type system --follow false --tail 30 \
  2>/dev/null || echo "(no system logs available or --type system not supported)"

# ---------------------------------------------------------------
# 12. Azure Monitor metrics
# ---------------------------------------------------------------
APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query id --output tsv 2>/dev/null)" || true

if [[ -n "$APP_ID" ]]; then
  echo
  echo "=== 12a. Replica count (Max) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "Replicas" \
    --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 12b. Restart count (Total) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "RestartCount" \
    --aggregation Total --interval PT5M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 12c. Memory Percentage (Avg) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "MemoryPercentage" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 12d. CPU Percentage (Avg) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "CpuPercentage" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 12e. Memory Working Set Bytes (Avg) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "WorkingSetBytes" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 12f. Request count (Total) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "Requests" \
    --aggregation Total --interval PT5M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true
fi

# ---------------------------------------------------------------
# 13. cgroup memory stats from live replica
# ---------------------------------------------------------------
echo
echo "=== 13. cgroup memory.stat from live replica ==="
if [[ -n "$ACTIVE_REV" ]]; then
  REPLICA="$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" --query '[0].name' -o tsv 2>/dev/null)" || true
  if [[ -n "$REPLICA" ]]; then
    echo "Replica: $REPLICA"
    az containerapp exec \
      --name "$APP_NAME" --resource-group "$RG" \
      --replica "$REPLICA" --container "$APP_NAME" \
      --command "/bin/sh -c 'echo --- memory.current ---; cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes; echo; echo --- memory.max ---; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes; echo; echo --- memory.stat (top 20 fields) ---; (cat /sys/fs/cgroup/memory.stat 2>/dev/null || cat /sys/fs/cgroup/memory/memory.stat) | head -20'" \
      2>&1 || echo "(exec failed — replica may be initializing or crash-looping)"
  else
    echo "(no replica found — container may be restarting)"
  fi
fi

# ---------------------------------------------------------------
# 14. Activity log (deployment / scale events)
# ---------------------------------------------------------------
echo
echo "=== 14. Activity log (resource group, last 1h) ==="
az monitor activity-log list \
  --resource-group "$RG" \
  --offset 1h \
  --query "[?contains(resourceId, '${APP_NAME}')] | [0:10].{time:eventTimestamp, operation:operationName.value, status:status.value, message:properties.statusMessage}" \
  --output table 2>/dev/null || echo "(no activity log entries)"

echo
echo "========================================================"
echo "Evidence collection complete for $APP_NAME"
echo "Report saved to: $REPORT"
echo "========================================================"
echo
echo "Portal screenshots to capture manually:"
echo "  1. Metrics blade → MemoryPercentage (Avg) split by Replica"
echo "  2. Metrics blade → Replicas (Max)"
echo "  3. Metrics blade → RestartCount (Total)"
echo "  4. Log stream → System logs (filter: 'no metrics returned')"
echo "  5. Revisions blade → Revision health state and replica count"
echo
echo "Save screenshots to: ${APP_DIR}/"
echo "  Naming convention:"
echo "    ${APP_NAME}-metrics-memory-percentage.png"
echo "    ${APP_NAME}-metrics-replica-count.png"
echo "    ${APP_NAME}-metrics-restart-count.png"
echo "    ${APP_NAME}-system-logs-no-metrics.png"
echo "    ${APP_NAME}-revisions-health.png"

} 2>&1 | tee_report

echo
echo "Full report: $REPORT"
