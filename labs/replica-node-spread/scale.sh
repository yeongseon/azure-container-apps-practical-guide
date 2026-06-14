#!/usr/bin/env bash
# Scale a subject app to exactly N replicas and wait until N are running.
#
# Sets both minReplicas and maxReplicas to N so KEDA does not drift the
# replica count during the sample window. Pins the scale by submitting
# az containerapp update, then polls az containerapp replica list every
# POLL_SECS seconds until exactly N replicas report runningState=Running
# OR the WAIT_SECS budget is exhausted.
#
# Usage:
#   ./scale.sh <app-name> <N>
#
# Required env:
#   RG       Resource group with the deployed lab.
#
# Optional env:
#   POLL_SECS    Poll interval in seconds (default: 10)
#   WAIT_SECS    Max wait for stable count in seconds (default: 600)

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-name> <N>" >&2
  exit 2
fi

APP="$1"
N="$2"
RG="${RG:-rg-aca-rns-lab}"
POLL_SECS="${POLL_SECS:-10}"
WAIT_SECS="${WAIT_SECS:-600}"

if ! [[ "$N" =~ ^[0-9]+$ ]] || (( N < 1 )); then
  echo "ERROR: N must be a positive integer (got '$N')" >&2
  exit 2
fi

echo ">> Scaling $APP to min=max=$N"
az containerapp update --resource-group "$RG" --name "$APP" \
  --min-replicas "$N" --max-replicas "$N" --output none

# Pinning min=max issues a revision-update internally and the new
# revision provisions before the old one drains. Wait until exactly N
# replicas with runningState=Running are present on the active revision.
DEADLINE=$(( $(date +%s) + WAIT_SECS ))
START=$(date +%s)
while (( $(date +%s) < DEADLINE )); do
  REV=$(az containerapp revision list --resource-group "$RG" --name "$APP" \
    --query '[?properties.active] | [0].name' --output tsv 2>/dev/null || echo "")
  if [[ -n "$REV" ]]; then
    # runningState is the per-replica field that flips to "Running" once
    # the container reports Ready. Length of the running subset is the
    # signal we wait on; total length can include terminating replicas
    # during the brief drain window after a min/max change.
    RUNNING=$(az containerapp replica list --resource-group "$RG" --name "$APP" \
      --revision "$REV" \
      --query "[?properties.runningState=='Running'] | length(@)" \
      --output tsv 2>/dev/null || echo "0")
    TOTAL=$(az containerapp replica list --resource-group "$RG" --name "$APP" \
      --revision "$REV" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
    ELAPSED=$(( $(date +%s) - START ))
    printf "   t=%03ds  rev=%s  running=%s  total=%s  (target=%s)\n" \
      "$ELAPSED" "$REV" "$RUNNING" "$TOTAL" "$N"
    if [[ "$RUNNING" == "$N" && "$TOTAL" == "$N" ]]; then
      echo ">> Reached stable count of $N replicas in ${ELAPSED}s"
      exit 0
    fi
  fi
  sleep "$POLL_SECS"
done

echo "ERROR: $APP did not reach $N running replicas within ${WAIT_SECS}s" >&2
exit 1
