#!/usr/bin/env bash
# sample.sh — enumerate all replicas of one app and capture a diag JSON
# line from each. Output is one JSON line per replica appended to
# $OUT_FILE (JSONL format). The operator-side sample timestamp is
# recorded as `local_sample_ts_ms` so analysis can compute
# boot_time_estimate = local_sample_ts_ms/1000 - uptime_seconds.
#
# Required env:
#   RG          Resource group
#   APP_NAME    Container app to sample
#   OUT_FILE    Path to JSONL output (will be created/appended)
#
# Optional env:
#   RUN_LABEL          Free-form label embedded in every line (e.g. "scale-30-run1")
#   SCALE_AT_SAMPLE    Numeric replica count target at sample time
#   PROFILE_LABEL      "Consumption" or "Dedicated-D8" — embedded as `profile`
#   MAX_EXEC_RETRIES   Per-replica retry count for transient exec failures (default 3)
#   PER_REPLICA_DELAY  Seconds to sleep between replicas (default 0)

set -uo pipefail

: "${RG:?required: resource group}"
: "${APP_NAME:?required: container app name}"
: "${OUT_FILE:?required: JSONL output path}"

RUN_LABEL="${RUN_LABEL:-unlabeled}"
SCALE_AT_SAMPLE="${SCALE_AT_SAMPLE:-0}"
PROFILE_LABEL="${PROFILE_LABEL:-unknown}"
MAX_EXEC_RETRIES="${MAX_EXEC_RETRIES:-5}"
PER_REPLICA_DELAY="${PER_REPLICA_DELAY:-0}"

mkdir -p "$(dirname "$OUT_FILE")"

# `az containerapp exec` requires a PTY (knack/CLI calls
# tty.setcbreak(stdin)) and aborts non-interactively. We wrap it with
# script(1) to allocate a pseudo-terminal. BSD form (macOS) takes the
# output file before the command; GNU form (Linux) needs `-c`.
exec_in_pty() {
  if script --version >/dev/null 2>&1; then
    script -q -c "$*" /dev/null
  else
    script -q /dev/null "$@"
  fi
}

now_ms() {
  if date -u +%s%3N | grep -qE '^[0-9]+$'; then
    date -u +%s%3N
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
}
now_iso() {
  if date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" | grep -qE '\.[0-9]{3}Z$'; then
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
  else
    python3 -c 'import time, datetime as dt; n=dt.datetime.now(dt.timezone.utc); print(n.strftime("%Y-%m-%dT%H:%M:%S.")+f"{n.microsecond//1000:03d}Z")'
  fi
}

emit_meta_line() {
  local stage="$1" detail="$2"
  jq -cn \
    --arg event "ReplicaDiagMeta" \
    --arg ts "$(now_iso)" \
    --argjson ts_ms "$(now_ms)" \
    --arg app "$APP_NAME" \
    --arg run_label "$RUN_LABEL" \
    --arg profile "$PROFILE_LABEL" \
    --argjson scale_at_sample "$SCALE_AT_SAMPLE" \
    --arg stage "$stage" \
    --arg detail "$detail" \
    '{event:$event, sample_iso:$ts, sample_ts_ms:$ts_ms, app:$app,
      run_label:$run_label, profile:$profile, scale_at_sample:$scale_at_sample,
      stage:$stage, detail:$detail}' \
    >> "$OUT_FILE"
}

REVISION=$(az containerapp revision list \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query '[?properties.active].name | [0]' \
  --output tsv 2>/dev/null)

if [[ -z "$REVISION" ]]; then
  emit_meta_line "no_active_revision" "ARM returned no active revision for $APP_NAME"
  echo "ERROR: no active revision for $APP_NAME" >&2
  exit 1
fi

REPLICAS_JSON=$(az containerapp replica list \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --revision "$REVISION" \
  --output json 2>/dev/null)

if [[ -z "$REPLICAS_JSON" ]] || ! echo "$REPLICAS_JSON" | jq -e '. | type == "array"' >/dev/null 2>&1; then
  emit_meta_line "replica_list_failed" "az containerapp replica list returned non-array"
  echo "ERROR: replica list failed for $APP_NAME" >&2
  exit 1
fi

REPLICA_COUNT=$(echo "$REPLICAS_JSON" | jq 'length')
emit_meta_line "enumeration_ok" "revision=${REVISION} replica_count=${REPLICA_COUNT}"

echo ">> Sampling $REPLICA_COUNT replica(s) of $APP_NAME (run: $RUN_LABEL)"

REPLICA_NAMES=$(echo "$REPLICAS_JSON" | jq -r '.[].name')
INDEX=0
# Read replica names from FD 3 instead of stdin. `script` (used by
# exec_in_pty) attaches its child to a PTY but inherits FD 0 from
# the loop body; with a here-string on FD 0 the child consumes the
# remaining names and the loop exits after iteration 1. FD 3 keeps
# the iteration source isolated from the exec child's stdin.
while IFS= read -r REPLICA <&3; do
  [[ -z "$REPLICA" ]] && continue
  INDEX=$((INDEX + 1))
  printf "   [%2d/%2d] %s ... " "$INDEX" "$REPLICA_COUNT" "$REPLICA"

  ATTEMPT=0
  SUCCESS=0
  LAST_ERR=""
  OUT=""
  RAW=""
  LOCAL_TS_MS=""
  while [[ $ATTEMPT -lt $MAX_EXEC_RETRIES ]]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOCAL_TS_MS="$(now_ms)"
    RAW=$(exec_in_pty az containerapp exec \
      --resource-group "$RG" \
      --name "$APP_NAME" \
      --revision "$REVISION" \
      --replica "$REPLICA" \
      --container diag \
      --command "/usr/local/bin/diag.sh" 2>&1)
    OUT=$(echo "$RAW" \
      | tr -d '\r' \
      | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
      | grep -E '^\{' \
      | head -n1)
    if [[ -n "$OUT" ]] && echo "$OUT" | jq -e .boot_id >/dev/null 2>&1; then
      SUCCESS=1
      break
    fi
    if echo "$RAW" | grep -qi "429 Too Many Requests"; then
      LAST_ERR="exec_attempt_${ATTEMPT}_handshake_429_throttled"
    elif echo "$RAW" | grep -qi "Handshake status"; then
      LAST_ERR="exec_attempt_${ATTEMPT}_handshake_non_200"
    else
      LAST_ERR="exec_attempt_${ATTEMPT}_no_parseable_json"
    fi
    BACKOFF=$(( 2 ** ATTEMPT ))
    [[ $BACKOFF -gt 30 ]] && BACKOFF=30
    sleep "$BACKOFF"
  done

  if [[ $SUCCESS -eq 1 ]]; then
    AUGMENTED=$(echo "$OUT" | jq -c \
      --arg event "ReplicaDiagSample" \
      --arg sample_iso "$(now_iso)" \
      --argjson local_sample_ts_ms "$LOCAL_TS_MS" \
      --arg app "$APP_NAME" \
      --arg revision "$REVISION" \
      --arg replica "$REPLICA" \
      --arg run_label "$RUN_LABEL" \
      --arg profile "$PROFILE_LABEL" \
      --argjson scale_at_sample "$SCALE_AT_SAMPLE" \
      --argjson attempt "$ATTEMPT" \
      '. + {event:$event, sample_iso:$sample_iso, local_sample_ts_ms:$local_sample_ts_ms,
            app:$app, revision:$revision, replica:$replica, run_label:$run_label,
            profile:$profile, scale_at_sample:$scale_at_sample, attempt:$attempt}')
    echo "$AUGMENTED" >> "$OUT_FILE"
    printf "ok (attempt %d)\n" "$ATTEMPT"
  else
    FAIL_LINE=$(jq -cn \
      --arg event "ReplicaDiagFailure" \
      --arg sample_iso "$(now_iso)" \
      --argjson local_sample_ts_ms "$LOCAL_TS_MS" \
      --arg app "$APP_NAME" \
      --arg revision "$REVISION" \
      --arg replica "$REPLICA" \
      --arg run_label "$RUN_LABEL" \
      --arg profile "$PROFILE_LABEL" \
      --argjson scale_at_sample "$SCALE_AT_SAMPLE" \
      --argjson attempts "$ATTEMPT" \
      --arg last_error "$LAST_ERR" \
      '{event:$event, sample_iso:$sample_iso, local_sample_ts_ms:$local_sample_ts_ms,
        app:$app, revision:$revision, replica:$replica, run_label:$run_label,
        profile:$profile, scale_at_sample:$scale_at_sample, attempts:$attempts,
        last_error:$last_error}')
    echo "$FAIL_LINE" >> "$OUT_FILE"
    printf "FAIL after %d attempts (%s)\n" "$ATTEMPT" "$LAST_ERR"
  fi

  if [[ "$PER_REPLICA_DELAY" != "0" ]]; then
    sleep "$PER_REPLICA_DELAY"
  fi
done 3<<< "$REPLICA_NAMES"

ACTUAL_LINES=$(grep -cE "\"run_label\":\"${RUN_LABEL}\".*\"event\":\"ReplicaDiag(Sample|Failure)\"" "$OUT_FILE" 2>/dev/null | head -n1)
ACTUAL_LINES="${ACTUAL_LINES:-0}"
echo ">> Wrote $ACTUAL_LINES sample line(s) (target=$REPLICA_COUNT) to $OUT_FILE"
