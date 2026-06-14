#!/usr/bin/env bash
# Perturbation harness for the zone-redundancy-best-effort lab.
#
# Modes:
#   --perturb restart   Restart the active revision on a subject app (forces
#                       all replicas to terminate and be rescheduled). This is
#                       the closest user-side analog to a mass-reschedule event.
#   --perturb redeploy  Redeploy the Bicep template to trigger revision rollover.
#   --load              Generate HTTP load only (no perturbation). Use with
#                       --client to compare client resilience modes.
#   --combined          Run --load and --perturb restart together.
#
# Client variants (for --load and --combined):
#   --client no-retry         Single attempt, no retry. Surfaces 503s directly.
#   --client retry-backoff    Up to 4 retries with exponential backoff (0.2s,
#                             0.4s, 0.8s, 1.6s). Quantifies L2 mitigation.
#
# Required env:
#   RG       Resource group with the deployed lab.
#   APP      Subject app to perturb (default: app-min3).
#
# Usage examples:
#   export RG="rg-aca-zr-lab"
#   ./trigger.sh --perturb restart                       # mass-reschedule
#   ./trigger.sh --load --client no-retry --duration 120
#   ./trigger.sh --combined --client retry-backoff --duration 180

set -euo pipefail

RG="${RG:-rg-aca-zr-lab}"
APP="${APP:-app-min3}"
MODE=""
CLIENT="no-retry"
DURATION_SECS=120
REQS_PER_SEC=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --perturb) MODE="perturb-$2"; shift 2 ;;
    --load) MODE="load"; shift ;;
    --combined) MODE="combined"; shift ;;
    --client) CLIENT="$2"; shift 2 ;;
    --duration) DURATION_SECS="$2"; shift 2 ;;
    --rps) REQS_PER_SEC="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "ERROR: specify --perturb {restart|redeploy}, --load, or --combined" >&2
  exit 2
fi

if [[ "$CLIENT" != "no-retry" && "$CLIENT" != "retry-backoff" ]]; then
  echo "ERROR: --client must be no-retry or retry-backoff" >&2
  exit 2
fi

# Portable millisecond timestamps. GNU date supports +%s%3N (Unix epoch in ms)
# and +%Y-%m-%dT%H:%M:%S.%3NZ (ISO-8601 with ms) via the %N (nanoseconds)
# extension, but BSD date (macOS default) does not — %N is emitted literally.
# Detect once at startup and fall back to perl with Time::HiRes (POSIX
# standard, ~20 ms subprocess overhead) on systems without GNU date.
if date +%s%3N 2>/dev/null | grep -qE '^[0-9]{13}$'; then
  ts_ms()  { date +%s%3N; }
  iso_ts() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }
else
  ts_ms()  { perl -MTime::HiRes -e 'printf "%d\n", Time::HiRes::time()*1000'; }
  iso_ts() {
    perl -MTime::HiRes -MPOSIX -e 'my $t=Time::HiRes::time(); my $ms=int(($t-int($t))*1000); printf "%s.%03dZ\n", POSIX::strftime("%Y-%m-%dT%H:%M:%S", gmtime(int($t))), $ms'
  }
fi

emit_event() {
  local event="$1" extra="$2"
  printf '{"event":"%s","timestamp":"%s","app":"%s","client":"%s",%s}\n' \
    "$event" "$(iso_ts)" "$APP" "$CLIENT" "$extra"
}

get_fqdn() {
  az containerapp show --resource-group "$RG" --name "$APP" \
    --query 'properties.configuration.ingress.fqdn' --output tsv
}

perturb_restart() {
  local rev
  rev=$(az containerapp revision list --resource-group "$RG" --name "$APP" \
    --query '[?properties.active] | [0].name' --output tsv)
  emit_event "PerturbationStart" "\"type\":\"revision-restart\",\"revision\":\"$rev\""
  az containerapp revision restart --resource-group "$RG" --name "$APP" --revision "$rev" --output none
  emit_event "PerturbationSubmitted" "\"type\":\"revision-restart\",\"revision\":\"$rev\""
}

perturb_redeploy() {
  emit_event "PerturbationStart" "\"type\":\"redeploy\""
  az deployment group create --resource-group "$RG" \
    --template-file ./infra/main.bicep \
    --parameters ./infra/main.parameters.json \
    --output none
  emit_event "PerturbationSubmitted" "\"type\":\"redeploy\""
}

run_load() {
  local fqdn url end_ts
  fqdn=$(get_fqdn)
  url="https://${fqdn}/"
  end_ts=$(( $(date +%s) + DURATION_SECS ))
  local total=0 success=0 fail=0 latency_sum=0

  emit_event "LoadStart" "\"url\":\"$url\",\"rps\":$REQS_PER_SEC,\"durationSec\":$DURATION_SECS"

  while (( $(date +%s) < end_ts )); do
    for _ in $(seq 1 "$REQS_PER_SEC"); do
      local t0 code dt attempts=1
      t0=$(ts_ms)
      if [[ "$CLIENT" == "retry-backoff" ]]; then
        for attempt in 1 2 3 4 5; do
          code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
            --max-time 5 "$url" || echo "000")
          if [[ "$code" == "200" ]]; then
            attempts=$attempt
            break
          fi
          # Sleep between attempts only; documented backoff is 0.2s, 0.4s, 0.8s, 1.6s
          # after attempts 1..4. No sleep after attempt 5 to honor the four-retry budget.
          if (( attempt < 5 )); then
            sleep "$(awk "BEGIN{print 0.2*(2**($attempt-1))}")"
          fi
        done
      else
        code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
          --max-time 5 "$url" || echo "000")
      fi
      dt=$(( $(ts_ms) - t0 ))
      total=$((total + 1))
      latency_sum=$((latency_sum + dt))
      if [[ "$code" == "200" ]]; then success=$((success + 1)); else fail=$((fail + 1)); fi
    done
    sleep 1
  done

  local avg_ms=0
  if (( total > 0 )); then avg_ms=$(( latency_sum / total )); fi
  emit_event "LoadEnd" "\"total\":$total,\"success\":$success,\"fail\":$fail,\"avgLatencyMs\":$avg_ms"
}

case "$MODE" in
  perturb-restart) perturb_restart ;;
  perturb-redeploy) perturb_redeploy ;;
  load) run_load ;;
  combined)
    run_load &
    LOAD_PID=$!
    sleep "$(( DURATION_SECS / 4 ))"
    perturb_restart
    wait "$LOAD_PID"
    ;;
  *) echo "Unknown mode: $MODE"; exit 2 ;;
esac
