#!/usr/bin/env bash
# trigger.sh — drive the full scale-sequence experiment.
#
# For each (profile, app) pair, walks through a scale ladder, waits for
# stability, and runs sample.sh. Top-scale step is repeated 3 times
# (Oracle mandate) to reach `[Strongly Suggested]` evidence level.
#
# Output: one JSONL file per profile under ./evidence/
#
# Required env:
#   RG          Resource group
#
# Optional env (defaults baked in):
#   CONSUMPTION_APP             default: ca-diag-consumption
#   DEDICATED_APP               default: ca-diag-dedicated
#   CONSUMPTION_LADDER          default: "1 3 10 30"
#   DEDICATED_LADDER            default: "1 3 10 24"
#   TOP_SCALE_REPEATS           default: 3
#   STABILIZE_CONSUMPTION_SECS  default: 90
#   STABILIZE_DEDICATED_SECS    default: 300  (D8 node provisioning)
#   PER_REPLICA_DELAY           default: 1    (passed through to sample.sh)
#   SKIP_DEDICATED              default: 0    (set to 1 to skip D8 track)
#   SKIP_CONSUMPTION            default: 0

set -uo pipefail

: "${RG:?required: resource group}"

CONSUMPTION_APP="${CONSUMPTION_APP:-ca-diag-consumption}"
DEDICATED_APP="${DEDICATED_APP:-ca-diag-dedicated}"
CONSUMPTION_LADDER="${CONSUMPTION_LADDER:-1 3 10 30}"
DEDICATED_LADDER="${DEDICATED_LADDER:-1 3 10 24}"
TOP_SCALE_REPEATS="${TOP_SCALE_REPEATS:-3}"
STABILIZE_CONSUMPTION_SECS="${STABILIZE_CONSUMPTION_SECS:-90}"
STABILIZE_DEDICATED_SECS="${STABILIZE_DEDICATED_SECS:-300}"
PER_REPLICA_DELAY="${PER_REPLICA_DELAY:-1}"
SKIP_DEDICATED="${SKIP_DEDICATED:-0}"
SKIP_CONSUMPTION="${SKIP_CONSUMPTION:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_SH="${SCRIPT_DIR}/sample.sh"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

EXPERIMENT_TS="$(date -u +%Y%m%d-%H%M%S)"
EXPERIMENT_LOG="${EVIDENCE_DIR}/trigger-${EXPERIMENT_TS}.log"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$EXPERIMENT_LOG"; }

wait_for_scale() {
  local app="$1" target="$2" wait_secs="$3"
  log "   waiting up to ${wait_secs}s for $app to reach $target replicas"
  local deadline=$(( $(date +%s) + wait_secs ))
  local last_count=-1
  while [[ $(date +%s) -lt $deadline ]]; do
    local rev count
    rev=$(az containerapp revision list \
      --resource-group "$RG" --name "$app" \
      --query '[?properties.active].name | [0]' --output tsv 2>/dev/null)
    if [[ -n "$rev" ]]; then
      count=$(az containerapp replica list \
        --resource-group "$RG" --name "$app" --revision "$rev" \
        --query 'length(@)' --output tsv 2>/dev/null || echo "0")
      if [[ "$count" != "$last_count" ]]; then
        log "   ... replicas=$count target=$target"
        last_count="$count"
      fi
      if [[ "$count" == "$target" ]]; then
        log "   ... stable at $count replicas"
        sleep 15
        return 0
      fi
    fi
    sleep 5
  done
  log "   WARNING: did not stabilize at $target within ${wait_secs}s (last=$last_count)"
  return 1
}

scale_app() {
  local app="$1" target="$2"
  log ">> scaling $app to min=max=$target"
  az containerapp update \
    --resource-group "$RG" \
    --name "$app" \
    --min-replicas "$target" \
    --max-replicas "$target" \
    --output none
}

run_ladder() {
  local profile_label="$1" app="$2" ladder="$3" stabilize_secs="$4" out_file="$5"
  log "================================================================"
  log "PROFILE: $profile_label  APP: $app  LADDER: $ladder"
  log "OUT FILE: $out_file"
  log "================================================================"

  local steps=($ladder)
  local last_step="${steps[-1]}"

  for step in "${steps[@]}"; do
    scale_app "$app" "$step"
    wait_for_scale "$app" "$step" "$stabilize_secs"

    if [[ "$step" == "$last_step" ]]; then
      for run_idx in $(seq 1 "$TOP_SCALE_REPEATS"); do
        log ">> SAMPLE: top-scale step=$step run=$run_idx/$TOP_SCALE_REPEATS"
        OUT_FILE="$out_file" \
        APP_NAME="$app" \
        RG="$RG" \
        RUN_LABEL="scale-${step}-run${run_idx}" \
        SCALE_AT_SAMPLE="$step" \
        PROFILE_LABEL="$profile_label" \
        PER_REPLICA_DELAY="$PER_REPLICA_DELAY" \
        bash "$SAMPLE_SH"
        if [[ $run_idx -lt $TOP_SCALE_REPEATS ]]; then
          log ">> inter-run pause 30s"
          sleep 30
        fi
      done
    else
      log ">> SAMPLE: intermediate step=$step"
      OUT_FILE="$out_file" \
      APP_NAME="$app" \
      RG="$RG" \
      RUN_LABEL="scale-${step}-run1" \
      SCALE_AT_SAMPLE="$step" \
      PROFILE_LABEL="$profile_label" \
      PER_REPLICA_DELAY="$PER_REPLICA_DELAY" \
      bash "$SAMPLE_SH"
    fi
  done
}

log ">> trigger.sh started at $EXPERIMENT_TS"
log ">> RG=$RG"
log ">> CONSUMPTION_LADDER=$CONSUMPTION_LADDER"
log ">> DEDICATED_LADDER=$DEDICATED_LADDER"
log ">> TOP_SCALE_REPEATS=$TOP_SCALE_REPEATS"

if [[ "$SKIP_CONSUMPTION" != "1" ]]; then
  CONS_OUT="${EVIDENCE_DIR}/consumption-${EXPERIMENT_TS}.jsonl"
  run_ladder "Consumption" "$CONSUMPTION_APP" "$CONSUMPTION_LADDER" "$STABILIZE_CONSUMPTION_SECS" "$CONS_OUT"
else
  log ">> SKIP_CONSUMPTION=1, skipping Consumption track"
fi

if [[ "$SKIP_DEDICATED" != "1" ]]; then
  DED_OUT="${EVIDENCE_DIR}/dedicated-${EXPERIMENT_TS}.jsonl"
  run_ladder "Dedicated-D8" "$DEDICATED_APP" "$DEDICATED_LADDER" "$STABILIZE_DEDICATED_SECS" "$DED_OUT"
else
  log ">> SKIP_DEDICATED=1, skipping Dedicated track"
fi

log ">> trigger.sh complete"
log ">> Evidence files:"
ls -la "$EVIDENCE_DIR" | tee -a "$EXPERIMENT_LOG"
