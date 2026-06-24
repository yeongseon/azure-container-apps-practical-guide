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
# Required env:
#   RG               Resource group with the deployed lab.
#   SUBSCRIPTION_ID  Exact Azure subscription this lab targets (defensive).
#
# Usage:
#   source /tmp/rns-lab.env   # exports SUBSCRIPTION_ID, RG, ...
#   ./trigger.sh

set -euo pipefail

# Defensive guard: prevent accidental cross-subscription trigger runs.
: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID must be exported (e.g. source /tmp/rns-lab.env)}"
ACTIVE_SUB=$(az account show --query id --output tsv 2>/dev/null || true)
if [[ "$ACTIVE_SUB" != "$SUBSCRIPTION_ID" ]]; then
  echo "ERROR: az active subscription mismatch" >&2
  echo "  expected: $SUBSCRIPTION_ID" >&2
  echo "  active  : $ACTIVE_SUB" >&2
  echo "  fix     : az account set --subscription $SUBSCRIPTION_ID" >&2
  exit 1
fi

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
  echo "ERROR: could not resolve both app FQDNs. Run health-check.sh first." >&2
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

# Scale sequences per profile.
#
# CONS_SCALES walks Consumption 1 -> 3 -> 10 -> 30. The top of 30 is the
# repeat target.
#
# DED_SCALES walks Dedicated D8 1 -> 3 -> 10. The top of 10 is the
# repeat target. The empirically validated capacity ceiling on a single
# D8 node (8 vCPU, 32 GiB) with 0.25 vCPU / 0.5 GiB per replica is
# ~10 replicas — earlier exploratory runs that attempted 24 replicas
# could not provision them within a 600s window because system overhead
# (control-plane sidecars, DaemonSet pods, kubelet headroom) consumes
# meaningful vCPU. The D8 ceiling itself is documented as a sidebar
# finding in the lab guide; the main H1/H2 experiment uses the
# provisionable top so the 3-repeat protocol completes within budget.
declare -a CONS_SCALES=(1 3 10 30)
declare -a DED_SCALES=(1 3 10)

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
