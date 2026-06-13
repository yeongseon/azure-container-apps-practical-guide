#!/usr/bin/env bash
# Stage B KQL execution harness for startup-degraded-transient-failure lab.
#
# Runs the KQL queries from
# docs/troubleshooting/kql/scaling-and-replicas/startup-degraded-bucketed-5xx.md
# against the deployed Log Analytics workspace and persists each result as
# both a human-readable table and a machine-readable JSON file under
# labs/startup-degraded-transient-failure/evidence/.
#
# Usage:
#   ./run_kql_pack.sh q1 <run_id_pattern>           Per-run summary (err_pct, percentiles)
#   ./run_kql_pack.sh q2 <run_id_pattern>           10s bucket time series, sum-across-VUs
#   ./run_kql_pack.sh q3 <perturbation_id_pattern>  RevisionStateSample timeline (5s)
#   ./run_kql_pack.sh q4 <hours_back>               ReplicaInventorySample snapshot (audit)
#   ./run_kql_pack.sh q5 <run_id_pattern>           Falsification: 3+ consecutive bad buckets
#   ./run_kql_pack.sh q6                            Baseline vs Perturbation comparison
#   ./run_kql_pack.sh q7 <hours_back>               System events (rollouts) timeline
#   ./run_kql_pack.sh all <run_id_prefix>           q1+q2+q3+q4+q5+q6+q7
#
# Prereqs:
#   - source labs/startup-degraded-transient-failure/evidence/deploy-env.sh
#   - az account set --subscription "$SUBSCRIPTION_NAME"
#   - LAW customer ID either in env LAW_CUSTOMER_ID or in
#     evidence/.local/law-customer-id.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="$SCRIPT_DIR"
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)

# KQL_LOOKBACK_HOURS overrides the default 3h window used by q1/q2/q5/q7.
# Set this to a larger value (e.g. 18) when querying a run that ended more
# than 3 hours ago. q4 (audit cron) takes its own hours arg and is unaffected.
LOOKBACK_HOURS="${KQL_LOOKBACK_HOURS:-3}"

if [[ -z "${RG:-}" || -z "${LAW_NAME:-}" ]]; then
  source "${SCRIPT_DIR}/deploy-env.sh"
fi

if [[ -z "${LAW_CUSTOMER_ID:-}" ]]; then
  if [[ -f "${SCRIPT_DIR}/.local/law-customer-id.txt" ]]; then
    LAW_CUSTOMER_ID=$(cat "${SCRIPT_DIR}/.local/law-customer-id.txt")
  else
    LAW_CUSTOMER_ID=$(az monitor log-analytics workspace show \
      --resource-group "$RG" --workspace-name "$LAW_NAME" \
      --query customerId --output tsv)
  fi
fi

if [[ -z "${LAW_CUSTOMER_ID:-}" ]]; then
  echo "ERROR: LAW_CUSTOMER_ID empty. Check RG=$RG LAW_NAME=$LAW_NAME exist." >&2
  exit 1
fi

echo "LAW customer ID: ${LAW_CUSTOMER_ID:0:8}..."
echo "Output dir:      $OUTDIR"
echo "Timestamp:       $TIMESTAMP"
echo ""

run_query() {
  local short="$1"
  local desc="$2"
  local q="$3"
  local table_out="${OUTDIR}/${short}-${desc}-${TIMESTAMP}.tsv"
  local json_out="${OUTDIR}/${short}-${desc}-${TIMESTAMP}.json"

  echo "=== ${short^^}: ${desc} ==="
  if az monitor log-analytics query \
      --workspace "$LAW_CUSTOMER_ID" \
      --analytics-query "$q" \
      --output tsv 2>&1 | tee "$table_out"; then
    echo "Saved TSV:  $table_out"
  else
    echo "WARN: ${short} TSV render failed; check $table_out"
  fi

  if az monitor log-analytics query \
      --workspace "$LAW_CUSTOMER_ID" \
      --analytics-query "$q" \
      --output json > "$json_out" 2>&1; then
    echo "Saved JSON: $json_out"
  else
    echo "WARN: ${short} JSON capture failed; check $json_out"
  fi
  echo ""
}

q1() {
  local run_pattern="${1:?usage: q1 <run_id_pattern>}"
  local q
  q=$(cat <<KQL
ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "k6"
| where Log_s has "${run_pattern}"
| extend body_raw = extract(@'msg="(.+)" source=console', 1, Log_s)
| where isnotempty(body_raw)
| extend body = replace_string(body_raw, @'\\"', '"')
| extend payload = parse_json(body)
| extend event_kind = tostring(payload.kind)
| extend run_id = tostring(payload.run_id)
| extend dur_ms = todouble(payload.dur_ms)
| extend ok = tobool(payload.ok)
| where event_kind == "req"
| summarize
    requests = count(),
    ok_count = countif(ok),
    err_count = countif(not(ok)),
    p50_ms = round(percentile(dur_ms, 50), 1),
    p95_ms = round(percentile(dur_ms, 95), 1),
    p99_ms = round(percentile(dur_ms, 99), 1),
    max_ms = round(max(dur_ms), 1)
  by run_id
| extend err_pct = round(100.0 * err_count / requests, 3)
| project run_id, requests, ok_count, err_count, err_pct, p50_ms, p95_ms, p99_ms, max_ms
| order by run_id asc
KQL
)
  run_query "q1" "per-run-summary" "$q"
}

q2() {
  local run_pattern="${1:?usage: q2 <run_id_pattern>}"
  local q
  q=$(cat <<KQL
let req = ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "k6"
| where Log_s has "${run_pattern}"
| extend body_raw = extract(@'msg="(.+)" source=console', 1, Log_s)
| where isnotempty(body_raw)
| extend body = replace_string(body_raw, @'\\"', '"')
| extend payload = parse_json(body)
| extend event_kind = tostring(payload.kind)
| extend run_id = tostring(payload.run_id)
| extend client_ts = todatetime(payload.ts)
| extend dur_ms = todouble(payload.dur_ms)
| where event_kind == "req"
| extend bucket_iso = bin(client_ts, 10s)
| summarize p50_ms = round(percentile(dur_ms, 50), 1),
            p95_ms = round(percentile(dur_ms, 95), 1),
            p99_ms = round(percentile(dur_ms, 99), 1)
        by run_id, bucket_iso;
ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "k6"
| where Log_s has "${run_pattern}"
| extend body_raw = extract(@'msg="(.+)" source=console', 1, Log_s)
| where isnotempty(body_raw)
| extend body = replace_string(body_raw, @'\\"', '"')
| extend payload = parse_json(body)
| extend event_kind = tostring(payload.kind)
| where event_kind == "bucket"
| extend run_id = tostring(payload.run_id)
| extend bucket_iso = todatetime(payload.bucket_start_iso)
| extend count_ = toint(payload.count)
| extend ok_ = toint(payload.ok)
| extend err_ = toint(payload.err)
| summarize total_count = sum(count_), total_ok = sum(ok_), total_err = sum(err_) by run_id, bucket_iso
| extend err_pct = round(100.0 * total_err / total_count, 3)
| join kind=leftouter (req) on run_id, bucket_iso
| project run_id, bucket_iso, total_count, total_ok, total_err, err_pct, p50_ms, p95_ms, p99_ms
| order by run_id asc, bucket_iso asc
KQL
)
  run_query "q2" "buckets-10s-sum-vus" "$q"
}

q3() {
  local perturb_pattern="${1:?usage: q3 <perturbation_id_pattern>}"
  local q
  q=$(cat <<KQL
ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "sampler"
| extend payload = parse_json(Log_s)
| extend event_kind = tostring(payload.kind)
| extend perturbation_id = tostring(payload.perturbation_id)
| where perturbation_id startswith "${perturb_pattern}"
| extend app = tostring(payload.app)
| extend revision = tostring(payload.revision)
| extend active = tobool(payload.active)
| extend replicas = toint(payload.replicas)
| extend traffic_weight = toint(payload.traffic_weight)
| extend provisioning_state = tostring(payload.provisioning_state)
| extend client_ts = todatetime(payload.ts)
| where event_kind in ("RevisionStateSample", "PerturbationWindowMarker")
| project client_ts, perturbation_id, event_kind, app, revision, active, replicas, traffic_weight, provisioning_state
| order by perturbation_id asc, client_ts asc
KQL
)
  run_query "q3" "revision-state-timeline" "$q"
}

q4() {
  local hours_back="${1:-24}"
  local q
  q=$(cat <<KQL
ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${hours_back}h)
| where ContainerName_s == "audit"
| extend payload = parse_json(Log_s)
| extend event_kind = tostring(payload.kind)
| where event_kind == "ReplicaInventorySample"
| extend app = tostring(payload.app)
| extend revision = tostring(payload.revision)
| extend replica = tostring(payload.replica)
| extend running_state = tostring(payload.running_state)
| extend client_ts = todatetime(payload.ts)
| summarize sample_count = count(),
            running_count = countif(running_state == "Running"),
            unique_replicas = dcount(replica),
            unique_revisions = dcount(revision),
            first_sample = min(client_ts),
            last_sample = max(client_ts)
        by app
| extend running_pct = round(100.0 * running_count / sample_count, 2)
| order by app asc
KQL
)
  run_query "q4" "replica-inventory-snapshot" "$q"
}

q5() {
  local run_pattern="${1:?usage: q5 <run_id_pattern>}"
  local q
  q=$(cat <<KQL
let buckets = ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "k6"
| where Log_s has "${run_pattern}"
| extend body_raw = extract(@'msg="(.+)" source=console', 1, Log_s)
| where isnotempty(body_raw)
| extend body = replace_string(body_raw, @'\\"', '"')
| extend payload = parse_json(body)
| extend event_kind = tostring(payload.kind)
| where event_kind == "bucket"
| extend run_id = tostring(payload.run_id)
| extend bucket_iso = todatetime(payload.bucket_start_iso)
| extend count_ = toint(payload.count)
| extend err_ = toint(payload.err)
| summarize total_count = sum(count_), total_err = sum(err_) by run_id, bucket_iso
| extend err_pct = round(100.0 * total_err / total_count, 3)
| extend bad_bucket = iff(err_pct > 0.5, 1, 0)
| order by run_id asc, bucket_iso asc;
buckets
| serialize
| extend prev1_bad = prev(bad_bucket, 1), prev2_bad = prev(bad_bucket, 2),
         prev1_run = prev(run_id, 1), prev2_run = prev(run_id, 2)
| extend is_3_window_end = (bad_bucket == 1 and prev1_bad == 1 and prev2_bad == 1
                            and run_id == prev1_run and run_id == prev2_run)
| where is_3_window_end
| summarize falsification_windows = count(),
            first_window_end = min(bucket_iso),
            last_window_end = max(bucket_iso)
        by run_id
| extend falsified = (falsification_windows > 0)
| project run_id, falsified, falsification_windows, first_window_end, last_window_end
KQL
)
  run_query "q5" "falsification-3-consecutive-bad-buckets" "$q"
}

q6() {
  local q
  q=$(cat <<KQL
let allBuckets = ContainerAppConsoleLogs_CL
| where TimeGenerated >= ago(${LOOKBACK_HOURS}h)
| where ContainerName_s == "k6"
| extend body_raw = extract(@'msg="(.+)" source=console', 1, Log_s)
| where isnotempty(body_raw)
| extend body = replace_string(body_raw, @'\"', '"')
| extend payload = parse_json(body)
| extend event_kind = tostring(payload.kind)
| where event_kind == "bucket"
| extend run_id = tostring(payload.run_id)
| extend bucket_iso = todatetime(payload.bucket_start_iso)
| extend count_ = toint(payload.count)
| extend ok_ = toint(payload.ok)
| extend err_ = toint(payload.err)
| summarize total_count = sum(count_), total_ok = sum(ok_), total_err = sum(err_) by run_id, bucket_iso
| extend err_pct = round(100.0 * total_err / total_count, 3);
allBuckets
| extend phase = case(
    run_id startswith "baseline-", "baseline",
    run_id startswith "perturbation-", "perturbation",
    run_id startswith "supplemental-", "supplemental-restart",
    "other")
| summarize buckets = count(),
            total_requests = sum(total_count),
            total_errors = sum(total_err),
            worst_bucket_err_pct = round(max(err_pct), 3),
            buckets_above_0p5pct = countif(err_pct > 0.5)
        by phase
| extend overall_err_pct = round(100.0 * total_errors / total_requests, 4)
| order by phase asc
KQL
)
  run_query "q6" "baseline-vs-perturb-vs-supplemental" "$q"
}

q7() {
  local hours_back="${1:-3}"
  local q
  q=$(cat <<KQL
ContainerAppSystemLogs_CL
| where TimeGenerated >= ago(${hours_back}h)
| where ContainerAppName_s == "subject-app"
| where Reason_s in ("ContainerTerminated", "ContainerStarted", "AssigningReplica",
                     "RevisionReady", "FailedScalingUp", "ContainerCreating")
| project TimeGenerated, RevisionName_s, ReplicaName_s, Reason_s, Log_s
| order by TimeGenerated asc
KQL
)
  run_query "q7" "system-events-timeline" "$q"
}

case "${1:-help}" in
  q1) q1 "${2:?run_id pattern required}" ;;
  q2) q2 "${2:?run_id pattern required}" ;;
  q3) q3 "${2:?perturbation_id pattern required (e.g. rollout-event-, restart-event-)}" ;;
  q4) q4 "${2:-24}" ;;
  q5) q5 "${2:?run_id pattern required}" ;;
  q6) q6 ;;
  q7) q7 "${2:-3}" ;;
  all)
    pattern="${2:?run_id pattern prefix required (e.g. baseline-, perturbation-, supplemental-restart-)}"
    # Derive perturbation_id pattern from run_id prefix so q3 can run as part
    # of `all`. trigger.sh tags perturbation events as rollout-event-N for the
    # perturbation phase and restart-event-N for the supplemental-restart phase;
    # baseline runs have no per-event perturbation_id and skip q3.
    case "$pattern" in
      perturbation-*) perturb_pattern="rollout-event-" ;;
      supplemental-restart-*) perturb_pattern="restart-event-" ;;
      *) perturb_pattern="" ;;
    esac
    q1 "$pattern"
    q2 "$pattern"
    if [[ -n "$perturb_pattern" ]]; then
      q3 "$perturb_pattern"
    else
      echo "=== Q3: SKIPPED (no perturbation_id mapping for run_id prefix '$pattern') ==="
      echo ""
    fi
    q5 "$pattern"
    q4 24
    q6
    q7 "$LOOKBACK_HOURS"
    ;;
  help|*) sed -n '1,30p' "$0"; exit 0 ;;
esac
