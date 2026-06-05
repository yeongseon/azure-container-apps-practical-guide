#!/usr/bin/env bash
set -uo pipefail

BASE="https://ca-loadtest-d38538.purplemeadow-5cd727b2.koreacentral.azurecontainerapps.io"
LOGDIR="/tmp/metrics-load"
mkdir -p "$LOGDIR"

echo "Starting parallel load against $BASE"
echo "Logs: $LOGDIR/"

# Steady mixed traffic - drives Requests, ResponseTime, RxBytes, TxBytes
hey -z 30m -c 30 -q 5 "$BASE/health" > "$LOGDIR/health.log" 2>&1 &
echo "  [pid $!] health: 30c@5rps for 30m"

# CPU burn - drives CpuPercentage, UsageNanoCores, triggers HTTP scaler (Replicas, CoresQuotaUsed)
hey -z 30m -c 25 -q 4 "$BASE/cpu?ms=400" > "$LOGDIR/cpu.log" 2>&1 &
echo "  [pid $!] cpu: 25c@4rps 400ms burn for 30m"

# Memory growth - drives MemoryPercentage, WorkingSetBytes
hey -z 30m -c 2 -q 1 "$BASE/mem?mb=8" > "$LOGDIR/mem.log" 2>&1 &
echo "  [pid $!] mem: 2c@1rps 8MiB alloc for 30m"

# 500 errors - drives Requests by Status Code Category (ServerError)
hey -z 30m -c 5 -q 2 "$BASE/error?code=500" > "$LOGDIR/err500.log" 2>&1 &
echo "  [pid $!] err500: 5c@2rps for 30m"

# 4xx errors - drives Requests by Status Code Category (ClientError)
hey -z 30m -c 3 -q 1 "$BASE/error?code=404" > "$LOGDIR/err404.log" 2>&1 &
echo "  [pid $!] err404: 3c@1rps for 30m"

# Slow responses - drives ResponseTime tail
hey -z 30m -c 4 -q 1 "$BASE/slow?ms=1500" > "$LOGDIR/slow.log" 2>&1 &
echo "  [pid $!] slow: 4c@1rps 1500ms for 30m"

# Large payloads - drives TxBytes
hey -z 30m -c 4 -q 2 "$BASE/payload?kb=512" > "$LOGDIR/payload.log" 2>&1 &
echo "  [pid $!] payload: 4c@2rps 512KiB for 30m"

echo ""
echo "All load generators started in background."
# hey's -q flag is requests-per-second PER WORKER, not aggregate. Sustained aggregate
# RPS depends on backpressure from the target app. Observed steady-state on the docs
# environment was ~130-145 RPS into ca-loadtest-d38538, which is enough to push the
# HTTP scaler (concurrentRequests=20) toward the max-replicas=10 ceiling.
echo "Sustained for 30 minutes; observed ~130-145 RPS aggregate steady-state on the docs env."
