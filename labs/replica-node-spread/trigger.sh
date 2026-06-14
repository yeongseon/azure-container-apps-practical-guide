#!/usr/bin/env bash
# Master orchestrator for the replica-node-spread lab.
#
# For each profile (Consumption, then Dedicated D8), walks the scale
# sequence 1 -> 3 -> 10 -> top, sampling /diag at each step. At the top
# scale step it repeats the sample 3 times (with a brief settle pause
# between) so the analysis stage can verify concurrence across runs.
#
# Sample size at each step is sized to oversample relative to the replica
# count so we have a high probability of hitting every replica:
#   N=1   -> 6 samples   (sanity)
#   N=3   -> 30 samples  (10x)
#   N=10  -> 80 samples  (8x)
#   N=top -> 8*top       (8x, so 240 for top=30, 192 for top=24)
#
# Per-step output:
#   evidence/<profile-lower>-scale-<N>-run-<R>.jsonl
#
# Required env:
#   RG       Resource group with the deployed lab.
#
# Optional env:
#   SKIP_FALSIFY=1   Skip the H3 falsification gate (NOT RECOMMENDED)
#   TOP_REPEATS=3    Number of repeats at top scale (default 3)
#   SETTLE_SECS=20   Pause after scale before sampling (default 20)
#
# Usage:
#   export RG="rg-aca-rns-lab"
#   ./trigger.sh

set -euo pipefail

RG="${RG:-rg-aca-rns-lab}"
TOP_REPEATS="${TOP_REPEATS:-3}"
SETTLE_SECS="${SETTLE_SECS:-20}"
SKIP_FALSIFY="${SKIP_FALSIFY:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
mkdir -p evidence

# Resolve FQDNs once so a transient ARM hiccup mid-run does not break us.
CONS_FQDN=$(az containerapp show --resource-group "$RG" --name "app-consumption" \
  --query 'properties.configuration.ingress.fqdn' --output tsv)
DED_FQDN=$(az containerapp show --resource-group "$RG" --name "app-dedicated-d8" \
  --query 'properties.configuration.ingress.fqdn' --output tsv)

if [[ -z "$CONS_FQDN" || -z "$DED_FQDN" ]]; then
  echo "ERROR: could not resolve both app FQDNs. Run verify.sh first." >&2
  exit 1
fi

echo ">> Consumption FQDN : $CONS_FQDN"
echo ">> Dedicated  FQDN : $DED_FQDN"

# H3 falsification gate — H1/H2 results are scientifically meaningless if
# the proxy is invalid, so we refuse to start sampling unless falsify.sh
# returned PASS (or the operator explicitly opts out).
if [[ "$SKIP_FALSIFY" != "1" ]]; then
  echo
  echo ">> Running H3 falsification gate"
  ./falsify.sh
  echo ">> H3 passed; proceeding with H1/H2 sampling"
else
  echo ">> SKIP_FALSIFY=1 — skipping H3 gate (do not publish H1/H2 results)"
fi

# Scale sequence per profile (top differs because D8 caps at 8 vCPU).
declare -a CONS_SCALES=(1 3 10 30)
declare -a DED_SCALES=(1 3 10 24)

# Per-step oversample factor and overrides for the small steps.
samples_for() {
  local n="$1"
  case "$n" in
    1)  echo 6   ;;
    3)  echo 30  ;;
    10) echo 80  ;;
    *)  echo $(( n * 8 )) ;;
  esac
}

run_profile() {
  local app="$1" fqdn="$2" profile_label="$3"
  shift 3
  local scales=("$@")
  local top="${scales[${#scales[@]}-1]}"

  echo
  echo "============================================================"
  echo "Profile: $profile_label   app=$app   FQDN=$fqdn"
  echo "Scales : ${scales[*]}   top=$top   repeats_at_top=$TOP_REPEATS"
  echo "============================================================"

  for n in "${scales[@]}"; do
    local repeats=1
    [[ "$n" == "$top" ]] && repeats="$TOP_REPEATS"

    # tr is used instead of bash 4 ${var,,} so the script works on
    # macOS default bash 3.2 without requiring brew install bash.
    local profile_slug
    profile_slug=$(printf '%s' "$profile_label" | tr '[:upper:]' '[:lower:]')

    for r in $(seq 1 "$repeats"); do
      local ts run_id out samples
      ts=$(date -u +%Y%m%d-%H%M%S)
      run_id="${profile_slug}-n${n}-r${r}-${ts}"
      out="evidence/${profile_slug}-scale-${n}-run-${r}.jsonl"
      samples=$(samples_for "$n")

      echo
      echo "-- step n=$n repeat=$r of $repeats samples=$samples run_id=$run_id"

      ./scale.sh "$app" "$n"
      echo "   settle ${SETTLE_SECS}s before sampling"
      sleep "$SETTLE_SECS"
      ./sample.sh "$app" "$fqdn" "$samples" "$out" "$run_id" "$profile_label" "$n"
    done
  done
}

run_profile "app-consumption"  "$CONS_FQDN" "Consumption"  "${CONS_SCALES[@]}"
run_profile "app-dedicated-d8" "$DED_FQDN"  "Dedicated-D8" "${DED_SCALES[@]}"

# Scale both back down to 1 to stop charging unused replicas while the
# operator runs analysis.
echo
echo ">> Scaling both apps back to 1 replica to reduce cost"
./scale.sh app-consumption 1
./scale.sh app-dedicated-d8 1

echo
echo ">> Trigger complete. Next: python3 ./analyze.py"
