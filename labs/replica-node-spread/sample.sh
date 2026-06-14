#!/usr/bin/env bash
# Sample /diag on a subject app and write per-replica JSONL evidence.
#
# Hits https://<fqdn>/diag <samples> times. Each sample is wrapped with
# run-level metadata (run_id, profile, scale_target, replica_count_target,
# app, fqdn, sample_index) and appended as one JSON line to <output>.
# We oversample to maximize the chance of hitting every replica behind
# the ACA load balancer; downstream analyze.py deduplicates by replica_name.
#
# Usage:
#   ./sample.sh <app> <fqdn> <samples> <output.jsonl> <run_id> <profile> <scale_target>
#
# Example:
#   ./sample.sh app-consumption $FQDN 60 \
#     ./evidence/consumption-scale-10-run-1.jsonl \
#     run-2026-06-14T13-22-00Z-1 Consumption 10

set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 <app> <fqdn> <samples> <output> <run_id> <profile> <scale_target>" >&2
  exit 2
fi

APP="$1"
FQDN="$2"
SAMPLES="$3"
OUT="$4"
RUN_ID="$5"
PROFILE="$6"
SCALE_TARGET="$7"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")"
URL="https://${FQDN}/diag"

echo ">> Sampling $URL  samples=$SAMPLES  run_id=$RUN_ID"

ok=0
fail=0
for i in $(seq 1 "$SAMPLES"); do
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # --silent suppresses the progress meter; --show-error surfaces transport
  # errors. --max-time 8 must exceed the diag handler's worst-case (it
  # only reads small /proc files; 8s is generous and shields us from
  # one-off ingress hiccups).
  if BODY=$(curl --silent --show-error --max-time 8 "$URL" 2>/dev/null); then
    # Validate that the body is JSON; otherwise drop the sample and log
    # to stderr so it does not corrupt the JSONL evidence file.
    if echo "$BODY" | jq -e . >/dev/null 2>&1; then
      echo "$BODY" | jq --compact-output \
        --arg app "$APP" --arg fqdn "$FQDN" --arg run_id "$RUN_ID" \
        --arg profile "$PROFILE" --argjson scale_target "$SCALE_TARGET" \
        --argjson sample_index "$i" --arg sample_at "$TS" \
        '. + {app:$app, fqdn:$fqdn, run_id:$run_id, profile:$profile, scale_target:$scale_target, sample_index:$sample_index, client_sample_at:$sample_at}' \
        >> "$OUT"
      ok=$((ok + 1))
    else
      echo "[sample $i] non-JSON body, skipped" >&2
      fail=$((fail + 1))
    fi
  else
    echo "[sample $i] curl failed" >&2
    fail=$((fail + 1))
  fi
done

echo ">> Sampling complete: ok=$ok fail=$fail out=$OUT"
