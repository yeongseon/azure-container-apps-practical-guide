#!/usr/bin/env bash
# trigger.sh — Phase B evidence-pack orchestrator for Lab 17 (memory-leak-oomkilled).
#
# Reproduces the cross-scenario differential evidence pack that proves:
#   H1.a (hard):    A workload that allocates beyond the cgroup memory ceiling
#                   at startup produces an IMMEDIATE, DENSE OOM burst signature
#                   distinct from a gradual leak.
#   H1.b (leak):    A workload that allocates +30 MiB / 20s in a background
#                   thread produces a DELAYED OOM signature with a measurable
#                   memory runway (monotonic tick prints in console logs)
#                   PRECEDING the OOM, distinct from a hard OOM.
#   H2 (healthy):   A workload with the same image and platform shape but
#                   without an allocation path produces ZERO OOM records,
#                   falsifying the hypothesis that the OOMs are environmental
#                   (image, platform, region, ACR, scaling rules).
#   H3 (cross):     The three workload patterns produce THREE DISTINGUISHABLE
#                   OOM signatures (hard ≫ leak > healthy=0), and the
#                   distinguishability is preserved across reasonable timing
#                   variations on a fresh re-run.
#
# Orchestrates the same 3-scenario evidence capture observed on 2026-06-20:
#   Scenario A (hard):    ca-oom-hard    — MODE=hard-oom (allocate 600 MiB at startup)
#                         Revision is briefly Healthy after the fix, but the
#                         OOM burst signature persists in §5/§6 of the report
#                         captured BEFORE the fix. Canonical capture set:
#                         3 timestamps (041900Z, 042113Z, 060257Z), the last
#                         AFTER trigger-fix.sh was applied.
#                         Canonical OOM record count on 2026-06-20 (060257Z):
#                         16 records in §5 spanning 04:41:48 → 05:56:58 UTC,
#                         max 5-min bin = 26 events @ 04:10 UTC.
#   Scenario B (leak):    ca-oom-leak    — MODE=leak (+30 MiB / 20s background thread)
#                         Revision is Healthy/RunningAtMaxScale because the
#                         leak runs in a background thread that does not block
#                         the HTTP server. The kernel OOM killer eventually
#                         hits the cgroup ceiling around tick 12-16.
#                         Canonical capture set: 2 timestamps (041947Z, 042200Z).
#                         Canonical leak progression on 2026-06-20 (042200Z):
#                         16 ticks (1→16) printed monotonically with retained
#                         memory climbing 30→480 MiB, +1 prior-cycle OOM in §5.
#   Scenario C (healthy): ca-oom-healthy — MODE=healthy (no allocations)
#                         Revision is Healthy/RunningAtMaxScale steady-state.
#                         No OOM records in §5 (strict predicate). §6 contains
#                         14 events on a 5-min bin that are FALSE POSITIVES
#                         from the broad `has_any 'memory'` KQL clause — they
#                         are not OOM records, just memory-related stdout/log
#                         lines. This false-positive is why Gate 12 uses §5
#                         record-scoped predicates, not §6 bin counts.
#                         Canonical capture set: 2 timestamps (042045Z, 042246Z).
#
# Phases (driven by a SINGLE script — no manual operator steps):
#   Phase 1 — Resolve infra outputs (RG, ENV_NAME, ACR_NAME, WORKSPACE_CUSTOMER_ID)
#   Phase 2 — Build the workload image once via az acr build (one image,
#             three deployments — MODE is set per-scenario via env vars)
#   Phase 3 — Deploy Scenario C (healthy baseline) FIRST so that the steady-
#             state metric and log baseline is captured cleanly without
#             interference from the OOMing scenarios
#   Phase 4 — Deploy Scenario A (hard-oom) and wait ~3 cycles of CrashLoopBackOff
#             so the dense OOM burst spans multiple 5-min bins
#   Phase 5 — Deploy Scenario B (leak) and wait LEAK_OBSERVE_SECONDS so the
#             memory runway climbs to the cgroup ceiling and produces at least
#             one OOM after the monotonic tick prints
#   Phase 6 — Apply trigger-fix.sh to Scenario A and wait FIX_OBSERVE_SECONDS
#             so the new revision reaches Healthy/RunningAtMaxScale
#   Phase 7 — Wait LOG_ANALYTICS_LAG_SECONDS (360s) for ingestion
#   Phase 8 — Capture per-scenario evidence (report-${TS}.txt + sidecar
#             JSONs) for all 3 apps. The capture is performed by an
#             inline function (capture_app_evidence) rather than by
#             verify.sh, because verify.sh is now a pure file processor.
#
# Option Y trigger pattern (per Oracle Lab 17 strategy review, FRESH
# session bg_97bdbde7, verdict 2026-06-24):
#   trigger.sh OWNS the canonical evidence run AND invokes the existing
#   trigger-scenario-{a,b,c}.sh helpers AND trigger-fix.sh sequentially.
#   The scenario helpers are PRESERVED (not deleted) so an operator who
#   wants to reproduce a SINGLE scenario can still do so. verify.sh
#   becomes a PURE FILE PROCESSOR that reads the captures this script
#   writes and emits the 4 gate JSONs. It does not call Azure.
#
# Strict record-scoped predicate boundary (per Oracle Option γ, Lab 15
# strategy review carried forward to Lab 17):
#   The evidence captures (report-*.txt + revisions-*.json) are the ONLY
#   inputs verify.sh sees. verify.sh does not re-issue any az or KQL
#   calls. This script is the only side-effect script in this lab.
#   Re-running the canonical evidence requires running this script.
#
# Evidence reuse policy (per Oracle Lab 17 directive):
#   The 2026-06-20 canonical evidence is the BASELINE. The committed
#   evidence files under evidence/ca-oom-{hard,healthy,leak}/ are the
#   artifacts verify.sh reads. This script EXISTS so that the capture
#   choreography is reproducible — running it would OVERWRITE the
#   2026-06-20 captures with a new TS. Operators reproducing the lab
#   from scratch will run this script; the committed 2026-06-20
#   evidence is preserved as the canonical baseline and is NOT
#   regenerated by normal CI runs.
#
# Empirical platform behavior captured during the 2026-06-20 live run
# (preserved verbatim in evidence/README.md "Honest disclosure" section):
#   - The §10c cgroup capture in report-*.txt is EXPECTED to be EMPTY
#     when the operator runs this script from macOS, because
#     `az containerapp exec` spawns a PTY via tty.setcbreak() which is
#     "Operation not supported by device" outside of an interactive
#     terminal. The Gate 12 sub-gate (c) uses RUNNING_STATE/REPLICAS
#     sidecar substitution (instead of the cgroup-derived RestartCount)
#     because §10c is reliably empty on a macOS capture path. Gates
#     10/11/12/13 do NOT depend on §10c being populated.
#   - The §6 5-min bin histogram for the HEALTHY scenario contains
#     ~14 events because the KQL query uses a BROAD `Log_s has_any
#     ('memory', 'oom', 'oomkilled', 'killed', 'exit code', '137')`
#     clause that matches NON-OOM memory-related stdout (e.g. the
#     workload's "memory baseline" startup message, "free memory"
#     diagnostics, etc.). This is a FALSE POSITIVE on the bin counter
#     — when filtered to the STRICT OOM predicate (form A: Reason_s ==
#     ContainerTerminated AND Log_s contains 'exit code 137' AND Log_s
#     contains 'ProcessExited'; form B: Reason_s == ProcessExited AND
#     Log_s contains 'exit code 137'), §5 has 0 records for healthy.
#     This is why Gate 12 uses STRICT §5 record-scoped predicates and
#     NEVER uses §6 bin counts as a healthy/non-healthy discriminator.
#   - The §5 KQL query in the historical capture has a `take 50` limit
#     to keep the report bounded. For the HARD scenario this means the
#     initial OOM burst (first 30-60s after revision creation) may be
#     PARTIALLY missing from §5 if the cycle 1 OOMs were already pushed
#     out by cycle 2+ OOMs. This is why Gate 10's sub-gate (a) has a
#     FALLBACK PATH: §5 strict record count ≥ 10 (STRONG) OR §6 max
#     5-min bin ≥ 10 (FALLBACK). The max-bin path captures the burst
#     density even when §5 has been truncated.
#   - The LEAK scenario's §7 console-log section contains the
#     monotonic tick prints `F [leak] tick N: +30 MiB, total retained
#     K MiB`. Tick 1 is CONCATENATED with the gunicorn listening
#     message on the same line (`F [app] listening on :8000[leak]
#     tick 1: +30 MiB, total retained 30 MiB`). The Gate 11 §7 parser
#     uses regex `search()` (not `match()`) so the concatenation does
#     not break the tick extraction.
#   - The HARD scenario was captured at THREE timestamps because the
#     operator ran verify.sh twice before applying the fix (041900Z,
#     042113Z — both PRE-fix) and once after the fix (060257Z —
#     POST-fix). The LATEST snapshot (060257Z) is the canonical one
#     per Oracle directive ("Use the latest canonical report per
#     scenario") because it reflects the eventual Healthy state of
#     the fixed revision. The earlier two snapshots are preserved as
#     part of the 35 historical artifacts.
#   - The HEALTHY scenario was captured at TWO timestamps (042045Z,
#     042246Z). 042045Z is missing its summary-*.md file (the historical
#     verify.sh from this lab had the same `cat <<MDEOF` bug as Lab 16
#     pre-Phase-B — the heredoc was inside a tee pipe and lost the
#     LOCATION variable). The 042246Z snapshot is the canonical one
#     per Oracle directive.
#   - The LEAK scenario was captured at TWO timestamps (041947Z,
#     042200Z). The 042200Z snapshot is the canonical one per Oracle
#     directive. It contains 16 monotonic ticks (1→16) in §7 with
#     retained memory climbing 30 → 480 MiB, plus 1 OOM record in §5
#     from a PREVIOUS leak cycle (the leak workload restarts after
#     each OOM and the previous cycle's exit-137 line is still inside
#     the 30-minute lookback window). The Gate 11 sub-gate predicate
#     accepts ≥1 OOM record (not "exactly 1") so this multi-cycle
#     overlap does not falsify the gate.
#
# PII / Secret safety:
#   - This lab uses an ACR-built workload image. ACR_NAME is resolved
#     from the Bicep deployment outputs; ACR admin credentials are
#     used by the scenario helpers (trigger-scenario-{a,b,c}.sh) to
#     authenticate the Container App. The ACR_NAME generated suffix
#     (e.g. acrmemleak6dnnsj) is NOT classified as PII per the
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
#   The "exit code '137'" string, the "ContainerTerminated" reason value,
#   and the "ProcessExited" reason value are LITERAL substrings produced
#   by the Container Apps platform when a container is killed by the
#   kernel OOM killer (SIGKILL → exit 137). These literals appear in
#   report-*.txt and verify.sh's record-scoped OOM predicate matches
#   them via §5's `Log_s` and `Reason_s` columns. Future operators
#   editing this script must NOT rewrite or paraphrase these literals
#   in the KQL query in capture_app_evidence's §5 section, or the gate
#   predicates in verify.sh will silently fail. Similarly the `[leak]
#   tick N: +30 MiB, total retained K MiB` print format produced by
#   workload/app.py MUST NOT be reformatted — Gate 11's tick regex
#   `r'\[leak\] tick (\d+): \+30 MiB, total retained (\d+) MiB'` is
#   exact-match on this format.
#
# Usage:
#   export RG=rg-aca-memleak-lab LOCATION=koreacentral BASE_NAME=memleak
#   az group create --name "$RG" --location "$LOCATION"
#   az deployment group create --resource-group "$RG" --name main \
#       --template-file labs/memory-leak-oomkilled/infra/main.bicep \
#       --parameters baseName="$BASE_NAME"
#   bash labs/memory-leak-oomkilled/trigger.sh
#   bash labs/memory-leak-oomkilled/verify.sh
#   bash labs/memory-leak-oomkilled/cleanup.sh

set -euo pipefail

: "${RG:?RG must be set (e.g. rg-aca-memleak-lab)}"

# Tunable wait windows. Default values reflect the 2026-06-20 observed
# timings with a safety margin. Override via environment if the workspace
# region or ACR is slower.
LOG_ANALYTICS_LAG_SECONDS="${LOG_ANALYTICS_LAG_SECONDS:-360}"      # 6 min for KQL ingestion lag
HEALTHY_OBSERVE_SECONDS="${HEALTHY_OBSERVE_SECONDS:-90}"           # 90s for the healthy baseline to start serving
HARD_OBSERVE_SECONDS="${HARD_OBSERVE_SECONDS:-180}"                # 3 min for >=3 hard-OOM restart cycles
LEAK_OBSERVE_SECONDS="${LEAK_OBSERVE_SECONDS:-600}"                # 10 min for the leak to reach the cgroup ceiling (~16 ticks × 20s = 320s + safety)
FIX_OBSERVE_SECONDS="${FIX_OBSERVE_SECONDS:-90}"                   # 90s for the fix revision to reach Healthy
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
#   ${EVIDENCE_DIR}/${APP_NAME}/summary-${TS}.md
#
# The report-*.txt section structure (§0-§14) is preserved verbatim from
# the 2026-06-20 canonical baseline so verify.sh's section-anchored
# predicates continue to match. DO NOT renumber the sections. The §5
# 4-column fixed-width format (Log_s | Reason_s | TableName |
# TimeGenerated) is also preserved verbatim — verify.sh's record-scoped
# OOM predicate splits each §5 row on `\s{2,}` (2+ spaces) to extract
# the four fields, and rewriting the KQL `project` clause would break
# that split.
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
        echo "Memory Leak / OOMKilled Lab — Evidence Report"
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
            --query "{name:name, location:location, provisioningState:properties.provisioningState, revisionMode:properties.configuration.activeRevisionsMode, cpu:properties.template.containers[0].resources.cpu, memory:properties.template.containers[0].resources.memory, minReplicas:properties.template.scale.minReplicas, maxReplicas:properties.template.scale.maxReplicas, envVars:properties.template.containers[0].env}" \
            --output json 2>/dev/null || echo "(failed to get app config)"

        # §1b. Container name --------------------------------------------------
        echo
        echo "=== 1b. Container name ==="
        local CONTAINER_NAME
        CONTAINER_NAME="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query 'properties.template.containers[0].name' --output tsv 2>/dev/null)" || true
        CONTAINER_NAME="${CONTAINER_NAME:-$APP_NAME}"
        echo "Container name: $CONTAINER_NAME"

        # §2. Active revision(s) -----------------------------------------------
        # Predicate-bearing section. verify.sh Gate 10/11/12 sub-gate (c)
        # reads the sidecar revisions-*.json (healthState, runningState,
        # replicas, trafficWeight) AND the §2 inline JSON for fields the
        # sidecar does not carry. DO NOT remove the inline `az containerapp
        # revision show` block — it is the only source of `runningState`
        # and the `provisioningState` value on the active revision.
        echo
        echo "=== 2. Active revision(s) ==="
        local ACTIVE_REVS ACTIVE_REV
        ACTIVE_REVS="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
            --query '[?properties.active].name' --output tsv 2>/dev/null)" || true
        ACTIVE_REV="$(echo "$ACTIVE_REVS" | head -1)"
        echo "Active revisions: ${ACTIVE_REVS:-<none>}"

        # Save revisions JSON sidecar for verify.sh consumption.
        # Schema: {healthState, name, replicas, runningState, trafficWeight}
        # verify.sh Gate 10/11/12 sub-gate (c) reads healthState + runningState
        # + replicas. trafficWeight is captured for cross-validation with §2b.
        local REVISIONS_JSON
        REVISIONS_JSON="$(az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
            --query '[?properties.active].{name:name, replicas:properties.replicas, trafficWeight:properties.trafficWeight, healthState:properties.healthState, runningState:properties.runningState}' \
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

        # §5. System logs: OOM record table (4-column fixed-width) -------------
        # PREDICATE-BEARING SECTION (CRITICAL). verify.sh Gate 10/11/12
        # sub-gate (a) parses every row of this section with `re.split(r'\s{2,}')`
        # to extract 4 fields: Log_s | Reason_s | TableName | TimeGenerated.
        # The 2-form OOM record predicate then matches:
        #   FORM A: Reason_s == 'ContainerTerminated' AND
        #           Log_s contains "exit code '137'" AND
        #           Log_s contains 'ProcessExited'
        #   FORM B: Reason_s == 'ProcessExited' AND
        #           Log_s contains "exit code '137'"
        # DO NOT alter the KQL `project` clause column order or the
        # `take 50` limit without updating verify.sh's column parser.
        # The `take 50` limit is intentional — the initial OOM burst
        # for the HARD scenario may be PARTIALLY missing from §5 if
        # cycle 1 OOMs were pushed out by cycle 2+, which is why
        # Gate 10's sub-gate (a) has a §6 fallback path.
        echo
        echo "=== 5. System logs: OOM record table (4-column fixed-width) ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            echo "(Log Analytics ingestion delay: 5-10 min)"
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('exit code', '137', 'OOMKilled', 'ProcessExited') | where Reason_s in ('ContainerTerminated', 'ProcessExited') | project Log_s, Reason_s, TableName=Type, TimeGenerated | order by TimeGenerated desc | take 50" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        else
            echo "(skipped — workspace not resolved)"
        fi

        # §6. OOM event 5-min bin histogram ------------------------------------
        # PREDICATE-BEARING SECTION (with FALSE-POSITIVE caveat for HEALTHY).
        # verify.sh Gate 10 sub-gate (a) FALLBACK path uses the max 5-min bin
        # count from this histogram (≥10 events). Gate 10 sub-gate (b) STRONG
        # path uses the same max bin (≥10 events) to discriminate hard from
        # leak. The HEALTHY scenario's §6 contains ~14 FALSE-POSITIVE events
        # because this KQL uses a BROAD `has_any` clause that matches
        # non-OOM memory-related stdout. This is documented in the
        # capture comment and in evidence/README.md. Gate 12 (healthy) does
        # NOT use §6 — it uses §5 strict record-scoped predicates only.
        echo
        echo "=== 6. OOM event 5-min bin histogram ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('memory', 'oom', 'oomkilled', 'killed', 'exit code', '137') | summarize EventCount=count() by bin(TimeGenerated, 5m) | order by TimeGenerated asc" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §7. Console logs (application stdout/stderr) -------------------------
        # PREDICATE-BEARING SECTION FOR LEAK SCENARIO. verify.sh Gate 11
        # sub-gate (a) STRONG path parses this section with regex
        # `r'\[leak\] tick (\d+): \+30 MiB, total retained (\d+) MiB'` and
        # requires ≥12 monotonic ticks. The regex uses `search()` (not
        # `match()`) because tick 1 is CONCATENATED with the gunicorn
        # listening message on the same line. DO NOT change the `--tail
        # 100` value without checking that >=16 leak ticks still fit.
        # The HEALTHY and HARD scenarios use this section for context
        # only; no gate predicate keys off their console output.
        echo
        echo "=== 7. Console logs (last 100 lines, JSON for leak tick parsing) ==="
        az containerapp logs show \
            --name "$APP_NAME" --resource-group "$RG" \
            --type console --follow false --tail 100 \
            --format json 2>/dev/null || echo "(no console logs available)"

        # §8. System logs via CLI ----------------------------------------------
        echo
        echo "=== 8. System logs via CLI (last 30 lines) ==="
        az containerapp logs show \
            --name "$APP_NAME" --resource-group "$RG" \
            --type system --follow false --tail 30 \
            2>/dev/null || echo "(no system logs available or --type system not supported)"

        # §9. Container lifecycle events ---------------------------------------
        echo
        echo "=== 9. System logs: container lifecycle events ==="
        if [[ -n "$WORKSPACE_ID" ]]; then
            az monitor log-analytics query \
                --workspace "$WORKSPACE_ID" \
                --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '${APP_NAME}' | where Log_s has_any ('started', 'stopped', 'killed', 'backoff', 'crash', 'OOM', 'unhealthy', 'probe', 'ready', 'pulling', 'pulled') | project TimeGenerated, Log_s | order by TimeGenerated desc | take 30" \
                --output table 2>/dev/null || echo "(query failed or no results yet)"
        fi

        # §10. Azure Monitor metrics + cgroup diagnostics ----------------------
        # §10a-b are platform metrics (Memory %, Working Set Bytes).
        # §10c is a cgroup memory.stat capture via `az containerapp exec`.
        # §10c is EXPECTED to be EMPTY on macOS captures because PTY
        # allocation fails (see honest disclosure in evidence/README.md).
        # Gates 10/11/12/13 do NOT depend on §10c.
        local APP_ID
        APP_ID="$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
            --query id --output tsv 2>/dev/null)" || true
        if [[ -n "$APP_ID" ]]; then
            echo
            echo "=== 10a. Memory Percentage (Max) ==="
            az monitor metrics list --resource "$APP_ID" --metric "MemoryPercentage" \
                --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
            echo
            echo "=== 10b. Working Set Bytes (Max) ==="
            az monitor metrics list --resource "$APP_ID" --metric "WorkingSetBytes" \
                --aggregation Maximum --interval PT1M --offset "$LOOKBACK" \
                --output table 2>/dev/null || true
        fi
        echo
        echo "=== 10c. cgroup memory.stat from live replica ==="
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
                    2>&1 || echo "(exec failed — replica may be initializing, crash-looping, or PTY allocation unsupported on this host)"
            else
                echo "(no replica found — container may be restarting)"
            fi
        fi

        # §11. Activity log ----------------------------------------------------
        echo
        echo "=== 11. Activity log (resource group, last 1h) ==="
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
        echo "  1. Metrics blade → MemoryPercentage (Max) split by Replica"
        echo "  2. Metrics blade → WorkingSetBytes (Max) — leak runway"
        echo "  3. Metrics blade → RestartCount (Total) — restart cliff"
        echo "  4. Log stream → System logs (filter: 'exit code 137')"
        echo "  5. Revisions blade → Revision health state and replica count"
        echo
        echo "Save screenshots to: ${APP_DIR}/"
        echo "  Naming convention:"
        echo "    ${APP_NAME}-metrics-memory-percentage.png"
        echo "    ${APP_NAME}-metrics-working-set-bytes.png"
        echo "    ${APP_NAME}-metrics-restart-count.png"
        echo "    ${APP_NAME}-system-logs-exit-137.png"

    } 2>&1 | tee "$REPORT" >/dev/null

    # Generate summary markdown sidecar OUTSIDE the tee pipe above. Variable
    # interpolation (LOCATION, RG, TS) only works in this scope; embedding the
    # heredoc inside the piped { ... } block silently produces a 0-byte file
    # because the subshell loses access to LOCATION before MDEOF expands.
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

- \`report-${TS}.txt\` — Full evidence report (sections §0-§11)
- \`az-version-${TS}.json\` — Azure CLI version
- \`containerapp-extension-${TS}.json\` — containerapp extension version
- \`revisions-${TS}.json\` — Active revision details

## Gate consumers (verify.sh)

- Gate 10 (hard scenario) reads §2/§5/§6 + sidecar revisions
- Gate 11 (leak scenario) reads §2/§5/§7 + sidecar revisions
- Gate 12 (healthy scenario) reads §2/§5 + sidecar revisions (NOT §6 due to false positive)
- Gate 13 (cross-scenario) reads §2/§5 across all 3 scenarios + sidecar revisions
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
WORKSPACE_CUSTOMER_ID="$(az containerapp env show \
    --name "$ENV_NAME" --resource-group "$RG" \
    --query 'properties.appLogsConfiguration.logAnalyticsConfiguration.customerId' --output tsv)"
export RG ACR_NAME ENV_NAME

echo "[Phase 1] ACR_NAME=$ACR_NAME ENV_NAME=$ENV_NAME"
echo "[Phase 1] WORKSPACE_CUSTOMER_ID=<resolved, redacted from stdout>"

echo "=== Phase 2: Pre-build workload image (one image, three deployments) ==="
# The scenario helpers each run `az acr build` independently. The build is
# fast (~30s, single-stage python:3.11-slim) so we let each helper rebuild
# rather than caching across runs. Each helper is reproducible stand-alone.
echo "[Phase 2] Image build is performed by each scenario helper (idempotent)"

echo "=== Phase 3: Deploy Scenario C (healthy baseline) FIRST ==="
# Healthy first so the steady-state baseline is captured cleanly without
# interference from the OOMing scenarios that may saturate the system-log
# path. The control case anchors Gate 12.
bash "${SCRIPT_DIR}/trigger-scenario-c.sh"
echo "[Phase 3] Healthy deploy complete; waiting ${HEALTHY_OBSERVE_SECONDS}s for steady-state"
sleep "$HEALTHY_OBSERVE_SECONDS"

echo "=== Phase 4: Deploy Scenario A (hard-oom) ==="
# Hard OOM second so its dense burst signature is captured while the leak
# scenario has not yet started accruing its own OOM records, simplifying
# the cross-scenario differential at evidence capture time.
bash "${SCRIPT_DIR}/trigger-scenario-a.sh"
echo "[Phase 4] Hard-OOM deploy complete; waiting ${HARD_OBSERVE_SECONDS}s for >=3 restart cycles"
sleep "$HARD_OBSERVE_SECONDS"

echo "=== Phase 5: Deploy Scenario B (leak) ==="
# Leak last because it takes ~10 min to reach the cgroup ceiling. Deploying
# it last means the LEAK_OBSERVE_SECONDS wait overlaps with the natural
# Log Analytics ingestion lag, reducing total wall-clock time.
bash "${SCRIPT_DIR}/trigger-scenario-b.sh"
echo "[Phase 5] Leak deploy complete; waiting ${LEAK_OBSERVE_SECONDS}s for >=12 ticks + 1 OOM"
sleep "$LEAK_OBSERVE_SECONDS"

echo "=== Phase 6: Apply fix to Scenario A ==="
# trigger-fix.sh changes Scenario A's MODE from hard-oom to healthy and
# raises memory from 0.5Gi to 1.0Gi. This produces a new revision that
# reaches Healthy. The OLD failing revision is preserved (visible in the
# Revisions blade) for post-incident review. The capture phase below
# captures the POST-fix state of ca-oom-hard, which is why Gate 10
# sub-gate (c) accepts the fixed Healthy state as valid evidence that
# the fix was applied — the OOM burst signature in §5/§6 still proves
# the hypothesis even though the current state is Healthy.
bash "${SCRIPT_DIR}/trigger-fix.sh"
echo "[Phase 6] Fix applied; waiting ${FIX_OBSERVE_SECONDS}s for new revision to reach Healthy"
sleep "$FIX_OBSERVE_SECONDS"

echo "=== Phase 7: Wait ${LOG_ANALYTICS_LAG_SECONDS}s for Log Analytics ingestion ==="
# ContainerAppSystemLogs_CL has a 5-10 minute ingestion lag from event
# time. We must wait before issuing KQL queries against the most recent
# events, otherwise §5/§6/§9 would be missing the most recent OOM records.
sleep "$LOG_ANALYTICS_LAG_SECONDS"

echo "=== Phase 8: Capture per-scenario evidence packs ==="
# Capture order matches the deploy order so the report-*.txt timestamps
# preserve the scenario lineage. Each capture produces 5 files in its
# evidence subdirectory: report-*.txt, az-version-*.json,
# containerapp-extension-*.json, revisions-*.json, summary-*.md.
capture_app_evidence "ca-oom-healthy"
capture_app_evidence "ca-oom-hard"
capture_app_evidence "ca-oom-leak"

echo ""
echo "=== Trigger complete ==="
echo "Evidence root: $EVIDENCE_DIR"
echo "Subdirectories:"
echo "  ca-oom-healthy/  (Gate 12 inputs)"
echo "  ca-oom-hard/     (Gate 10 inputs, POST-fix state)"
echo "  ca-oom-leak/     (Gate 11 inputs)"
echo "Next step: run verify.sh to emit gates 10..13 (pure file processor — no Azure calls)."
echo ""
echo "PII safety reminder: Before committing this evidence, run the PII"
echo "scrub pass per AGENTS.md (subscription/tenant GUIDs AND the workspace"
echo "customerId replaced with 00000000-0000-0000-0000-000000000000;"
echo "operator alias replaced with demouser; employee emails replaced with"
echo "user@example.com)."
