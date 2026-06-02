#!/usr/bin/env bash
set -euo pipefail

: "${RG:?RG (resource group) must be set}"
: "${APP_NAME:?APP_NAME must be set}"

APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query id --output tsv)"
LOOKBACK="${LOOKBACK:-PT30M}"
TARGET="${TARGET:-50}"

echo "==============================================="
echo "App: $APP_NAME"
echo "Lookback: $LOOKBACK"
echo "Scale-rule target Utilization: $TARGET"
echo "==============================================="

echo
echo "--- Replica count (Max) over lookback ---"
az monitor metrics list \
  --resource "$APP_ID" --metric "Replicas" \
  --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
  --output table || true

echo
echo "--- Memory Percentage (Avg) over lookback ---"
az monitor metrics list \
  --resource "$APP_ID" --metric "MemoryPercentage" \
  --aggregation Average --interval PT1M --offset "$LOOKBACK" \
  --output table || true

echo
echo "--- Memory Working Set Bytes (Avg) over lookback ---"
az monitor metrics list \
  --resource "$APP_ID" --metric "WorkingSetBytes" \
  --aggregation Average --interval PT1M --offset "$LOOKBACK" \
  --output table || true

echo
echo "--- Active revision and replica count ---"
ACTIVE_REV="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query '[?properties.active]|[0].name' -o tsv)"
az containerapp revision show --name "$APP_NAME" --resource-group "$RG" --revision "$ACTIVE_REV" \
  --query "{name:name, replicas:properties.replicas, active:properties.active}" -o table

echo
echo "--- cgroup memory.stat from a live replica (anon vs file cache) ---"
REPLICA="$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --revision "$ACTIVE_REV" --query '[0].name' -o tsv)"
if [[ -n "$REPLICA" ]]; then
  echo "Replica: $REPLICA"
  az containerapp exec \
    --name "$APP_NAME" --resource-group "$RG" \
    --replica "$REPLICA" --container "$APP_NAME" \
    --command "/bin/sh -c 'echo --- memory.current ---; cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes; echo; echo --- memory.max ---; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes; echo; echo --- memory.stat (top fields) ---; (cat /sys/fs/cgroup/memory.stat 2>/dev/null || cat /sys/fs/cgroup/memory/memory.stat) | head -20'" \
    2>&1 || echo "(exec failed - replica may be initializing)"
fi

echo
echo "--- HPA ceiling math hint ---"
echo "Formula: desiredReplicas = ceil(currentReplicas * currentMetric / targetMetric)"
echo "With target=${TARGET} and currentReplicas=N, scale-out boundary per current util M:"
printf "  N=2  -> needs M > %s%% to reach replicas=3\n" "$TARGET"
printf "  N=3  -> needs M > %d%% to reach replicas=4 (ceil(3*M/%s) > 3 iff M > %s)\n" "$TARGET" "$TARGET" "$TARGET"
echo "(KEDA also applies a small tolerance, typically 0.1, before triggering.)"
