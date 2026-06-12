#!/usr/bin/env bash
# Perturbation harness for the startup-degraded-transient-failure lab (Stage B).
#
# Modes:
#   --preflight             Brief 100/200/400 RPS staircase against the
#                           subject app to prove 200 RPS consumes
#                           nontrivial headroom (Oracle binding #2).
#
#   --baseline              Single k6 run at TARGET_RPS for DURATION_SECONDS
#                           with NO perturbations. Establishes the
#                           steady-state 5xx baseline.
#
#   --perturbation          PRIMARY phase. Runs $EVENTS perturbation events
#                           every $INTERVAL seconds. Each event:
#                             1. Starts the perturbation-sampler Job (5s cadence
#                                for 600s) tagged with this event's PERTURBATION_ID.
#                             2. Triggers an ACA-managed new revision rollout
#                                by setting subject app env var ROLLOUT_GENERATION
#                                to a unique value (Oracle revision #2).
#                             3. Waits $INTERVAL seconds before the next event.
#                           A single long-running k6 loadgen Job is started ONCE
#                           before the first event and runs continuously across
#                           all events. The PERTURBATION_ID is reset between
#                           events by relabeling the loadgen execution log
#                           offline (KQL joins on bucket timestamp + event window).
#
#   --supplemental-restart  SUPPLEMENTAL phase (optional). Runs $EVENTS revision
#                           restart events for comparison vs. the primary
#                           rollout phase. Cap any conclusions about
#                           platform-initiated restart causes at
#                           [Strongly Suggested] (Oracle binding #1).
#
# Usage:
#   export RG="rg-aca-startup-degraded"
#   ./trigger.sh --preflight
#   ./trigger.sh --baseline --duration 1800
#   ./trigger.sh --perturbation --events 12 --interval 600
#   ./trigger.sh --supplemental-restart --events 3 --interval 600
#
# Optional overrides:
#   --app                   Subject app name (default: subject-app)
#   --loadgen-job           k6 loadgen Job name (default: loadgen-k6)
#   --sampler-job           Perturbation sampler Job name (default: perturbation-sampler)
#   --rps                   k6 target RPS (default: 200)
#   --duration              k6 duration in seconds (default: 1800)

set -euo pipefail

RG="${RG:?RG must be set, e.g. rg-aca-startup-degraded}"
SUBJECT_APP="${SUBJECT_APP:-subject-app}"
LOADGEN_JOB="${LOADGEN_JOB:-loadgen-k6}"
SAMPLER_JOB="${SAMPLER_JOB:-perturbation-sampler}"
TARGET_RPS="${TARGET_RPS:-200}"
DURATION_SECONDS="${DURATION_SECONDS:-1800}"
EVENTS="${EVENTS:-12}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-600}"
MODE=""

usage() {
  grep '^# ' "$0" | sed 's/^# \?//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preflight) MODE="preflight"; shift ;;
    --baseline) MODE="baseline"; shift ;;
    --perturbation) MODE="perturbation"; shift ;;
    --supplemental-restart) MODE="supplemental-restart"; shift ;;
    --app) SUBJECT_APP="$2"; shift 2 ;;
    --loadgen-job) LOADGEN_JOB="$2"; shift 2 ;;
    --sampler-job) SAMPLER_JOB="$2"; shift 2 ;;
    --rps) TARGET_RPS="$2"; shift 2 ;;
    --duration) DURATION_SECONDS="$2"; shift 2 ;;
    --events) EVENTS="$2"; shift 2 ;;
    --interval) INTERVAL_SECONDS="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$MODE" ]] || { echo "ERROR: must specify --preflight | --baseline | --perturbation | --supplemental-restart" >&2; usage; }

SUBJECT_FQDN=$(az containerapp show \
  --resource-group "$RG" --name "$SUBJECT_APP" \
  --query 'properties.configuration.ingress.fqdn' --output tsv)
SUBJECT_URL="https://${SUBJECT_FQDN}/"

echo ">> Mode: $MODE"
echo "   RG: $RG"
echo "   Subject FQDN: $SUBJECT_FQDN"
echo "   Subject URL : $SUBJECT_URL"
echo "   Target RPS  : $TARGET_RPS"
echo "   Duration    : $DURATION_SECONDS sec"

start_loadgen_job() {
  local run_id="$1"
  local perturbation_id="$2"
  local duration_s="$3"

  echo ">>>> Starting $LOADGEN_JOB (run_id=$run_id, perturbation_id=$perturbation_id, duration=${duration_s}s)"
  az containerapp job start \
    --resource-group "$RG" \
    --name "$LOADGEN_JOB" \
    --env-vars \
      "SUBJECT_URL=${SUBJECT_URL}" \
      "TARGET_RPS=${TARGET_RPS}" \
      "DURATION_SECONDS=${duration_s}" \
      "PERTURBATION_ID=${perturbation_id}" \
      "RUN_ID=${run_id}" \
      "K6_NO_USAGE_REPORT=true" \
    --output json \
    | jq --compact-output '{name: .name, status: .properties.status, start: .properties.startTime}'
}

start_sampler_job() {
  local perturbation_id="$1"
  local sample_duration_s="${2:-600}"

  echo ">>>> Starting $SAMPLER_JOB (perturbation_id=$perturbation_id, duration=${sample_duration_s}s)"
  az containerapp job start \
    --resource-group "$RG" \
    --name "$SAMPLER_JOB" \
    --env-vars \
      "PERTURBATION_ID=${perturbation_id}" \
      "SAMPLE_INTERVAL_SECONDS=5" \
      "SAMPLE_DURATION_SECONDS=${sample_duration_s}" \
    --output json \
    | jq --compact-output '{name: .name, status: .properties.status, start: .properties.startTime}'
}

trigger_rollout() {
  local perturbation_id="$1"
  local rollout_generation
  rollout_generation="$(date -u +%s)-${perturbation_id}"

  echo ">>>> Triggering rollout (ROLLOUT_GENERATION=$rollout_generation) on $SUBJECT_APP"
  az containerapp update \
    --resource-group "$RG" \
    --name "$SUBJECT_APP" \
    --set-env-vars "ROLLOUT_GENERATION=${rollout_generation}" \
    --output none

  local active_revisions
  active_revisions=$(az containerapp revision list \
    --resource-group "$RG" --name "$SUBJECT_APP" \
    --query 'length([?properties.active])' --output tsv)
  echo ">>>> Active revisions after rollout: $active_revisions"
}

trigger_revision_restart() {
  local rev
  rev=$(az containerapp revision list \
    --resource-group "$RG" --name "$SUBJECT_APP" \
    --query '[?properties.active]|[0].name' --output tsv)
  echo ">>>> Restarting active revision: $rev"
  az containerapp revision restart \
    --resource-group "$RG" --name "$SUBJECT_APP" \
    --revision "$rev" --output none
}

case "$MODE" in
  preflight)
    echo ">>>> Preflight calibration: 100/200/400 RPS staircase, 60s each"
    for rps in 100 200 400; do
      start_loadgen_job "preflight-${rps}rps" "none" 60
      echo "    Waiting 90s before next staircase step..."
      sleep 90
    done
    echo ">>>> Preflight done. Query ContainerAppConsoleLogs_CL for kind=bucket lines tagged run_id=preflight-*"
    ;;

  baseline)
    start_loadgen_job "baseline-$(date -u +%Y%m%d%H%M%S)" "none" "$DURATION_SECONDS"
    echo ">>>> Baseline k6 run launched. Wait $DURATION_SECONDS seconds for completion."
    ;;

  perturbation)
    RUN_ID="perturbation-$(date -u +%Y%m%d%H%M%S)"
    TOTAL_DURATION=$(( EVENTS * INTERVAL_SECONDS + 60 ))
    echo ">>>> Starting continuous loadgen for ${TOTAL_DURATION}s spanning $EVENTS events"
    start_loadgen_job "$RUN_ID" "spans-all-events" "$TOTAL_DURATION"

    sleep 30

    for i in $(seq 1 "$EVENTS"); do
      PERT_ID="rollout-event-${i}"
      echo
      echo ">>>> ==== Event $i/$EVENTS: $PERT_ID ===="
      start_sampler_job "$PERT_ID" 600
      sleep 10
      trigger_rollout "$PERT_ID"

      if [[ $i -lt $EVENTS ]]; then
        echo ">>>> Waiting $INTERVAL_SECONDS seconds before next event..."
        sleep "$INTERVAL_SECONDS"
      fi
    done

    echo
    echo ">>>> Perturbation phase complete. RUN_ID=$RUN_ID"
    echo ">>>> k6 loadgen will continue for ~60s past the last event, then exit cleanly."
    ;;

  supplemental-restart)
    RUN_ID="supplemental-restart-$(date -u +%Y%m%d%H%M%S)"
    TOTAL_DURATION=$(( EVENTS * INTERVAL_SECONDS + 60 ))
    echo ">>>> Starting continuous loadgen for ${TOTAL_DURATION}s spanning $EVENTS restart events"
    start_loadgen_job "$RUN_ID" "spans-all-restart-events" "$TOTAL_DURATION"

    sleep 30

    for i in $(seq 1 "$EVENTS"); do
      PERT_ID="restart-event-${i}"
      echo
      echo ">>>> ==== Restart event $i/$EVENTS: $PERT_ID ===="
      start_sampler_job "$PERT_ID" 600
      sleep 10
      trigger_revision_restart

      if [[ $i -lt $EVENTS ]]; then
        echo ">>>> Waiting $INTERVAL_SECONDS seconds before next restart..."
        sleep "$INTERVAL_SECONDS"
      fi
    done

    echo
    echo ">>>> Supplemental restart phase complete. RUN_ID=$RUN_ID"
    echo ">>>> NOTE: Cap conclusions about platform-initiated restart causes at [Strongly Suggested] (Oracle binding #1)."
    ;;
esac
