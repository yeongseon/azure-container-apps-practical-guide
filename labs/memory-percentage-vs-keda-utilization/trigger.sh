#!/usr/bin/env bash
# trigger.sh — Phase B evidence-pack orchestrator for Lab 14.
#
# Reproduces three side-by-side Container Apps that share the same memory
# scale rule (Utilization=50, min=2, max=20) but exercise different
# workload mixes, then captures a flat, chronologically-numbered evidence
# pack under labs/memory-percentage-vs-keda-utilization/evidence/.
#
# Strict 2-path predicate (per Oracle Option α, Lab 14 strategy review):
#   Scenario A — Just-below (rss, TARGET_MB=400, expected per-replica ~40%):
#     Strong: replicas_max <= 2, memorypercentage in [25,50], scale rule
#             {min=2, max=20, target=50}, cgroup rss/anon-dominant.
#     Fallback: active revision steady at 2 replicas, no scale-out event,
#               cgroup composition shows rss/anon-dominant footprint.
#   Scenario B — Just-above (rss, TARGET_MB=560, expected per-replica ~56%):
#     Strong: replicas_max == 20, memorypercentage crosses 50, same scale
#             rule, cgroup rss/anon-dominant.
#     Fallback: replicas_max > A AND > C, memorypercentage crosses 50,
#               cgroup rss/anon-dominant.
#   Scenario C — Cache inflation (cache, TARGET_MB=700, expected ~72%):
#     Strong: replicas_max <= 5, memorypercentage_max > 50, cgroup
#             cache/file > 5x rss/anon (cache-heavy composition).
#     Fallback: replicas near floor despite over-target memorypercentage,
#               cgroup cache-heavy.
#   H2 cross-scenario differential (lab hypothesis):
#     Strong: A.replicas_max <= 2 AND B.replicas_max == 20 AND
#             C.replicas_max <= 5 AND C.memorypercentage > 50 AND
#             C.cgroup cache-dominant.
#     Fallback: B >> A AND B >> C ordinal scaling; A pinned at floor;
#               C near floor despite over-target memory.
#
# PII / Secret safety:
#   - ACR admin credential (username + password) is the one P0 secret
#     surface in this lab. The password is retrieved into a shell
#     variable, passed to `az containerapp create` as a registry password,
#     and is NEVER logged to any evidence file. The containerapp show
#     responses captured under properties.configuration.registries[]
#     deliberately reference `passwordSecretRef`, not the raw password
#     (Container Apps stores it as a managed secret).
#   - All `set -x` debugging is intentionally NOT used after credential
#     retrieval to avoid leaking the password in command echo.
#
# Numbered prefix policy (per Phase B Lab 11+12 lessons):
#   01..21 = trigger-side snapshots (this script).
#   22..25 = verify.sh sub-gates (H1×3 + H2×1).
#   Plural filenames everywhere; index starts at 01-* (never 00-*).
#
# Empirical platform behavior captured during 2026-06-24 live run:
#   - az-cli 2.79.0 `--offset PT15M` alone raises TypeError inside
#     az monitor metrics list (datetime - str). Workaround: pass explicit
#     `--start-time`/`--end-time` ISO 8601 pair (computed up front).
#   - `az containerapp exec` requires a pseudo-tty. On a non-interactive
#     macOS shell it fails with `tty.setcbreak()`. Workaround: wrap each
#     exec call with `script -q /dev/null ... < /dev/null` to allocate a
#     pty without interactive input. Each call still carries az-cli noise
#     (INFO:, Disconnect, Use ctrl-..., FutureWarning, WARNING:); the
#     captures pipe through a noise filter before being recorded.
#   - Container Apps throttles consecutive exec calls (HTTP 429 Too Many
#     Requests). Sleep 20 seconds between cgroup exec calls.
#   - Container Apps on AKS expose cgroup v1 at
#     /sys/fs/cgroup/memory/memory.{usage_in_bytes,limit_in_bytes,stat}.
#     The capture issues three separate exec calls (one per file) and
#     writes them to three separate JSON keys so verify.sh can parse each
#     file independently. The captured strings retain the pty's
#     "\r\r\n" line endings — verify.sh strips them before parsing.
#
# Usage:
#   export RG=rg-aca-lab-mempct2 ACR_NAME=... ENV_NAME=... LOCATION=koreacentral
#   bash labs/memory-percentage-vs-keda-utilization/trigger.sh

set -euo pipefail

: "${RG:?RG must be set}"
: "${ACR_NAME:?ACR_NAME must be set}"
: "${ENV_NAME:?ENV_NAME must be set}"
: "${LOCATION:=koreacentral}"

IMAGE_TAG="${IMAGE_TAG:-mempct:v1}"
SCENARIO_A_APP="${SCENARIO_A_APP:-ca-mempct-a-below}"
SCENARIO_B_APP="${SCENARIO_B_APP:-ca-mempct-b-above}"
SCENARIO_C_APP="${SCENARIO_C_APP:-ca-mempct-cache}"
WAIT_SECONDS="${WAIT_SECONDS:-1200}"   # 20 min for HPA to walk + stable window
METRICS_LOOKBACK_MINUTES="${METRICS_LOOKBACK_MINUTES:-15}"

# Resolve metric window as explicit ISO 8601 start/end pair.
# RATIONALE: az-cli 2.79.0 has a bug where `--offset PT15M` alone (without
# `--start-time`/`--end-time`) raises:
#   TypeError: unsupported operand type(s) for -: 'datetime.datetime' and 'str'
# inside list_metrics. Using the explicit pair sidesteps the buggy code path.
METRIC_END_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
METRIC_START_UTC="$(date -u -v "-${METRICS_LOOKBACK_MINUTES}M" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -d "-${METRICS_LOOKBACK_MINUTES} minutes" '+%Y-%m-%dT%H:%M:%SZ')"

EVIDENCE_DIR="$(cd "$(dirname "$0")" && pwd)/evidence"
mkdir -p "$EVIDENCE_DIR"

echo "=== Phase 1: Infra Resolve ==="
ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)"
# SECURITY: ACR credential retrieval. Username + password go into shell
# vars only. The password is NEVER echoed, NEVER captured to evidence.
# Container Apps will store it as a managed secret (passwordSecretRef).
ACR_USERNAME="$(az acr credential show --name "$ACR_NAME" --query username --output tsv)"
ACR_PASSWORD="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' --output tsv)"
ENV_ID="$(az containerapp env show --name "$ENV_NAME" --resource-group "$RG" --query id --output tsv)"

# Record infra resolve WITHOUT credentials. Image digest captured via repo show.
IMAGE_DIGEST="$(az acr repository show --name "$ACR_NAME" --image "$IMAGE_TAG" --query digest --output tsv 2>/dev/null || echo "unknown")"

cat > "$EVIDENCE_DIR/01-infra-resolve.json" <<EOF
{
  "resource_group": "$RG",
  "location": "$LOCATION",
  "acr_name": "$ACR_NAME",
  "acr_login_server": "$ACR_LOGIN_SERVER",
  "acr_credential_retrieved": true,
  "acr_credential_logged_to_evidence": false,
  "acr_credential_safety_note": "Username + password retrieved into shell variables only. Password never written to evidence files. Container Apps stores it as a managed secret (passwordSecretRef) — visible in containerapp show responses as a secret reference, never as the raw value.",
  "environment_name": "$ENV_NAME",
  "environment_id": "$ENV_ID",
  "image_tag": "$IMAGE_TAG",
  "image_digest": "$IMAGE_DIGEST",
  "image_full_reference": "$ACR_LOGIN_SERVER/$IMAGE_TAG@$IMAGE_DIGEST"
}
EOF
echo "[01] infra resolve written"

echo "=== Phase 2: Image Metadata ==="
# The workload image is built before this script runs (see Reproducibility
# section of evidence/README.md for the az acr build command). This phase
# captures the manifest metadata as 02-image-manifest.json so the evidence
# chain records the image digest the three scenarios were created against.
az acr repository show \
  --name "$ACR_NAME" --image "$IMAGE_TAG" \
  --output json > "$EVIDENCE_DIR/02-image-manifest.json" 2>&1 || {
    echo '{"error": "az acr repository show failed"}' > "$EVIDENCE_DIR/02-image-manifest.json"
}
echo "[02] image manifest written"

FULL_IMAGE="$ACR_LOGIN_SERVER/$IMAGE_TAG"

create_scenario() {
  local app_name="$1"
  local mode="$2"
  local target_mb="$3"
  local evidence_index="$4"
  local label="$5"
  echo "[$evidence_index] creating $app_name (MODE=$mode, TARGET_MB=$target_mb)"
  # ACR password is passed via --registry-password. Do NOT enable `set -x`.
  az containerapp create \
    --name "$app_name" --resource-group "$RG" \
    --environment "$ENV_NAME" --image "$FULL_IMAGE" \
    --registry-server "$ACR_LOGIN_SERVER" \
    --registry-username "$ACR_USERNAME" --registry-password "$ACR_PASSWORD" \
    --cpu 0.5 --memory 1.0Gi \
    --min-replicas 2 --max-replicas 20 \
    --ingress external --target-port 8000 \
    --scale-rule-name memory-rule --scale-rule-type memory \
    --scale-rule-metadata "type=Utilization" "value=50" \
    --env-vars "MODE=$mode" "TARGET_MB=$target_mb" \
    --output json > /tmp/trigger-${app_name}-create.json 2>&1 || true
  # Show responses redact secret VALUES — only secret NAMES appear.
  az containerapp show \
    --name "$app_name" --resource-group "$RG" \
    --output json > "$EVIDENCE_DIR/$evidence_index-scenario-${label}-trigger.json"
  rm -f /tmp/trigger-${app_name}-create.json
}

echo "=== Phase 3: Create Scenario A (ca-mempct-a-below) ==="
create_scenario "$SCENARIO_A_APP" "rss" "400" "03" "a"

echo "=== Phase 4: Create Scenario B (ca-mempct-b-above) ==="
create_scenario "$SCENARIO_B_APP" "rss" "560" "04" "b"

echo "=== Phase 5: Create Scenario C (ca-mempct-cache) ==="
create_scenario "$SCENARIO_C_APP" "cache" "700" "05" "c"

echo "=== Phase 6: Wait $WAIT_SECONDS seconds for HPA to walk + metrics to stabilize ==="
WAIT_LOG="$EVIDENCE_DIR/06-wait-markers.log"
{
  echo "wait_start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "wait_seconds=$WAIT_SECONDS"
  echo "expected_end_utc=$(date -u -v "+${WAIT_SECONDS}S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "+${WAIT_SECONDS} seconds" '+%Y-%m-%dT%H:%M:%SZ')"
  for elapsed in 120 240 360 480 600 720 840 960 1080 1200; do
    if [ "$elapsed" -gt "$WAIT_SECONDS" ]; then break; fi
    sleep_chunk=120
    sleep "$sleep_chunk"
    echo "elapsed=${elapsed}s now_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  done
  echo "wait_end_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$WAIT_LOG" 2>&1
echo "[06] wait complete, markers logged"

capture_cgroup_file() {
  local app_name="$1"
  local replica="$2"
  local cgroup_path="$3"
  script -q /dev/null az containerapp exec \
      --name "$app_name" --resource-group "$RG" \
      --replica "$replica" --container "$app_name" \
      --command "cat $cgroup_path" \
      < /dev/null 2>&1 \
    | grep -v '^INFO:' \
    | grep -v 'Disconnect' \
    | grep -v 'Use ctrl' \
    | grep -v 'FutureWarning' \
    | grep -v 'warnings.warn' \
    | grep -v '^WARNING:' \
    | grep -v '^Script started' \
    | grep -v '^Script done' \
    || true
}

capture_scenario_evidence() {
  local app_name="$1"
  local revisions_idx="$2"
  local replicas_idx="$3"
  local memory_idx="$4"
  local cgroup_idx="$5"
  local label="$6"
  echo "[$revisions_idx-$cgroup_idx] capturing $app_name evidence ($label)"

  az containerapp revision list \
    --name "$app_name" --resource-group "$RG" \
    --output json > "$EVIDENCE_DIR/$revisions_idx-scenario-${label}-revisions.json"

  local app_id
  app_id="$(az containerapp show --name "$app_name" --resource-group "$RG" --query id --output tsv)"

  az monitor metrics list \
    --resource "$app_id" --metric "Replicas" \
    --aggregation Maximum --interval PT1M \
    --start-time "$METRIC_START_UTC" --end-time "$METRIC_END_UTC" \
    --output json > "$EVIDENCE_DIR/$replicas_idx-scenario-${label}-replicas.json"

  az monitor metrics list \
    --resource "$app_id" --metric "MemoryPercentage" \
    --aggregation Average --interval PT1M \
    --start-time "$METRIC_START_UTC" --end-time "$METRIC_END_UTC" \
    --output json > "$EVIDENCE_DIR/$memory_idx-scenario-${label}-memorypercentage.json"

  local active_rev replica
  active_rev="$(az containerapp revision list --name "$app_name" --resource-group "$RG" --query '[?properties.active]|[0].name' --output tsv)"
  replica="$(az containerapp replica list --name "$app_name" --resource-group "$RG" --revision "$active_rev" --query '[0].name' --output tsv)"
  if [ -n "$replica" ]; then
    local memory_usage_raw memory_limit_raw memory_stat_raw
    memory_usage_raw="$(capture_cgroup_file "$app_name" "$replica" /sys/fs/cgroup/memory/memory.usage_in_bytes)"
    sleep 20
    memory_limit_raw="$(capture_cgroup_file "$app_name" "$replica" /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    sleep 20
    memory_stat_raw="$(capture_cgroup_file "$app_name" "$replica" /sys/fs/cgroup/memory/memory.stat)"
    MEM_USAGE="$memory_usage_raw" MEM_LIMIT="$memory_limit_raw" MEM_STAT="$memory_stat_raw" \
    APP_NAME="$app_name" ACTIVE_REV="$active_rev" REPLICA="$replica" \
    CAPTURED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    python3 - > "$EVIDENCE_DIR/$cgroup_idx-scenario-${label}-cgroup.json" <<'PYEOF'
import json, os
out = {
    "app_name": os.environ["APP_NAME"],
    "active_revision": os.environ["ACTIVE_REV"],
    "replica_name": os.environ["REPLICA"],
    "captured_at_utc": os.environ["CAPTURED_AT"],
    "cgroup_version": "v1",
    "memory_path": "/sys/fs/cgroup/memory",
    "memory_usage_in_bytes_raw": os.environ["MEM_USAGE"],
    "memory_limit_in_bytes_raw": os.environ["MEM_LIMIT"],
    "memory_stat_raw": os.environ["MEM_STAT"],
}
print(json.dumps(out, indent=2))
PYEOF
  else
    cat > "$EVIDENCE_DIR/$cgroup_idx-scenario-${label}-cgroup.json" <<EOF
{
  "app_name": "$app_name",
  "active_revision": "$active_rev",
  "replica_name": null,
  "captured_at_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "error": "no replica returned from replica list"
}
EOF
  fi
}

echo "=== Phase 7-10: Scenario A Evidence ==="
capture_scenario_evidence "$SCENARIO_A_APP" "07" "08" "09" "10" "a"

echo "=== Phase 11-14: Scenario B Evidence ==="
capture_scenario_evidence "$SCENARIO_B_APP" "11" "12" "13" "14" "b"

echo "=== Phase 15-18: Scenario C Evidence ==="
capture_scenario_evidence "$SCENARIO_C_APP" "15" "16" "17" "18" "c"

echo "=== Phase 19: CLI Versions ==="
az version --output json > "$EVIDENCE_DIR/19-cli-versions.json"

echo "=== Phase 20: Container Apps Extension Version ==="
az extension show --name containerapp --output json > "$EVIDENCE_DIR/20-cli-containerapp-ext.json" 2>&1 || \
  echo '{"error": "containerapp extension not installed"}' > "$EVIDENCE_DIR/20-cli-containerapp-ext.json"

echo "=== Phase 21: Region ==="
cat > "$EVIDENCE_DIR/21-region.json" <<EOF
{
  "location": "$LOCATION",
  "subscription_id": "$(az account show --query id --output tsv)",
  "tenant_id": "$(az account show --query tenantId --output tsv)"
}
EOF

echo "=== Trigger complete ==="
echo "Evidence directory: $EVIDENCE_DIR"
echo "Files written: 21 numbered snapshots (01..21)"
echo "Next step: run verify.sh to compute H1 sub-gates (22..24) and H2 cross-scenario gate (25)."
