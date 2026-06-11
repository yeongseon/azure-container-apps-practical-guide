#!/usr/bin/env bash
# sample-revision.sh — sample one specific revision (bypass active-revision auto-pick)
# Used to capture revision 0000004 (24 replicas, fully provisioned) after the
# main trigger.sh wait loop timed out at 300s.
#
# Usage: RG=... APP_NAME=... REVISION=... OUT_FILE=... RUN_LABEL=... PROFILE_LABEL=... ./sample-revision.sh

set -uo pipefail
: "${RG:?}" "${APP_NAME:?}" "${REVISION:?}" "${OUT_FILE:?}"
RUN_LABEL="${RUN_LABEL:-revision-explicit}"
PROFILE_LABEL="${PROFILE_LABEL:-Dedicated-D8}"
SCALE_AT_SAMPLE="${SCALE_AT_SAMPLE:-0}"
MAX_EXEC_RETRIES="${MAX_EXEC_RETRIES:-5}"
PER_REPLICA_DELAY="${PER_REPLICA_DELAY:-5}"

mkdir -p "$(dirname "$OUT_FILE")"

exec_in_pty() {
  if script --version >/dev/null 2>&1; then
    script -q -c "$*" /dev/null
  else
    script -q /dev/null "$@"
  fi
}
now_ms() {
  # BSD date(1) on macOS prints "17811548703N" (literal "3N") and returns rc=0
  # for `+%s%3N`, so a bare `|| python3 ...` fallback never triggers. Validate
  # the output matches digits-only before accepting it.
  if date -u +%s%3N 2>/dev/null | grep -qE '^[0-9]+$'; then
    date -u +%s%3N
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
}
now_iso() {
  if date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null | grep -qE '\.[0-9]{3}Z$'; then
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
  else
    python3 -c 'import time, datetime as dt; n=dt.datetime.now(dt.timezone.utc); print(n.strftime("%Y-%m-%dT%H:%M:%S.")+f"{n.microsecond//1000:03d}Z")'
  fi
}

REPLICAS_JSON=$(az containerapp replica list --resource-group "$RG" --name "$APP_NAME" --revision "$REVISION" --output json 2>/dev/null)
COUNT=$(echo "$REPLICAS_JSON" | jq 'length')
echo ">> Sampling $COUNT replica(s) of $APP_NAME revision=$REVISION (run: $RUN_LABEL)"

REPLICA_NAMES=$(echo "$REPLICAS_JSON" | jq -r '.[].name')
INDEX=0
while IFS= read -r REPLICA <&3; do
  [[ -z "$REPLICA" ]] && continue
  INDEX=$((INDEX + 1))
  printf "   [%2d/%2d] %s ... " "$INDEX" "$COUNT" "$REPLICA"
  ATTEMPT=0; SUCCESS=0; LAST_ERR=""; OUT=""; RAW=""; LOCAL_TS_MS=""
  while [[ $ATTEMPT -lt $MAX_EXEC_RETRIES ]]; do
    ATTEMPT=$((ATTEMPT + 1))
    LOCAL_TS_MS="$(now_ms)"
    RAW=$(exec_in_pty az containerapp exec --resource-group "$RG" --name "$APP_NAME" --revision "$REVISION" --replica "$REPLICA" --container diag --command "/usr/local/bin/diag.sh" 2>&1)
    OUT=$(echo "$RAW" | tr -d '\r' | sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -E '^\{' | head -n1)
    if [[ -n "$OUT" ]] && echo "$OUT" | jq -e .boot_id >/dev/null 2>&1; then SUCCESS=1; break; fi
    if echo "$RAW" | grep -qi "429 Too Many Requests"; then LAST_ERR="exec_attempt_${ATTEMPT}_handshake_429_throttled"
    elif echo "$RAW" | grep -qi "Handshake status"; then LAST_ERR="exec_attempt_${ATTEMPT}_handshake_non_200"
    else LAST_ERR="exec_attempt_${ATTEMPT}_no_parseable_json"; fi
    BACKOFF=$(( 2 ** ATTEMPT )); [[ $BACKOFF -gt 30 ]] && BACKOFF=30; sleep "$BACKOFF"
  done
  if [[ $SUCCESS -eq 1 ]]; then
    AUG=$(echo "$OUT" | jq -c --arg event "ReplicaDiagSample" --arg sample_iso "$(now_iso)" --argjson local_sample_ts_ms "$LOCAL_TS_MS" --arg app "$APP_NAME" --arg revision "$REVISION" --arg replica "$REPLICA" --arg run_label "$RUN_LABEL" --arg profile "$PROFILE_LABEL" --argjson scale_at_sample "$SCALE_AT_SAMPLE" --argjson attempt "$ATTEMPT" '. + {event:$event, sample_iso:$sample_iso, local_sample_ts_ms:$local_sample_ts_ms, app:$app, revision:$revision, replica:$replica, run_label:$run_label, profile:$profile, scale_at_sample:$scale_at_sample, attempt:$attempt}')
    echo "$AUG" >> "$OUT_FILE"
    printf "ok (attempt %d)\n" "$ATTEMPT"
  else
    FAIL=$(jq -cn --arg event "ReplicaDiagFailure" --arg sample_iso "$(now_iso)" --argjson local_sample_ts_ms "$LOCAL_TS_MS" --arg app "$APP_NAME" --arg revision "$REVISION" --arg replica "$REPLICA" --arg run_label "$RUN_LABEL" --arg profile "$PROFILE_LABEL" --argjson scale_at_sample "$SCALE_AT_SAMPLE" --argjson attempts "$ATTEMPT" --arg last_error "$LAST_ERR" '{event:$event, sample_iso:$sample_iso, local_sample_ts_ms:$local_sample_ts_ms, app:$app, revision:$revision, replica:$replica, run_label:$run_label, profile:$profile, scale_at_sample:$scale_at_sample, attempts:$attempts, last_error:$last_error}')
    echo "$FAIL" >> "$OUT_FILE"
    printf "FAIL after %d attempts (%s)\n" "$ATTEMPT" "$LAST_ERR"
  fi
  [[ "$PER_REPLICA_DELAY" != "0" ]] && sleep "$PER_REPLICA_DELAY"
done 3<<< "$REPLICA_NAMES"
