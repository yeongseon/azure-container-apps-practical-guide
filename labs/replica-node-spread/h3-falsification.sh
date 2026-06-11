#!/usr/bin/env bash
# h3-falsification.sh — Oracle-mandated proxy validation.
#
# Tests two invariants of the boot_id + uptime proxy:
#
# Part A (idempotence): the same replica sampled twice 30-60s apart
#   must yield (a) identical boot_id and (b) uptime that advanced
#   monotonically by approximately the wall-clock delta. If either
#   fails, the proxy is invalid and H1/H2 analysis must NOT be published.
#
# Part B (new-replica detection): force-restart a small set of
#   replicas one at a time. Each new replica must report a DIFFERENT
#   boot_id from the one it replaced, otherwise we cannot distinguish
#   "same node" from "different node".
#
# Required env:
#   RG          Resource group
#
# Optional env:
#   APP_NAME              default: ca-diag-consumption (Consumption likely yields multiple boot_ids)
#   REPEAT_SAMPLE_GAP     default: 45   (seconds between same-replica samples)
#   RESTART_COUNT         default: 3    (Oracle min 3, recommended 3-5)
#   RESTART_WAIT_SECS     default: 90   (wait for new replica to be Running)

set -uo pipefail

: "${RG:?required: resource group}"

APP_NAME="${APP_NAME:-ca-diag-consumption}"
REPEAT_SAMPLE_GAP="${REPEAT_SAMPLE_GAP:-45}"
RESTART_COUNT="${RESTART_COUNT:-3}"
RESTART_WAIT_SECS="${RESTART_WAIT_SECS:-90}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_SH="${SCRIPT_DIR}/sample.sh"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

TS="$(date -u +%Y%m%d-%H%M%S)"
PART_A_OUT="${EVIDENCE_DIR}/h3-same-replica-${TS}.jsonl"
PART_B_OUT="${EVIDENCE_DIR}/h3-restart-${TS}.jsonl"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

REVISION=$(az containerapp revision list \
  --resource-group "$RG" --name "$APP_NAME" \
  --query '[?properties.active].name | [0]' --output tsv)

if [[ -z "$REVISION" ]]; then
  echo "ERROR: no active revision for $APP_NAME" >&2
  exit 1
fi

log "================================================================"
log "H3 PART A — same-replica idempotence (boot_id stable, uptime monotonic)"
log "================================================================"

OUT_FILE="$PART_A_OUT" \
APP_NAME="$APP_NAME" \
RG="$RG" \
RUN_LABEL="h3a-t0" \
SCALE_AT_SAMPLE="0" \
PROFILE_LABEL="h3-validation" \
PER_REPLICA_DELAY="0" \
bash "$SAMPLE_SH"

log ">> Pausing ${REPEAT_SAMPLE_GAP}s before second sample"
sleep "$REPEAT_SAMPLE_GAP"

OUT_FILE="$PART_A_OUT" \
APP_NAME="$APP_NAME" \
RG="$RG" \
RUN_LABEL="h3a-t1" \
SCALE_AT_SAMPLE="0" \
PROFILE_LABEL="h3-validation" \
PER_REPLICA_DELAY="0" \
bash "$SAMPLE_SH"

log ">> Part A complete. Output: $PART_A_OUT"

log "================================================================"
log "H3 PART B — single-replica restart, expect new boot_id"
log "================================================================"

REPLICA_NAMES=$(az containerapp replica list \
  --resource-group "$RG" --name "$APP_NAME" --revision "$REVISION" \
  --query '[].name' --output tsv)

mapfile -t REPLICAS <<< "$REPLICA_NAMES"
TOTAL_REPLICAS="${#REPLICAS[@]}"

if [[ $TOTAL_REPLICAS -lt $RESTART_COUNT ]]; then
  log "WARNING: only $TOTAL_REPLICAS replicas available; reducing RESTART_COUNT to $TOTAL_REPLICAS"
  RESTART_COUNT=$TOTAL_REPLICAS
fi

for ((i = 0; i < RESTART_COUNT; i++)); do
  REPLICA="${REPLICAS[$i]}"
  log ">> H3B sample $((i+1))/$RESTART_COUNT — pre-restart probe of $REPLICA"

  OUT_FILE="$PART_B_OUT" \
  APP_NAME="$APP_NAME" \
  RG="$RG" \
  RUN_LABEL="h3b-pre-${i}" \
  SCALE_AT_SAMPLE="0" \
  PROFILE_LABEL="h3-validation" \
  PER_REPLICA_DELAY="0" \
  bash "$SAMPLE_SH"

  log ">> Restarting replica $REPLICA"
  if ! az containerapp replica restart \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --revision "$REVISION" \
        --replica "$REPLICA" \
        --output none 2>/dev/null; then
    log "   (replica restart command unavailable in this CLI; falling back to revision restart)"
    az containerapp revision restart \
      --resource-group "$RG" \
      --name "$APP_NAME" \
      --revision "$REVISION" \
      --output none || true
  fi

  log "   waiting ${RESTART_WAIT_SECS}s for replacement replica to be Running"
  sleep "$RESTART_WAIT_SECS"

  OUT_FILE="$PART_B_OUT" \
  APP_NAME="$APP_NAME" \
  RG="$RG" \
  RUN_LABEL="h3b-post-${i}" \
  SCALE_AT_SAMPLE="0" \
  PROFILE_LABEL="h3-validation" \
  PER_REPLICA_DELAY="0" \
  bash "$SAMPLE_SH"
done

log ">> Part B complete. Output: $PART_B_OUT"
log "================================================================"
log ">> NEXT: run analyze.py against the two JSONL files to confirm:"
log ">>   - Part A: same replica name => same boot_id, uptime strictly increasing"
log ">>   - Part B: any post-sample replica with a name not in pre-set"
log ">>            must have a boot_id distinct from the pre-set"
log "================================================================"
