#!/usr/bin/env bash
# Verify script: collect ALL available evidence for "memory-leak-oomkilled" reproduction.
# Outputs a structured report per app. Run once per scenario to avoid duplicate queries.
#
# Usage: RG=rg-aca-memleak-lab APP_NAME=ca-oom-hard bash verify.sh
#        RG=rg-aca-memleak-lab APP_NAME=ca-oom-leak LOOKBACK=PT1H bash verify.sh
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${APP_NAME:?APP_NAME must be set}"

LOOKBACK="${LOOKBACK:-PT30M}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${OUTDIR:-${SCRIPT_DIR}/evidence}"
APP_DIR="${OUTDIR}/${APP_NAME}"
mkdir -p "$APP_DIR"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${APP_DIR}/report-${TS}.txt"

tee_report() { tee -a "$REPORT"; }

# Pre-resolve values that the SUMMARY heredoc needs (variables set inside the
# `{ ... } 2>&1 | tee_report` pipe live in a subshell and would be unbound here).
CONTAINER_NAME="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query 'properties.template.containers[0].name' -o tsv 2>/dev/null)" || true
CONTAINER_NAME="${CONTAINER_NAME:-$APP_NAME}"
ACTIVE_REVS="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query '[?properties.active].name' -o tsv 2>/dev/null)" || true

{
echo "========================================================"
echo "Memory Leak OOMKilled Lab — Evidence Report"
echo "========================================================"
echo "App:       $APP_NAME"
echo "RG:        $RG"
echo "Lookback:  $LOOKBACK"
echo "Timestamp: $TS"
echo "========================================================"

# Tool versions
echo
echo "=== 0. Tool versions ==="
az version --output json 2>/dev/null | tee "${APP_DIR}/az-version-${TS}.json" || echo "(az version unavailable)"
az extension show --name containerapp --query "{name:name, version:version}" -o json 2>/dev/null | tee "${APP_DIR}/containerapp-extension-${TS}.json" || echo "(containerapp extension not found)"

# App metadata
echo
echo "=== 1. App configuration ==="
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "{name:name, location:location, provisioningState:properties.provisioningState, revisionMode:properties.configuration.activeRevisionsMode, cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas, envVars:properties.template.containers[0].env}" \
  --output json 2>/dev/null || echo "(failed to get app config)"

echo
echo "=== 1b. Container name ==="
CONTAINER_NAME="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query 'properties.template.containers[0].name' -o tsv 2>/dev/null)" || true
CONTAINER_NAME="${CONTAINER_NAME:-$APP_NAME}"
echo "Container name: $CONTAINER_NAME"

# Revisions
echo
echo "=== 2. Active revision(s) ==="
ACTIVE_REVS="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query '[?properties.active].name' -o tsv 2>/dev/null)" || true
ACTIVE_REV="$(echo "$ACTIVE_REVS" | head -1)"
echo "Active revisions: ${ACTIVE_REVS:-<none>}"

REVISIONS_JSON="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query '[].{name:name, replicas:properties.replicas, active:properties.active, trafficWeight:properties.trafficWeight, healthState:properties.healthState, provisioningState:properties.provisioningState, runningState:properties.runningState, createdTime:properties.createdTime}' \
  -o json 2>/dev/null)" || true
if [[ -n "$REVISIONS_JSON" && "$REVISIONS_JSON" != "null" ]]; then
  echo "$REVISIONS_JSON" > "${APP_DIR}/revisions-${TS}.json"
  echo "$REVISIONS_JSON"
fi

# Replicas
echo
echo "=== 3. Replica list (all active revisions) ==="
while IFS= read -r REV; do
  [[ -z "$REV" ]] && continue
  echo "--- Replicas for revision: $REV ---"
  az containerapp replica list \
    --name "$APP_NAME" --resource-group "$RG" \
    --revision "$REV" \
    --output table 2>/dev/null || echo "(no replicas for $REV)"
done <<< "$ACTIVE_REVS"

# Log Analytics workspace resolution
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
  WORKSPACE_ID="$WORKSPACE_CUSTOMER_ID"
fi
echo "Workspace ID (customerId): ${WORKSPACE_ID:-<not resolved>}"

# System logs: exit code 137 / OOM / ContainerTerminated
echo
echo "=== 5. System logs: exit code 137 / OOM / ProcessExited / ContainerTerminated ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  echo "(Log Analytics ingestion delay: 5-10 min)"
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('exit code', 'ProcessExited', 'ContainerTerminated', 'OOM', 'OOMKill', 'memory', '137', 'SIGKILL')
      | project TimeGenerated, Reason_s, Log_s
      | order by TimeGenerated desc
      | take 50
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
else
  echo "(skipped — workspace not resolved)"
fi

# Count of exit-137 / OOM events per 5-min bin
echo
echo "=== 6. OOM event count timeline (5-min bins) ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('exit code', 'ProcessExited', 'ContainerTerminated', 'OOM', '137', 'SIGKILL')
      | summarize EventCount=count() by bin(TimeGenerated, 5m)
      | order by TimeGenerated asc
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# Console logs (application stdout)
echo
echo "=== 7. Console logs (last 50 lines) ==="
az containerapp logs show \
  --name "$APP_NAME" --resource-group "$RG" \
  --type console --follow false --tail 50 \
  2>/dev/null || echo "(no console logs available)"

# Console logs via Log Analytics (history beyond live tail)
echo
echo "=== 8. Console logs from Log Analytics (last 50) ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 50
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# Lifecycle events
echo
echo "=== 9. System logs: lifecycle events ==="
if [[ -n "$WORKSPACE_ID" ]]; then
  az monitor log-analytics query \
    --workspace "$WORKSPACE_ID" \
    --analytics-query "
      ContainerAppSystemLogs_CL
      | where ContainerAppName_s == '${APP_NAME}'
      | where Log_s has_any ('started', 'stopped', 'killed', 'backoff', 'crash', 'unhealthy', 'probe', 'ready', 'pulling', 'pulled', 'starting')
      | project TimeGenerated, Log_s
      | order by TimeGenerated desc
      | take 30
    " \
    --output table 2>/dev/null || echo "(query failed or no results yet)"
fi

# Azure Monitor metrics
APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query id --output tsv 2>/dev/null)" || true

if [[ -n "$APP_ID" ]]; then
  echo
  echo "=== 10a. Memory Percentage (Avg, PT1M) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "MemoryPercentage" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 10b. Memory Working Set Bytes (Avg, PT1M) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "WorkingSetBytes" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 10c. Restart count (Total, PT5M) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "RestartCount" \
    --aggregation Total --interval PT5M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 10d. Replica count (Max, PT1M) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "Replicas" \
    --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true

  echo
  echo "=== 10e. CPU Percentage (Avg, PT1M) ==="
  az monitor metrics list \
    --resource "$APP_ID" --metric "CpuPercentage" \
    --aggregation Average --interval PT1M --offset "$LOOKBACK" \
    --output table 2>/dev/null || true
fi

# cgroup memory stats (only if replica is alive)
echo
echo "=== 11. cgroup memory.stat from live replica (best effort) ==="
if [[ -n "$ACTIVE_REV" ]]; then
  REPLICA="$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" \
    --revision "$ACTIVE_REV" --query '[0].name' -o tsv 2>/dev/null)" || true
  if [[ -n "$REPLICA" ]]; then
    echo "Replica: $REPLICA"
    # `az containerapp exec` requires an interactive TTY on both stdin and
    # stdout. Because this script writes its report through `{ ... } 2>&1 |
    # tee_report`, stdout is always a pipe inside this block — so the TTY
    # check below will always be false during normal `bash verify.sh` runs.
    # That is intentional: when `exec` is called without a TTY the Azure CLI
    # emits a Python traceback (with local site-packages paths) into the
    # report, which is the PII leak path the AGENTS PII rules forbid. To
    # actually collect cgroup stats, run the printed command manually in an
    # interactive terminal.
    if [[ -t 0 && -t 1 ]]; then
      az containerapp exec \
        --name "$APP_NAME" --resource-group "$RG" \
        --replica "$REPLICA" --container "$CONTAINER_NAME" \
        --command "/bin/sh -c 'echo --- memory.current ---; cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes; echo; echo --- memory.max ---; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes; echo; echo --- memory.stat (top 20 fields) ---; (cat /sys/fs/cgroup/memory.stat 2>/dev/null || cat /sys/fs/cgroup/memory/memory.stat) | head -20'" \
        2>&1 || echo "(exec failed — replica may be crash-looping or not exec-capable)"
    else
      echo "(skipped: az containerapp exec requires an interactive TTY, and this script always pipes through tee for reporting)"
      echo "  To collect cgroup memory stats, run this command manually in an interactive terminal:"
      echo "    az containerapp exec --name $APP_NAME --resource-group $RG --replica $REPLICA --container $CONTAINER_NAME --command \"/bin/sh\""
      echo "  Then inside the replica shell:"
      echo "    cat /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.max"
    fi
  else
    echo "(no replica found — container may be restarting)"
  fi
fi

# Activity log
echo
echo "=== 12. Activity log (resource group, last 1h) ==="
az monitor activity-log list \
  --resource-group "$RG" \
  --offset 1h \
  --query "[?contains(resourceId, '${APP_NAME}')] | [0:10].{time:eventTimestamp, operation:operationName.value, status:status.value, message:properties.statusMessage}" \
  --output table 2>/dev/null || echo "(no activity log entries)"

echo
echo "========================================================"
echo "Evidence collection complete for $APP_NAME"
echo "Report saved to: labs/memory-leak-oomkilled/evidence/${APP_NAME}/report-${TS}.txt"
echo "========================================================"
echo
echo "Portal screenshots to capture manually for this scenario:"
echo "  1. Container App overview blade (ProvisioningState / Status)"
echo "  2. System logs blade (filter: exit code, OOM, ProcessExited)"
echo "  3. Console logs blade (allocation prints)"
echo "  4. Revisions blade (HealthState / RestartCount / running replicas)"
echo "  5. Metrics blade → MemoryPercentage"
echo "  6. Metrics blade → WorkingSetBytes"
echo "  7. Metrics blade → RestartCount"
echo
echo "Save screenshots to: docs/assets/troubleshooting/memory-leak-oomkilled/"

} 2>&1 | tee_report

LOCATION="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query location -o tsv 2>/dev/null)" || true
SUMMARY="${APP_DIR}/summary-${TS}.md"
cat > "$SUMMARY" <<MDEOF
# Evidence Summary: ${APP_NAME}

| Field | Value |
|-------|-------|
| App | ${APP_NAME} |
| Container | ${CONTAINER_NAME} |
| Resource Group | ${RG} |
| Region | ${LOCATION:-unknown} |
| Timestamp | ${TS} |
| Active Revisions | $(echo "${ACTIVE_REVS:-none}" | tr '\n' ', ' | sed 's/, $//') |
| Lookback | ${LOOKBACK} |

## Collected files

- \`report-${TS}.txt\` — Full evidence report
- \`az-version-${TS}.json\` — Azure CLI version
- \`containerapp-extension-${TS}.json\` — containerapp extension version
- \`revisions-${TS}.json\` — Revision details

## Next steps

- [ ] Capture Portal screenshots (listed in report)
- [ ] Correlate OOM event timestamps with MemoryPercentage spikes
- [ ] Confirm exit code 137 in system logs
MDEOF

echo
echo "Full report: labs/memory-leak-oomkilled/evidence/${APP_NAME}/report-${TS}.txt"
echo "Summary: labs/memory-leak-oomkilled/evidence/${APP_NAME}/summary-${TS}.md"
