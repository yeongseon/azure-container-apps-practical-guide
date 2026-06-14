#!/usr/bin/env bash
# H3 (proxy validation) — empirical falsification of the boot_id signal as
# a per-replica kernel-context proxy. MUST pass before any H1/H2
# conclusion is published.
#
# Empirical findings from initial H3 run (h3-20260614-131354) reshaped the
# design:
#
#   - boot_id is a kernel-instance UUID, not a hardware-host UUID. On
#     Consumption it reflects the per-replica microVM kernel (Hyper-V
#     isolation gives each replica its own kernel). On Dedicated D8 it
#     reflects the shared D8 VM kernel.
#   - `az containerapp revision restart` only restarts user-space, not
#     the underlying microVM kernel. The original "restart rotates
#     boot_id" assumption was wrong — uptime continued monotonically
#     across restart in the initial run, confirming no kernel rotation.
#   - boot_id DID differ between two distinct replicas on Consumption
#     (one on revision wv4y44w, one on revision 0000001) — empirical
#     proof that boot_id distinguishes microVMs.
#
# The redesigned H3 tests what the proxy MUST satisfy for H1/H2 to be
# valid, without depending on restart semantics:
#
#   H3a) Per-replica stability. Pin Consumption app to min=max=1. Sample
#        /diag 5 times at 10s intervals. All 5 samples MUST report:
#          - identical replica_name (= we hit the same replica each time)
#          - identical boot_id (= proxy is stable within a replica)
#          - monotonically increasing uptime_seconds (= proxy reflects
#            real kernel time, not a cached value)
#        Failure on any sub-check means the proxy is non-deterministic
#        and the experiment is invalid.
#
#   H3b) Non-trivial UUID. boot_id MUST be a real-looking UUID, not
#        empty, not "null", not the all-zeros sentinel. This guards
#        against the kernel returning a placeholder in a misconfigured
#        environment.
#
# What H3 deliberately does NOT test:
#
#   - "restart rotates boot_id" — empirically false (see above). The
#     original H3b would test ACA's restart semantics, not our proxy.
#   - "different replicas always have different boot_ids" — this is
#     actually the H1/H2 research question on Consumption (expected yes)
#     vs Dedicated D8 (expected no, all on one shared kernel).
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

# Ensure N=1 (idempotent — no-op if already at min=max=1; otherwise rolls
# one revision and waits for steady state before sampling).
./scale.sh "$APP" 1

# Settle period: even after scale.sh returns "stable", the ingress may
# still be transitioning between revisions. Wait 30s so we sample a
# steady replica, not a draining one.
echo ">> Settling 30s before first sample"
sleep 30

FQDN=$(az containerapp show --resource-group "$RG" --name "$APP" \
  --query 'properties.configuration.ingress.fqdn' --output tsv)
echo ">> FQDN: $FQDN"

# Append one /diag sample to the JSONL output and echo it for downstream
# parsing. The wrapper fields (phase, app, fqdn, run_id, client_sample_at)
# match the trigger.sh sample.sh schema so analyze.py can ingest this
# evidence too.
sample_once() {
  local idx="$1"
  local body
  body=$(curl --silent --show-error --max-time 8 "https://${FQDN}/diag")
  local sample_at
  sample_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$body" | jq --compact-output \
    --arg phase "H3a-sample-${idx}" --arg app "$APP" --arg fqdn "$FQDN" \
    --arg run_id "$RUN_ID" --arg sample_at "$sample_at" \
    '. + {phase:$phase, app:$app, fqdn:$fqdn, run_id:$run_id, client_sample_at:$sample_at}' \
    >> "$OUT"
  echo "$body"
}

# Collect 5 samples 10s apart. Use parallel index-aligned arrays rather
# than ${arr[-1]} (bash 4.3+) for macOS bash 3.2 compatibility.
REPLICAS=()
BOOTS=()
UPTIMES=()
for i in 1 2 3 4 5; do
  echo ">> H3a sample $i"
  S=$(sample_once "$i")
  R=$(echo "$S" | jq -r '.replica_name')
  B=$(echo "$S" | jq -r '.boot_id')
  U=$(echo "$S" | jq -r '.uptime_seconds')
  REPLICAS+=("$R")
  BOOTS+=("$B")
  UPTIMES+=("$U")
  echo "   replica=$R  boot=$B  uptime=$U"
  if [[ $i -lt 5 ]]; then sleep 10; fi
done

# Pin index 0 as the canonical reference value and compare the remaining
# samples against it.
R0="${REPLICAS[0]}"
B0="${BOOTS[0]}"

# H3a-1: all 5 samples must hit the same replica_name.
H3A_REPLICA_CONSISTENT="yes"
H3A_REPLICA_NOTE="all 5 samples hit replica=$R0"
for r in "${REPLICAS[@]}"; do
  if [[ "$r" != "$R0" ]]; then
    H3A_REPLICA_CONSISTENT="no"
    H3A_REPLICA_NOTE="replica_name varied across samples — ingress may be in transition (saw $r, expected $R0)"
    break
  fi
done

# H3a-2: all 5 samples must report the same boot_id.
H3A_BOOT_CONSISTENT="yes"
H3A_BOOT_NOTE="boot_id stable at $B0 across all 5 samples"
for b in "${BOOTS[@]}"; do
  if [[ "$b" != "$B0" ]]; then
    H3A_BOOT_CONSISTENT="no"
    H3A_BOOT_NOTE="boot_id varied within same replica — proxy non-deterministic (saw $b, expected $B0)"
    break
  fi
done

# H3a-3: uptime_seconds must strictly increase sample-to-sample. Use awk
# float comparison; bash lacks native float comparison.
H3A_UPTIME_MONOTONIC="yes"
H3A_UPTIME_NOTE="uptime monotonically increased from ${UPTIMES[0]}s to ${UPTIMES[4]}s"
PREV="${UPTIMES[0]}"
for idx in 1 2 3 4; do
  CUR="${UPTIMES[$idx]}"
  if awk "BEGIN{exit !($CUR <= $PREV)}"; then
    H3A_UPTIME_MONOTONIC="no"
    H3A_UPTIME_NOTE="uptime non-monotonic at sample $((idx+1)): $CUR <= $PREV"
    break
  fi
  PREV="$CUR"
done

# H3b: boot_id must be a real-looking UUID, not empty/null/zero-sentinel.
H3B_PASS="yes"
H3B_NOTE="boot_id=$B0 is a non-trivial UUID"
if [[ -z "$B0" || "$B0" == "null" || "$B0" == "00000000-0000-0000-0000-000000000000" ]]; then
  H3B_PASS="no"
  H3B_NOTE="boot_id is empty/null/zero-sentinel — kernel did not provide a real UUID"
fi

OVERALL="FAIL"
if [[ "$H3A_REPLICA_CONSISTENT" == "yes" \
   && "$H3A_BOOT_CONSISTENT" == "yes" \
   && "$H3A_UPTIME_MONOTONIC" == "yes" \
   && "$H3B_PASS" == "yes" ]]; then
  OVERALL="PASS"
fi

{
  echo "H3 falsification verdict — run $RUN_ID"
  echo "----------------------------------------------------------------"
  echo "H3a-replica-consistent:  $H3A_REPLICA_CONSISTENT  ($H3A_REPLICA_NOTE)"
  echo "H3a-boot-consistent:     $H3A_BOOT_CONSISTENT  ($H3A_BOOT_NOTE)"
  echo "H3a-uptime-monotonic:    $H3A_UPTIME_MONOTONIC  ($H3A_UPTIME_NOTE)"
  echo "H3b-boot-nontrivial:     $H3B_PASS  ($H3B_NOTE)"
  echo "----------------------------------------------------------------"
  echo "Overall: $OVERALL"
  echo
  echo "Raw samples (replica_name | boot_id | uptime_seconds):"
  for i in 0 1 2 3 4; do
    printf "  sample %d  %s  %s  %s\n" \
      $((i+1)) "${REPLICAS[$i]}" "${BOOTS[$i]}" "${UPTIMES[$i]}"
  done
} | tee "$VERDICT"

if [[ "$OVERALL" != "PASS" ]]; then
  echo "ERROR: H3 falsification did not pass. Do NOT publish H1/H2 conclusions." >&2
  exit 1
fi
echo ">> H3 passed. H1/H2 analysis is allowed to proceed."
