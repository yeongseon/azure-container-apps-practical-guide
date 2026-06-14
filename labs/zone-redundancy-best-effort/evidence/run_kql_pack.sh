#!/usr/bin/env bash
# Phase 4 KQL execution harness for zone-redundancy-best-effort lab.
#
# Runs the KQL queries from
# docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md
# against the deployed Log Analytics workspace and persists each result as
# both a human-readable table and a machine-readable JSON file under
# labs/zone-redundancy-best-effort/evidence/.
#
# Usage:
#   ./run_kql_pack.sh q1              # baseline ingestion check (run BEFORE Phase 3)
#   ./run_kql_pack.sh q1b             # error sample drill-down (only if q1 shows errors)
#   ./run_kql_pack.sh phase4-window   # q1 + q2 + q3 + q4 + q7 (run AFTER Phase 3, window-based)
#   ./run_kql_pack.sh q6              # Q6 baseline vs perturbation (requires Phase 3 logs)
#   ./run_kql_pack.sh all             # phase4-window + q6
#
# Prereqs:
#   - source labs/zone-redundancy-best-effort/evidence/deploy-env.sh
#   - az account set --subscription "$SUBSCRIPTION_NAME"
#   - Phase 3 perturbation logs in evidence/perturbation-variant-*.log (for q6)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="$SCRIPT_DIR"
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)

# --- Env recovery ---
if [[ -z "${RG:-}" || -z "${LAW_NAME:-}" ]]; then
  # shellcheck source=deploy-env.sh
  source "${SCRIPT_DIR}/deploy-env.sh"
fi

if [[ -z "${LAW_CUSTOMER_ID:-}" ]]; then
  LAW_CUSTOMER_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RG" --workspace-name "$LAW_NAME" \
    --query customerId --output tsv)
fi

if [[ -z "${LAW_CUSTOMER_ID:-}" ]]; then
  echo "ERROR: LAW_CUSTOMER_ID is empty. Check that RG=$RG and LAW_NAME=$LAW_NAME exist." >&2
  exit 1
fi

echo "LAW customer ID: ${LAW_CUSTOMER_ID:0:8}..."
echo "Output dir:      $OUTDIR"
echo "Timestamp:       $TIMESTAMP"
echo ""

# --- Helper: run one query and persist table + JSON ---
run_query() {
  local short="$1"
  local desc="$2"
  local q="$3"
  local table_out="${OUTDIR}/${short}-${desc}-${TIMESTAMP}.table.txt"
  local json_out="${OUTDIR}/${short}-${desc}-${TIMESTAMP}.json"

  echo "=== ${short^^}: ${desc} ==="
  if az monitor log-analytics query \
      --workspace "$LAW_CUSTOMER_ID" \
      --analytics-query "$q" \
      --output table 2>&1 | tee "$table_out"; then
    echo "Saved table: $table_out"
  else
    echo "WARN: ${short} table render failed; check $table_out"
  fi

  if az monitor log-analytics query \
      --workspace "$LAW_CUSTOMER_ID" \
      --analytics-query "$q" \
      --output json > "$json_out" 2>&1; then
    echo "Saved JSON:  $json_out"
  else
    echo "WARN: ${short} JSON capture failed; check $json_out"
  fi
  echo ""
}

# --- Query definitions (verbatim from KQL pack, Window expanded to 24h) ---

read -r -d '' Q1 <<'KQL' || true
let LookbackHours = 24h;
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(LookbackHours)
| extend JobNameVal = coalesce(column_ifexists("ContainerJobName_s", ""), column_ifexists("JobName_s", ""))
| where JobNameVal == "audit-sampler"
| extend parsed = parse_json(Log_s)
| where tostring(parsed.event) == "ReplicaInventorySample"
| extend resolutionStatus = tostring(parsed.resolutionStatus),
         app = tostring(parsed.app)
| summarize TotalSamples = count(),
            OkSamples = countif(resolutionStatus == "ok"),
            ErrorSamples = countif(resolutionStatus != "ok"),
            UniqueApps = dcount(app),
            FirstSample = min(TimeGenerated),
            LastSample = max(TimeGenerated)
| extend ExpectedOkSamples = (LookbackHours / 5m) * UniqueApps
| extend HealthRatio = round(todouble(OkSamples) / todouble(ExpectedOkSamples), 2)
KQL

read -r -d '' Q1B <<'KQL' || true
let LookbackHours = 24h;
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(LookbackHours)
| extend JobNameVal = coalesce(column_ifexists("ContainerJobName_s", ""), column_ifexists("JobName_s", ""))
| where JobNameVal == "audit-sampler"
| extend parsed = parse_json(Log_s)
| where tostring(parsed.event) == "ReplicaInventorySample"
| extend resolutionStatus = tostring(parsed.resolutionStatus),
         resolutionDetail = tostring(parsed.resolutionDetail),
         app = tostring(parsed.app)
| where resolutionStatus != "ok"
| summarize ErrorCount = count(),
            FirstError = min(TimeGenerated),
            LastError = max(TimeGenerated),
            SampleDetail = any(resolutionDetail)
            by app, resolutionStatus
| order by app asc, resolutionStatus asc
KQL

read -r -d '' Q2 <<'KQL' || true
let Window = 24h;
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(Window)
| extend JobNameVal = coalesce(column_ifexists("ContainerJobName_s", ""), column_ifexists("JobName_s", ""))
| where JobNameVal == "audit-sampler"
| extend parsed = parse_json(Log_s)
| where tostring(parsed.event) == "ReplicaInventorySample"
| where tostring(parsed.resolutionStatus) == "ok"
| extend app = tostring(parsed.app),
         observed = toint(parsed.observedReplicaCount),
         configured = toint(parsed.configuredMinReplicas)
| summarize Samples = count(),
            ObservedMin = min(observed),
            ObservedMax = max(observed),
            ObservedAvg = round(avg(observed), 2),
            ConfiguredMin = max(configured)
            by app
| extend SteadyStateOK = (ObservedMin == ConfiguredMin and ObservedMax == ConfiguredMin)
| order by app asc
KQL

read -r -d '' Q3 <<'KQL' || true
let Window = 24h;
let ClusterSecs = 60;
let ReplicaEvents =
    ContainerAppSystemLogs_CL
    | where TimeGenerated > ago(Window)
    | where ContainerAppName_s in ("app-min2", "app-min3", "app-min6")
    | where Reason_s in ("ContainerTerminated", "ContainerStarted", "AssigningReplica")
    | project TimeGenerated, ContainerAppName_s, RevisionName_s, ReplicaName_s, Reason_s;
ReplicaEvents
| where Reason_s == "ContainerTerminated"
| extend BinEnd = TimeGenerated + (ClusterSecs * 1s)
| summarize TerminatedReplicas = dcount(ReplicaName_s),
            ReplicaList = make_set(ReplicaName_s)
            by ContainerAppName_s, bin(TimeGenerated, ClusterSecs * 1s)
| where TerminatedReplicas >= 2
| project ClusterStart = TimeGenerated,
          App = ContainerAppName_s,
          TerminatedReplicas,
          ReplicaList
| order by ClusterStart desc, App asc
KQL

read -r -d '' Q4 <<'KQL' || true
let Window = 24h;
let ClusterSecs = 60;
let RecoveryDeadlineSecs = 600;
let Churns =
    ContainerAppSystemLogs_CL
    | where TimeGenerated > ago(Window)
    | where ContainerAppName_s in ("app-min2", "app-min3", "app-min6")
    | where Reason_s == "ContainerTerminated"
    | summarize TerminatedReplicas = dcount(ReplicaName_s)
              by ContainerAppName_s, bin(TimeGenerated, ClusterSecs * 1s)
    | where TerminatedReplicas >= 2
    | project ChurnStart = TimeGenerated, App = ContainerAppName_s;
let Recoveries =
    ContainerAppConsoleLogs_CL
    | where TimeGenerated > ago(Window)
    | extend JobNameVal = coalesce(column_ifexists("ContainerJobName_s", ""), column_ifexists("JobName_s", ""))
    | where JobNameVal == "audit-sampler"
    | extend parsed = parse_json(Log_s)
    | where tostring(parsed.event) == "ReplicaInventorySample"
    | where tostring(parsed.resolutionStatus) == "ok"
    | extend App = tostring(parsed.app),
             observed = toint(parsed.observedReplicaCount),
             configured = toint(parsed.configuredMinReplicas)
    | where observed >= configured
    | project RecoverySample = TimeGenerated, App, observed, configured;
Churns
| join kind=leftouter Recoveries on App
| where RecoverySample > ChurnStart
| summarize FirstRecoveryAt = min(RecoverySample) by ChurnStart, App
| extend RecoverySecs = datetime_diff('second', FirstRecoveryAt, ChurnStart)
| extend WithinDeadline = (RecoverySecs <= RecoveryDeadlineSecs)
| order by ChurnStart desc
KQL

read -r -d '' Q7 <<'KQL' || true
let Window = 24h;
let ClusterSecs = 60;
let ChurnEvents =
    ContainerAppSystemLogs_CL
    | where TimeGenerated > ago(Window)
    | where ContainerAppName_s in ("app-min2", "app-min3", "app-min6")
    | where Reason_s == "ContainerTerminated"
    | summarize TerminatedReplicas = dcount(ReplicaName_s)
              by ContainerAppName_s, bin(TimeGenerated, ClusterSecs * 1s)
    | where TerminatedReplicas >= 2
    | summarize ClusteredChurnEvents = count(),
                MaxTerminatedInOneEvent = max(TerminatedReplicas),
                AvgTerminatedPerEvent = round(avg(TerminatedReplicas), 2)
                by ContainerAppName_s;
let MinConfig = datatable(App: string, ConfiguredMin: int)
[
  "app-min2", 2,
  "app-min3", 3,
  "app-min6", 6,
];
MinConfig
| join kind=leftouter ChurnEvents on $left.App == $right.ContainerAppName_s
| project App,
          ConfiguredMin,
          ClusteredChurnEvents = coalesce(ClusteredChurnEvents, 0),
          MaxTerminatedInOneEvent = coalesce(MaxTerminatedInOneEvent, 0),
          AvgTerminatedPerEvent = coalesce(AvgTerminatedPerEvent, 0.0)
| extend MaxReplacementFraction = round(todouble(MaxTerminatedInOneEvent) / todouble(ConfiguredMin), 2)
| order by ConfiguredMin asc
KQL

# --- Q6 builder: parse Phase 3 perturbation logs for PerturbationSubmitted timestamps ---
# Each trigger.sh run emits a JSON line `{"event":"PerturbationSubmitted","timestamp":"...","app":"...",...}`.
# We extract those to populate Q6's `PerturbWindows` datatable dynamically.
build_q6_perturb_table() {
  local rows=()
  for log in "${OUTDIR}"/perturbation-variant-*.log; do
    [[ -f "$log" ]] || continue
    # Match JSON event lines, extract timestamp + app
    while IFS= read -r line; do
      local ts app
      ts=$(echo "$line" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' | sed 's/\..*Z$/Z/')
      app=$(echo "$line" | sed -n 's/.*"app":"\([^"]*\)".*/\1/p')
      if [[ -n "$ts" && -n "$app" ]]; then
        # Convert ISO to KQL datetime(YYYY-MM-DDTHH:MM:SSZ) form
        rows+=("  datetime(${ts}), \"${app}\",")
      fi
    done < <(grep -h 'PerturbationSubmitted' "$log" 2>/dev/null || true)
  done

  if [[ ${#rows[@]} -eq 0 ]]; then
    echo "ERROR: No PerturbationSubmitted events found in evidence/perturbation-variant-*.log" >&2
    echo "       Run Phase 3 perturbations first." >&2
    return 1
  fi

  # Emit the datatable rows (last row keeps trailing comma; that's syntactically valid in KQL)
  printf '%s\n' "${rows[@]}"
}

q6() {
  local table_rows
  table_rows=$(build_q6_perturb_table) || return 1

  local q
  q=$(cat <<KQL
let Window = 24h;
let PerturbPad = 10m;
let ClusterSecs = 60;
let PerturbWindows = datatable(PerturbStart: datetime, App: string)
[
${table_rows}
];
let AllChurns =
    ContainerAppSystemLogs_CL
    | where TimeGenerated > ago(Window)
    | where ContainerAppName_s in ("app-min2", "app-min3", "app-min6")
    | where Reason_s == "ContainerTerminated"
    | summarize TerminatedReplicas = dcount(ReplicaName_s)
              by ContainerAppName_s, bin(TimeGenerated, ClusterSecs * 1s)
    | where TerminatedReplicas >= 2
    | project ChurnTime = TimeGenerated, App = ContainerAppName_s, TerminatedReplicas;
let PerturbedChurns =
    AllChurns
    | join kind=inner PerturbWindows on App
    | where ChurnTime between ((PerturbStart - PerturbPad) .. (PerturbStart + PerturbPad))
    | project ChurnTime, App, TerminatedReplicas;
let BaselineChurns =
    AllChurns
    | join kind=leftanti PerturbedChurns on ChurnTime, App;
union
    (BaselineChurns | summarize ChurnEvents = count(), Bucket = "Baseline (no perturb)" by App),
    (PerturbedChurns | summarize ChurnEvents = count(), Bucket = "Perturbation window" by App)
| extend WindowMinutes = case(Bucket == "Baseline (no perturb)",
                              ((Window / 1m) - (toscalar(PerturbWindows | count) * (PerturbPad / 1m * 2))),
                              toscalar(PerturbWindows | count) * (PerturbPad / 1m * 2))
| extend ChurnPerHour = round(todouble(ChurnEvents) / (WindowMinutes / 60.0), 3)
| order by App asc, Bucket asc
KQL
)

  run_query "q6" "baseline-vs-perturb" "$q"
}

# --- Dispatch ---
case "${1:-help}" in
  q1)             run_query "q1"  "ingestion-check"        "$Q1" ;;
  q1b)            run_query "q1b" "error-sample-breakdown" "$Q1B" ;;
  q2)             run_query "q2"  "per-app-baseline"       "$Q2" ;;
  q3)             run_query "q3"  "clustered-churn"        "$Q3" ;;
  q4)             run_query "q4"  "recovery-duration"      "$Q4" ;;
  q7)             run_query "q7"  "multi-app-comparison"   "$Q7" ;;
  q6)             q6 ;;
  phase4-window)
    run_query "q1" "ingestion-check"      "$Q1"
    run_query "q2" "per-app-baseline"     "$Q2"
    run_query "q3" "clustered-churn"      "$Q3"
    run_query "q4" "recovery-duration"    "$Q4"
    run_query "q7" "multi-app-comparison" "$Q7"
    ;;
  all)
    run_query "q1" "ingestion-check"      "$Q1"
    run_query "q2" "per-app-baseline"     "$Q2"
    run_query "q3" "clustered-churn"      "$Q3"
    run_query "q4" "recovery-duration"    "$Q4"
    run_query "q7" "multi-app-comparison" "$Q7"
    q6
    ;;
  help|*)
    sed -n '1,28p' "$0"
    exit 0
    ;;
esac
