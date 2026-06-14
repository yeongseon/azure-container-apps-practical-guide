#!/usr/bin/env bash
# H3 (proxy validation) — falsification check that MUST pass before any
# H1/H2 conclusion is published.
#
# Two sub-checks:
#
#   H3a) Same-replica stability. Pin Consumption app to N=1, sample /diag
#        twice 30s apart. Both samples must report:
#          - identical boot_id
#          - monotonically increasing uptime_seconds (delta ~ 30s ± 5s)
#        Failure means boot_id is NOT a stable proxy for kernel identity
#        within a single replica's lifetime — the entire experiment is
#        invalid.
#
#   H3b) Restart-induced rotation. Restart the active revision (forces
#        replica replacement), wait 90s for the new replica to become
#        ready, sample again. The new boot_id MUST differ from the
#        pre-restart boot_id. Failure means boot_id is shared across
#        replica generations on the same host — the proxy cannot
#        distinguish "same node" from "same container restart".
#
# Both checks need only the app-consumption app at min=max=1.
# Evidence is written to evidence/h3-falsification-${RUN_ID}.jsonl
# and a human-readable verdict to evidence/h3-falsification-${RUN_ID}.txt
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   ./falsify.sh

set -euo pipefail

RG="${RG:-rg-aca-rns-lab}"
APP="app-consumption"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p evidence
RUN_ID="h3-$(date -u +%Y%m%d-%H%M%S)"
OUT="evidence/${RUN_ID}.jsonl"
VERDICT="evidence/${RUN_ID}.verdict.txt"

echo ">> H3 falsification run: $RUN_ID"
echo ">> Output: $OUT"

# Pin to 1 replica so we know the response is from the same container
# (modulo restart in H3b).
./scale.sh "$APP" 1

FQDN=$(az containerapp show --resource-group "$RG" --name "$APP" \
  --query 'properties.configuration.ingress.fqdn' --output tsv)
echo ">> FQDN: $FQDN"

sample_once() {
  local tag="$1"
  local body
  body=$(curl --silent --show-error --max-time 8 "https://${FQDN}/diag")
  local sample_at
  sample_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$body" | jq --compact-output \
    --arg phase "$tag" --arg app "$APP" --arg fqdn "$FQDN" \
    --arg run_id "$RUN_ID" --arg sample_at "$sample_at" \
    '. + {phase:$phase, app:$app, fqdn:$fqdn, run_id:$run_id, client_sample_at:$sample_at}' \
    >> "$OUT"
  echo "$body"
}

echo ">> H3a sample 1"
S1=$(sample_once "H3a-sample-1")
BOOT1=$(echo "$S1" | jq -r '.boot_id')
UP1=$(echo "$S1" | jq -r '.uptime_seconds')
echo "   boot_id=$BOOT1  uptime=$UP1"

echo ">> Sleeping 30s before H3a sample 2"
sleep 30

echo ">> H3a sample 2"
S2=$(sample_once "H3a-sample-2")
BOOT2=$(echo "$S2" | jq -r '.boot_id')
UP2=$(echo "$S2" | jq -r '.uptime_seconds')
echo "   boot_id=$BOOT2  uptime=$UP2"

H3A_PASS="no"
if [[ "$BOOT1" == "$BOOT2" ]]; then
  DELTA=$(awk "BEGIN{print $UP2 - $UP1}")
  # Expect ~30s elapsed. Allow 25..40s window — accounts for sleep skew
  # and request latency on either side.
  if awk "BEGIN{exit !($DELTA >= 25 && $DELTA <= 40)}"; then
    H3A_PASS="yes"
  fi
  H3A_NOTE="boot_id stable, uptime delta=${DELTA}s"
else
  H3A_NOTE="boot_id CHANGED between samples 30s apart (boot1=$BOOT1, boot2=$BOOT2) — proxy invalid"
fi

echo
echo ">> H3b restarting active revision to force replica replacement"
REV=$(az containerapp revision list --resource-group "$RG" --name "$APP" \
  --query '[?properties.active] | [0].name' --output tsv)
az containerapp revision restart --resource-group "$RG" --name "$APP" \
  --revision "$REV" --output none

echo ">> Waiting 90s for replacement replica to become ready"
sleep 90

# Re-confirm there is exactly 1 ready replica before sampling.
./scale.sh "$APP" 1

echo ">> H3b sample"
S3=$(sample_once "H3b-post-restart")
BOOT3=$(echo "$S3" | jq -r '.boot_id')
UP3=$(echo "$S3" | jq -r '.uptime_seconds')
echo "   boot_id=$BOOT3  uptime=$UP3"

H3B_PASS="no"
H3B_NOTE=""
if [[ "$BOOT3" != "$BOOT2" ]]; then
  H3B_PASS="yes"
  H3B_NOTE="boot_id rotated after restart (pre=$BOOT2, post=$BOOT3)"
else
  # boot_id can match across restarts only if the replacement landed on
  # the same physical node AND ACA reused the host kernel session. That
  # would not invalidate H3 by itself, but it means our proxy cannot
  # distinguish container-restart from host-shared on Consumption.
  H3B_NOTE="boot_id UNCHANGED across restart — proxy may conflate container restart with shared host"
fi

OVERALL="FAIL"
if [[ "$H3A_PASS" == "yes" && "$H3B_PASS" == "yes" ]]; then
  OVERALL="PASS"
fi

{
  echo "H3 falsification verdict — run $RUN_ID"
  echo "----------------------------------------------------------------"
  echo "H3a (same-replica boot_id stability + monotonic uptime): $H3A_PASS"
  echo "    $H3A_NOTE"
  echo "H3b (restart-induced boot_id rotation):                  $H3B_PASS"
  echo "    $H3B_NOTE"
  echo "----------------------------------------------------------------"
  echo "Overall: $OVERALL"
  echo
  echo "Raw samples:"
  echo "  pre1   boot_id=$BOOT1  uptime=$UP1"
  echo "  pre2   boot_id=$BOOT2  uptime=$UP2"
  echo "  post   boot_id=$BOOT3  uptime=$UP3"
} | tee "$VERDICT"

if [[ "$OVERALL" != "PASS" ]]; then
  echo "ERROR: H3 falsification did not pass. Do NOT publish H1/H2 conclusions." >&2
  exit 1
fi
echo ">> H3 passed. H1/H2 analysis is allowed to proceed."
