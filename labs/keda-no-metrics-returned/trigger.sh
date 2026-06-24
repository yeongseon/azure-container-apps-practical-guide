#!/usr/bin/env bash
# trigger.sh — Phase B evidence-pack orchestrator for Lab 16 (keda-no-metrics-returned).
#
# Reproduces the cross-scenario differential evidence pack that proves:
#   H1.a: The "no metrics returned" signal appears while a replica is Not
#         Ready during the readiness/startup-probe window (slow-start).
#   H1.b: The same signal persists across multiple 5-min bins when the
#         replica never becomes Ready (crash-loop with periodic exits).
#   H2:   The same signal disappears after the replica reaches Ready and
#         stays Ready (healthy baseline) — i.e. the signal does NOT
#         persist once the container is steady-state Healthy.
#   H3:   The error-window DURATION tracks the readiness outcome:
#         healthy ≲ slow ≪ crash (single-bin vs single-bin vs multi-bin).
#
# Orchestrates the same 3-scenario evidence capture observed on 2026-06-20:
#   Scenario A (slow):    ca-nometrics-slow    — MODE=slow-start (120s delay)
#                         Revision becomes Healthy after StartUp probe failures
#                         clear; the metric-error signal is confined to the
#                         pre-Ready window and a brief ~15s aftershock.
#                         Canonical revision suffix on 2026-06-20: --gd2u817
#                         Canonical error window: 00:35:49 → 00:38:05 (~136s,
#                         20 events, single 5-min bin @ 00:35).
#   Scenario B (crash):   ca-nometrics-crash   — MODE=crash-loop (exits every 30s)
#                         Revision is Unhealthy/Failed; the metric-error
#                         signal appears in MULTIPLE 5-min bins as replicas
#                         restart with exponential backoff.
#                         Canonical revision suffix on 2026-06-20: --xfn3h34
#                         Canonical error window: 00:36:37 → 00:46:40 (~10+ min,
#                         27 events, 3 bins @ 00:35/00:40/00:45).
#   Scenario C (healthy): ca-nometrics-healthy — MODE=healthy (control)
#                         Revision is Healthy/Running; the metric-error
#                         signal appears ONLY in the first 5-min bin
#                         during Kubernetes Metrics Server warm-up, then
#                         goes silent.
#                         Canonical revision suffix on 2026-06-20: --9ovm8cn
#                         Canonical error window: 00:37:31 → 00:39:17 (~106s,
#                         16 events, single 5-min bin @ 00:35).
#
# Phases (driven by a SINGLE script — no manual operator steps):
#   Phase 1 — Resolve infra outputs (RG, ENV_NAME, ACR_NAME, WORKSPACE_CUSTOMER_ID)
#   Phase 2 — Build the workload image once via az acr build (one image,
#             three deployments — MODE is set per-scenario via env vars)
#   Phase 3 — Deploy Scenario C (healthy baseline) FIRST so that the
#             Metrics Server warm-up signal is captured cleanly without
#             interference from the failing scenarios
#   Phase 4 — Deploy Scenario A (slow-start) and wait for the StartUp
#             probe window to elapse (DELAY_SECONDS + safety margin)
#   Phase 5 — Deploy Scenario B (crash-loop) and wait for at least 3
#             crash cycles so the error pattern spans multiple 5-min bins
#   Phase 6 — Wait LOG_ANALYTICS_LAG_SECONDS (360s) for ingestion
#   Phase 7 — Capture per-scenario evidence (report-${TS}.txt + sidecar
#             JSONs) for all 3 apps. The capture is performed by an
#             inline function (capture_app_evidence) rather than by
#             verify.sh, because verify.sh is now a pure file processor.
#
# Option Y trigger pattern (per Oracle Lab 16 strategy review, FRESH
# session bg_6d132066, verdict 2026-06-22):
#   trigger.sh OWNS the canonical evidence run AND invokes the existing
#   trigger-scenario-{a,b,c}.sh helpers sequentially. The scenario helpers
#   are PRESERVED (not deleted) so an operator who wants to reproduce a
#   SINGLE scenario can still do so. verify.sh becomes a PURE FILE
#   PROCESSOR that reads the captures this script writes and emits the
#   4 gate JSONs. It does not call Azure.
#
# Strict 2-path predicate boundary (per Oracle Option γ, Lab 15 strategy
# review carried forward to Lab 16):
#   The evidence captures (report-*.txt + revisions-*.json + traffic-*.json)
#   are the ONLY inputs verify.sh sees. verify.sh does not re-issue any
#   az or KQL calls. This script is the only side-effect script in this
#   lab. Re-running the canonical evidence requires running this script.
#
# Evidence reuse policy (per Oracle Lab 16 directive):
#   The 2026-06-20 canonical evidence is the BASELINE. The committed
#   evidence files under evidence/ca-nometrics-{slow,crash,healthy}/ are
#   the artifacts verify.sh reads. This script EXISTS so that the
#   capture choreography is reproducible — running it would OVERWRITE
#   the 2026-06-20 captures with a new TS. Operators reproducing the lab
#   from scratch will run this script; the committed 2026-06-20 evidence
#   is preserved as the canonical baseline and is NOT regenerated by
#   normal CI runs.
#
# Empirical platform behavior captured during the 2026-06-20 live run
# (preserved verbatim in evidence/README.md "Honest disclosure" section):
#   - The §13 cgroup capture in report-*.txt is EXPECTED to fail when the
#     operator runs this script from macOS, because `az containerapp exec`
#     spawns a PTY via tty.setcbreak() which is "Operation not supported
#     by device" outside of an interactive terminal. The traceback is
#     preserved as honest disclosure of what an operator sees, NOT as
#     evidence that the experiment failed. Gates 10-13 do not depend on
#     §13. This was observed on 2026-06-20 with azure-cli 2.79.0 +
#     containerapp extension 1.3.0b4 on macOS Python 3.9.
#   - The §12a-f Azure Monitor metrics sections are EXPECTED to be EMPTY
#     in this lab because the metric error timeline (§6) and the
#     KQL-derived per-bin counts already provide the falsifying data,
#     and the platform metric pipeline (Replicas, RestartCount,
#     MemoryPercentage, CpuPercentage, WorkingSetBytes, Requests) has
#     its own ingestion lag distinct from ContainerAppSystemLogs_CL.
#     Gates 10-13 do not depend on §12a-f.
#   - The §7 DEPRECATED warning ("The 'type' setting is DEPRECATED and
#     will be removed in v2.18 - Use 'metricType' instead.") appears
#     EXACTLY ONCE per app at KEDA scaler initialization, regardless of
#     scenario. This is a cosmetic notice from the KEDA scaler, NOT a
#     runtime error. It is captured as honest disclosure but is NOT
#     part of any gate predicate.
#   - Log Analytics ingestion lag for ContainerAppSystemLogs_CL is
#     typically 5-10 minutes from event time. This script waits
#     LOG_ANALYTICS_LAG_SECONDS (default 360s = 6min) AFTER the final
#     crash-loop deployment before issuing KQL queries, otherwise §5/§6/§9
#     would be missing the most recent metric-error events.
#   - The crash-loop scenario relies on Kubernetes-style restart backoff
#     (10s / 20s / 40s / ... exponential), so 3 cycles typically take
#     ~90-120s. CRASH_OBSERVE_SECONDS (default 180s) ensures at least
#     3 distinct restart cycles are captured before evidence collection.
#
# PII / Secret safety:
#   - This lab uses an ACR-built workload image. ACR_NAME is resolved
#     from the Bicep deployment outputs; ACR admin credentials are
#     used by the scenario helpers (trigger-scenario-{a,b,c}.sh) to
#     authenticate the Container App. The ACR_NAME generated suffix
#     (e.g. acrnometrics2aw3wk) is NOT classified as PII per the
#     AGENTS.md PII rules — it is a hash-derived name, not a real
#     account identifier.
#   - The captured report-*.txt files contain the Log Analytics
#     workspace customerId GUID in §4. A PII-scrub pass MUST be run
#     before committing the evidence (subscription/tenant GUIDs AND
#     the workspace customerId replaced with the zero-GUID placeholder,
#     operator alias replaced with demouser, employee emails replaced
#     with user@example.com, per AGENTS.md PII rules). This script
#     does NOT perform the scrub — the scrub is a manual pre-commit
#     step. The committed 2026-06-20 evidence in this repo has already
#     been scrubbed.
#
# Priority 3 comment justification (PII safety + empirical platform behavior):
#   The "no metrics returned from resource metrics API" string and the
#   "invalid metrics (1 invalid out of N)" string are LITERAL substrings
#   produced by the KEDA operator when the Kubernetes Resource Metrics
#   API returns no data. These literals appear in report-*.txt and
#   verify.sh's gate predicates match them as substrings. Future
#   operators editing this script must NOT rewrite or paraphrase these
#   literals in the KQL query in capture_app_evidence's §5/§8 sections,
#   or the gate predicates in verify.sh will silently fail.
#
# Usage:
#   export RG=rg-aca-no-metrics-lab LOCATION=koreacentral BASE_NAME=nometrics
#   az group create --name "$RG" --location "$LOCATION"
#   az deployment group create --resource-group "$RG" --name main \
#       --template-file labs/keda-no-metrics-returned/infra/main.bicep \
#       --parameters baseName="$BASE_NAME"
#   bash labs/keda-no-metrics-returned/trigger.sh
#   bash labs/keda-no-metrics-returned/verify.sh
#   bash labs/keda-no-metrics-returned/cleanup.sh

set -euo pipefail

: "${RG:?RG must be set (e.g. rg-aca-no-metrics-lab)}"

# Tunable wait windows. Default values reflect the 2026-06-20 observed
# timings with a safety margin. Override via environment if the workspace
# region or ACR is slower.
LOG_ANALYTICS_LAG_SECONDS="${LOG_ANALYTICS_LAG_SECONDS:-360}"      # 6 min for KQL ingestion lag
SLOW_OBSERVE_SECONDS="${SLOW_OBSERVE_SECONDS:-180}"                # 3 min so StartUp probe window completes (DELAY_SECONDS=120 + margin)
CRASH_OBSERVE_SECONDS="${CRASH_OBSERVE_SECONDS:-180}"              # 3 min for at least 3 crash cycles to occur
HEALTHY_OBSERVE_SECONDS="${HEALTHY_OBSERVE_SECONDS:-120}"          # 2 min for Metrics Server warm-up signal to complete
LOOKBACK="${LOOKBACK:-PT30M}"                                      # KQL lookback for evidence capture

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/evidence"
mkdir -p "$EVIDENCE_DIR"

# capture_app_evidence — produce the per-app evidence pack for one
# scenario. Writes:
#   ${EVIDENCE_DIR}/${APP_NAME}/report-${TS}.txt
#   ${EVIDENCE_DIR}/${APP_NAME}/az-version-${TS}.json
#   ${EVIDENCE_DIR}/${APP_NAME}/containerapp-extension-${TS}.json
#   ${EVIDENCE_DIR}/${APP_NAME}/revisions-${TS}.json
#   ${EVIDENCE_DIR}/${APP_NAME}/traffic-${TS}.json
#   ${EVIDENCE_DIR}/${APP_NAME}/summary-${TS}.md
#
# The report-*.txt section structure (§0-§14) is preserved verbatim from
# the 2026-06-20 canonical baseline so verify.sh's section-anchored
# predicates continue to match. DO NOT renumber the sections.
#
# Usage: capture_app_evidence "$APP_NAME"
capture_app_evidence() {
    local APP_NAME="$1"
    local APP_DIR="${EVIDENCE_DIR}/${APP_NAME}"
    mkdir -p "$APP_DIR"
    local TS
    TS="$(date -u +%Y%m%dT%H%M%SZ)"
    local REPORT="${APP_DIR}/report-${TS}.txt"

    {
        echo "========================================================"
        echo "KEDA No-Metrics-Returned Lab — Evidence Report"
        echo "========================================================"
        echo "App:       $APP_NAME"
        echo "RG:        $RG"
        echo "Lookback:  $LOOKBACK"
        echo "Timestamp: $TS"
        echo "========================================================"

        # §0. Tool versions ----------------------------------------------------
        echo
        echo "=== 0. Tool versions ==="
        az version --output json 2>/dev/null | tee "${APP_DIR}/az-version-${TS}.json" \
            || echo "(az version unavailable)"
        az extension show --name containerapp \
            --query "{name:name, version:version}" --output json 2>/dev/null \
            | tee "${APP_DIR}/containerapp-extension-${TS}.json" \
            || echo "(containerapp extension not found)"

        # §1. App configuration ------------------------------------------------
        echo
        echo "=== 1. App configuration ==="
        az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query "{name:name, location:location, provisioningState:properties.provisioningState, revisionMode:properties.configuration.activeRevisionsMode, cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas, scaleRules:properties.template.scale.rules, envVars:properties.template.containers[0].env}" \
            --output json 2>/dev/null || echo "(failed to get app config)"

        # §1b. Container name
        echo
        echo "=== 1b. Container name ==="
        local CONTAINER_NAME
        CONTAINER_NAME="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query 'properties.template.containers[0].name' --output tsv 2>/dev/null)" || true
        CONTAINER_NAME="${CONTAINER_NAME:-$APP_NAME}"
        echo "Container name: $CONTAINER_NAME"

        # §2. Active revision(s) -----------------------------------------------
        echo
        echo "=== 2. Active revision(s) ==="
        local ACTIVE_REVS ACTIVE_REV
        ACTIVE_REVS="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
            --query '[?properties.active].name' --output tsv 2>/dev/null)" || true
        ACTIVE_REV="$(echo "$ACTIVE_REVS" | head -1)"
        echo "Active revisions: ${ACTIVE_REVS:-<none>}"

        # Save revisions JSON sidecar for verify.sh consumption
        local REVISIONS_JSON
        REVISIONS_JSON="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
            --query '[?properties.active].{name:name, replicas:properties.replicas, trafficWeight:properties.trafficWeight, healthState:properties.healthState}' \
            --output json 2>/dev/null)" || true
        if [[ -n "$REVISIONS_JSON" && "$REVISIONS_JSON" != "null" ]]; then
            echo "$REVISIONS_JSON" > "${APP_DIR}/revisions-${TS}.json"
        fi

        if [[ -n "$ACTIVE_REV" ]]; then
            az containerapp revision show --name "$APP_NAME" --resource-group "$RG" \
                --revision "$ACTIVE_REV" \
                --query "{name:name, replicas:properties.replicas, active:properties.active, healthState:properties.healthState, provisioningState:properties.provisioningState, createdTime:properties.createdTime, runningState:properties.runningState}" \
                --output json
        fi

        # §2b. Traffic configuration
        echo
        echo "=== 2b. Traffic configuration ==="
        local TRAFFIC_JSON
        TRAFFIC_JSON="$(az containerapp ingress traffic show \
            --name "$APP_NAME" --resource-group "$RG" \
            --output json 2>/dev/null)" || true
        if [[ -n "$TRAFFIC_JSON" && "$TRAFFIC_JSON" != "null" ]]; then
            echo "$TRAFFIC_JSON" > "${APP_DIR}/traffic-${TS}.json"
            echo "$TRAFFIC_JSON"
        else
            echo "(no ingress traffic config)"
        fi

        # §3. Replica list ------------------------------------------------------
        echo
        echo "=== 3. Replica list (all active revisions) ==="
        local REV
        while IFS= read -r REV; do
            [[ -z "$REV" ]] && continue
            echo "--- Replicas for revision: $REV ---"
            az containerapp replica list \
                --name "$APP_NAME" --resource-group "$RG" \
                --revision "$REV" \
                --output table 2>/dev/null || echo "(no replicas for $REV)"
        done <<< "$ACTIVE_REVS"

        # §4. Log Analytics workspace ------------------------------------------
        echo
        echo "=== 4. Log Analytics workspace ==="
        local ENV_ID WORKSPACE_CUSTOMER_ID WORKSPACE_ID
        ENV_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query 'properties.managedEnvironmentId' --output tsv 2>/dev/null)" || true
        WORKSPACE_CUSTOMER_ID=""
        WORKSPACE_ID=""
        if [[ -n "$ENV_ID" ]]; then
            WORKSPACE_CUSTOMER_ID="$(az resource show --ids "$ENV_ID" \
                --query 'properties.appLogsConfiguration.logAnalyticsConfiguration.customerId' \
                --output tsv 2>/dev/null)" || true
        fi
        if [[ -n "$WORKSPACE_CUSTOMER_ID" ]]; then
            WORKSPACE_ID="$WORKSPACE_CUSTOMER_ID"
        fi
        echo "Workspace ID (customerId): ${WORKSPACE_ID:-<not resolved>}"

        # §5. System logs: metric errors ---------------------------------------
        # Predicate-bearing section. verify.sh Gate 10/11/12 sub-gates key off
        # the presence and count of "no metrics returned" / "invalid metrics"
        # entries in this section. DO NOT alter the literal substrings in the
        # KQL `has_any` clause — verify.sh's gate predicates depend on them.
        echo
        echo "=== 5. System logs: metric errors ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            echo "(Log Analytics ingestion delay: 5-10 min)"
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('no metrics returned', 'invalid metrics', 'failed to get') | project TimeGenerated, Log_s | order by TimeGenerated desc | take 30" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        else
            echo "(skipped — workspace not resolved)"
        fi

        # §6. Metric error count timeline (5-min bins) -------------------------
        # Predicate-bearing section. verify.sh Gate 11 sub-gate b counts the
        # distinct 5-min bins reported here to falsify the "single-bin
        # transient" hypothesis. DO NOT change the bin width.
        echo
        echo "=== 6. Metric error count timeline (5-min bins) ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('no metrics returned', 'invalid metrics', 'failed to get') | summarize ErrorCount=count() by bin(TimeGenerated, 5m) | order by TimeGenerated asc" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §7. DEPRECATED warnings (cosmetic, not gated) ------------------------
        echo
        echo "=== 7. System logs: DEPRECATED warnings ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('DEPRECATED', 'metricType') | project TimeGenerated, Log_s | order by TimeGenerated desc | take 10" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §8. ALL scaler/KEDA/HPA logs (broader view) --------------------------
        echo
        echo "=== 8. System logs: all scaler-related logs (last 30) ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('keda', 'scaler', 'scale', 'hpa', 'metric', 'replica') | project TimeGenerated, Log_s | order by TimeGenerated desc | take 30" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §9. Container lifecycle events ---------------------------------------
        # Predicate-bearing section. verify.sh Gate 10 sub-gate a correlates
        # "Probe of StartUp failed" entries here with the metric errors in §5
        # to prove the slow-start scenario's hypothesis. DO NOT remove the
        # "probe", "ready", or "backoff" literals from the KQL `has_any` clause.
        echo
        echo "=== 9. System logs: container lifecycle events ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('started', 'stopped', 'killed', 'backoff', 'crash', 'OOM', 'unhealthy', 'probe', 'ready', 'pulling', 'pulled') | project TimeGenerated, Log_s | order by TimeGenerated desc | take 30" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §10. Console logs (application stdout/stderr) ------------------------
        echo
        echo "=== 10. Console logs (last 30 lines) ==="
        az containerapp logs show \
            --name "$APP_NAME" --resource-group "$RG" \
            --type console --follow false --tail 30 \
            2>/dev/null || echo "(no console logs available)"

        # §11. System logs via CLI ---------------------------------------------
        echo
        echo "=== 11. System logs via CLI (last 30 lines) ==="
        az containerapp logs show \
            --name "$APP_NAME" --resource-group "$RG" \
            --type system --follow false --tail 30 \
            2>/dev/null || echo "(no system logs available or --type system not supported)"

        # §12. Azure Monitor metrics -------------------------------------------
        # §12a-f are EXPECTED to be EMPTY on first capture due to the
        # platform-metric ingestion lag (~5-10 min separate from KQL).
        # Gates 10-13 do NOT depend on §12a-f — they depend on §5/§6/§9.
        local APP_ID
        APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query id --output tsv 2>/dev/null)" || true
        if [[ -n "$APP_ID" ]]; then
            echo
            echo "=== 12a. Replica count (Max) ==="
            az monitor metrics list --resource "$APP_ID" --metric "Replicas" \
                --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 12b. Restart count (Total) ==="
            az monitor metrics list --resource "$APP_ID" --metric "RestartCount" \
                --aggregation Total --interval PT5M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 12c. Memory Percentage (Avg) ==="
            az monitor metrics list --resource "$APP_ID" --metric "MemoryPercentage" \
                --aggregation Average --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 12d. CPU Percentage (Avg) ==="
            az monitor metrics list --resource "$APP_ID" --metric "CpuPercentage" \
                --aggregation Average --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 12e. Memory Working Set Bytes (Avg) ==="
            az monitor metrics list --resource "$APP_ID" --metric "WorkingSetBytes" \
                --aggregation Average --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 12f. Request count (Total) ==="
            az monitor metrics list --resource "$APP_ID" --metric "Requests" \
                --aggregation Total --interval PT5M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
        fi

        # §13. cgroup memory.stat (EXPECTED to fail on macOS, honest disclosure)
        echo
        echo "=== 13. cgroup memory.stat from live replica ==="
        if [[ -n "$ACTIVE_REV" ]]; then
            local REPLICA
            REPLICA="$(az containerapp replica list --name "$APP_NAME" --resource-group "$RG" \
                --revision "$ACTIVE_REV" --query '[0].name' --output tsv 2>/dev/null)" || true
            if [[ -n "$REPLICA" ]]; then
                echo "Replica: $REPLICA"
                az containerapp exec \
                    --name "$APP_NAME" --resource-group "$RG" \
                    --replica "$REPLICA" --container "$CONTAINER_NAME" \
                    --command "/bin/sh -c 'echo --- memory.current ---; cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes; echo; echo --- memory.max ---; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes; echo; echo --- memory.stat (top 20 fields) ---; (cat /sys/fs/cgroup/memory.stat 2>/dev/null || cat /sys/fs/cgroup/memory/memory.stat) | head -20'" \
                    2>&1 || echo "(exec failed — replica may be initializing or crash-looping)"
            else
                echo "(no replica found — container may be restarting)"
            fi
        fi

        # §14. Activity log -----------------------------------------------------
        echo
        echo "=== 14. Activity log (resource group, last 1h) ==="
        az monitor activity-log list \
            --resource-group "$RG" --offset 1h \
            --query "[?contains(resourceId, '${APP_NAME}')] | [0:10].{time:eventTimestamp, operation:operationName.value, status:status.value, message:properties.statusMessage}" \
            --output table 2>/dev/null || echo "(no activity log entries)"

        echo
        echo "========================================================"
        echo "Evidence collection complete for $APP_NAME"
        echo "Report saved to: $REPORT"
        echo "========================================================"
        echo
        echo "Portal screenshots to capture manually:"
        echo "  1. Metrics blade → MemoryPercentage (Avg) split by Replica"
        echo "  2. Metrics blade → Replicas (Max)"
        echo "  3. Metrics blade → RestartCount (Total)"
        echo "  4. Log stream → System logs (filter: 'no metrics returned')"
        echo "  5. Revisions blade → Revision health state and replica count"
        echo
        echo "Save screenshots to: ${APP_DIR}/"
        echo "  Naming convention:"
        echo "    ${APP_NAME}-metrics-memory-percentage.png"
        echo "    ${APP_NAME}-metrics-replica-count.png"
        echo "    ${APP_NAME}-metrics-restart-count.png"
        echo "    ${APP_NAME}-system-logs-no-metrics.png"

    } 2>&1 | tee "$REPORT" >/dev/null

    # Generate summary markdown sidecar
    local LOCATION SUMMARY
    LOCATION="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
        --query location --output tsv 2>/dev/null)" || true
    SUMMARY="${APP_DIR}/summary-${TS}.md"
    cat > "$SUMMARY" <<MDEOF
# Evidence Summary: ${APP_NAME}

| Field | Value |
|-------|-------|
| App | ${APP_NAME} |
| Resource Group | ${RG} |
| Region | ${LOCATION:-unknown} |
| Timestamp | ${TS} |
| Lookback | ${LOOKBACK} |

## Collected files

- \`report-${TS}.txt\` — Full evidence report (sections §0-§14)
- \`az-version-${TS}.json\` — Azure CLI version
- \`containerapp-extension-${TS}.json\` — containerapp extension version
- \`revisions-${TS}.json\` — Active revision details
- \`traffic-${TS}.json\` — Traffic configuration

## Gate consumers (verify.sh)

- Gate 10 (slow scenario) reads §2/§5/§6/§9
- Gate 11 (crash scenario) reads §2/§5/§6
- Gate 12 (healthy scenario) reads §2/§5/§6
- Gate 13 (cross-scenario) reads §6 across all 3 scenarios
MDEOF

    echo "[capture] $APP_NAME → $REPORT"
}

echo "=== Phase 1: Resolve infra outputs ==="
ACR_NAME="$(az deployment group show \
    --resource-group "$RG" --name main \
    --query 'properties.outputs.containerRegistryName.value' --output tsv)"
ENV_NAME="$(az deployment group show \
    --resource-group "$RG" --name main \
    --query 'properties.outputs.environmentName.value' --output tsv)"
# WORKSPACE_CUSTOMER_ID is read off the Container Apps Environment so we
# do not have to know the workspace resource name separately.
WORKSPACE_CUSTOMER_ID="$(az containerapp env show \
    --name "$ENV_NAME" --resource-group "$RG" \
    --query 'properties.appLogsConfiguration.logAnalyticsConfiguration.customerId' --output tsv)"
export RG ACR_NAME ENV_NAME

echo "[Phase 1] ACR_NAME=$ACR_NAME ENV_NAME=$ENV_NAME"
echo "[Phase 1] WORKSPACE_CUSTOMER_ID=<resolved, redacted from stdout>"

echo "=== Phase 2: Pre-build workload image (one image, three deployments) ==="
# The scenario helpers each run `az acr build` independently; for the
# canonical orchestration we let them each rebuild because the image
# build is fast (~30s) and we want each helper to be reproducible
# stand-alone. No-op here.
echo "[Phase 2] Image build is performed by each scenario helper (idempotent)"

echo "=== Phase 3: Deploy Scenario C (healthy baseline) FIRST ==="
# Healthy first so the Metrics Server warm-up signal is captured cleanly
# without interference from the failing scenarios that may saturate the
# system-log path. The control case anchors Gate 12.
bash "${SCRIPT_DIR}/trigger-scenario-c.sh"
echo "[Phase 3] Healthy deploy complete; waiting ${HEALTHY_OBSERVE_SECONDS}s for warm-up signal"
sleep "$HEALTHY_OBSERVE_SECONDS"

echo "=== Phase 4: Deploy Scenario A (slow-start) ==="
bash "${SCRIPT_DIR}/trigger-scenario-a.sh"
echo "[Phase 4] Slow-start deploy complete; waiting ${SLOW_OBSERVE_SECONDS}s for StartUp probe window"
sleep "$SLOW_OBSERVE_SECONDS"

echo "=== Phase 5: Deploy Scenario B (crash-loop) ==="
bash "${SCRIPT_DIR}/trigger-scenario-b.sh"
echo "[Phase 5] Crash-loop deploy complete; waiting ${CRASH_OBSERVE_SECONDS}s for >=3 crash cycles"
sleep "$CRASH_OBSERVE_SECONDS"

echo "=== Phase 6: Wait ${LOG_ANALYTICS_LAG_SECONDS}s for Log Analytics ingestion ==="
# ContainerAppSystemLogs_CL has a 5-10 minute ingestion lag from event
# time. We must wait before issuing KQL queries against the most recent
# events, otherwise §5/§6/§9 would be missing the crash-loop tail.
sleep "$LOG_ANALYTICS_LAG_SECONDS"

echo "=== Phase 7: Capture per-scenario evidence packs ==="
# Capture order matches the deploy order so the report-*.txt timestamps
# preserve the scenario lineage. Each capture produces ~7 files in its
# evidence subdirectory.
capture_app_evidence "ca-nometrics-healthy"
capture_app_evidence "ca-nometrics-slow"
capture_app_evidence "ca-nometrics-crash"

echo ""
echo "=== Trigger complete ==="
echo "Evidence root: $EVIDENCE_DIR"
echo "Subdirectories:"
echo "  ca-nometrics-healthy/  (Gate 12 inputs)"
echo "  ca-nometrics-slow/     (Gate 10 inputs)"
echo "  ca-nometrics-crash/    (Gate 11 inputs)"
echo "Next step: run verify.sh to emit gates 10..13 (pure file processor — no Azure calls)."
echo ""
echo "PII safety reminder: Before committing this evidence, run the PII"
echo "scrub pass per AGENTS.md (subscription/tenant GUIDs AND the workspace"
echo "customerId replaced with 00000000-0000-0000-0000-000000000000;"
echo "operator alias replaced with demouser; employee emails replaced with"
echo "user@example.com)."
