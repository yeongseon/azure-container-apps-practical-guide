# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `memory-percentage-vs-keda-utilization` lab run on **2026-06-24**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens such as `customDomainVerificationId` replaced with `AAAA…A` placeholders, local user paths replaced with `/Users/demouser`).

## Capture timeline

The lab evidence was captured in a single live-Azure window on **2026-06-24** against three side-by-side Container Apps in RG `rg-aca-lab-mempct2` (Korea Central):

- **Trigger Phase 1–5 (01:54 UTC).** `trigger.sh` resolved infrastructure (ACR `acrmempct4xuaob`, ACA environment `cae-mempct-4xuaob`, image `mempct:v1` digest `sha256:a5523f8d…`), recorded the image manifest, and created three Container Apps that share the IDENTICAL memory scale rule (`Utilization=50`, `min=2`, `max=20`, CPU `0.5`, memory `1.0Gi`) but exercise different workload mixes via env vars:
    - `ca-mempct-a-below` (`MODE=rss`, `TARGET_MB=400`, expected per-replica ~40%)
    - `ca-mempct-b-above` (`MODE=rss`, `TARGET_MB=560`, expected per-replica ~56%)
    - `ca-mempct-cache` (`MODE=cache`, `TARGET_MB=700`, expected ~72% cache-heavy)

- **Trigger Phase 6 (01:55–02:15 UTC, 1200 s).** A bounded 20-minute wait window with elapsed markers logged every 120 s, sized so the HPA controller has time to walk both the rss-dominant `B` app from `2 → 20` and the cache-heavy `C` app to its steady plateau, then stabilize for at least 10 consecutive minutes inside the metric-list window.

- **Trigger Phase 7–18 (02:21–02:23 UTC).** Per-scenario captures: revisions list, `Replicas (Maximum)` metric (15-min lookback, PT1M interval, ~30 samples), `MemoryPercentage (Average)` metric (same window, ~25 samples after KEDA controller publishing delay), and an initial cgroup capture attempt against the active replica of each app. The metric pulls explicitly carry both `--start-time` and `--end-time` (computed up front from `date -u`) because az-cli 2.79.0 raises a `TypeError` inside `list_metrics` when `--offset PT15M` is passed alone — see honest disclosure below.

- **Cgroup re-capture window (02:28–02:31 UTC).** The initial cgroup captures in Phase 7–18 used a single combined heredoc that did not survive pseudo-tty wrapping cleanly; the three cgroup files were re-captured as **three separate `az containerapp exec` invocations per app** (`memory.usage_in_bytes`, `memory.limit_in_bytes`, `memory.stat`), with a 20-second sleep between calls to avoid HTTP 429 throttling, and stored under three separate JSON keys (`memory_usage_in_bytes_raw`, `memory_limit_in_bytes_raw`, `memory_stat_raw`). The refactored `capture_cgroup_file` helper in `trigger.sh` now performs this capture pattern on the first attempt — see honest disclosure below for the reproducibility implications.

- **Trigger Phase 19–21 (02:23 UTC).** CLI versions, container apps extension metadata, and region/subscription/tenant context captured for evidence completeness.

- **Verify window (02:40 UTC).** `verify.sh` operates as a pure file processor against `evidence/01-*` through `evidence/18-*` (no Azure calls — fully replayable from disk). It computes four falsifiable sub-gates evaluated against a strict 2-path predicate (Strong path + Fallback path; the Strong path matches the exact lab specification, the Fallback path tolerates the same controlling behavior under minor numeric drift). All four gates were emitted with `utc_captured: 2026-06-24T02:40:09Z`:
    - `22-h1-scenario-a-gate.json` → `scenario_a_held_at_floor_rss_dominant` (5/5 sub-gates PASS)
    - `23-h1-scenario-b-gate.json` → `scenario_b_walked_to_max_rss_dominant` (5/5 sub-gates PASS)
    - `24-h1-scenario-c-gate.json` → `scenario_c_stalled_despite_overtarget_cache_dominant` (5/5 sub-gates PASS)
    - `25-h2-differential-gate.json` → `portal_mempct_diverges_from_keda_scaler_input_for_cache_heavy_workloads` (6/6 sub-gates PASS)

- **Async cleanup (02:37:45 UTC, before verify completion).** `cleanup.sh` was kicked off with `az group delete --no-wait --yes`; the resource group entered `Deleting` state before `verify.sh` finished, confirming that `verify.sh` operates on the disk-captured evidence only and does not require live Azure access.

All four gates pass on the Strong path with no Fallback-path fallback required. The differential between the three scenarios — `A` held at the floor of 2 replicas with rss-dominant cgroup composition, `B` walked all the way to `maxReplicas=20` with rss-dominant cgroup composition, `C` held at the floor of 2 replicas despite a Portal `MemoryPercentage` of 72% with cache-dominant cgroup composition — is the cross-scenario proof that the Portal `MemoryPercentage` value does NOT cleanly map to the KEDA memory scaler input for cache-heavy workloads.

## Cross-scenario differential proof — why this is not a fake-fix lab

This lab does NOT have a "before/after fix" structure because there is nothing to fix. The platform behavior on display (HPA ceiling math + page-cache inflation in the Portal metric) is by design at both the KEDA and Azure Monitor layers. The H2 cross-scenario differential gate (`25-h2-differential-gate.json`) therefore proves the lab's hypothesis by comparing three side-by-side scenarios with one controlled variable per pair:

- **A → B (workload-mode held constant at `rss`):** isolates the HPA ceiling effect. Both apps source the same metric (rss-dominant working set), but the per-replica value crosses `50` in `B` and not in `A`, so the HPA formula `ceil(N × value / 50)` only increments above `N` for `B`. The fact that `B` reaches `maxReplicas=20` while `A` stays at floor `2` proves the scale rule itself is correct — the controlling variable is whether the per-replica metric crosses target, not whether the rule is broken.

- **B → C (workload-mode toggled from `rss` to `cache`):** isolates the metric-source effect. Both apps show a Portal `MemoryPercentage` ABOVE the 50% target (`B` at 56%, `C` at 72%), but only `B` scales out. `C` plateaus at floor `2` despite the Portal value being further above target than `B`'s. The cgroup composition (`stat_cache_bytes / stat_rss_bytes` ratio of 39.4× for `C` vs 0.003× for `B`) explains why: the KEDA memory scaler reads a numerator dominated by anonymous RSS, while the Portal `MemoryPercentage (Preview)` metric is sourced from Azure Monitor and, based on the cgroup composition captured here, behaves as if it includes reclaimable page cache. The two numerators diverge by tens of percentage points for `C` but agree closely for `B`.

The H2 gate's `gate_classification` (`portal_mempct_diverges_from_keda_scaler_input_for_cache_heavy_workloads`) records the falsifiable claim. The lab guide's `## 2) Hypothesis` records the upstream root cause (`metric-source mismatch + HPA ceiling math`); the metric-source half of that root cause is documented as `[Strongly Suggested]` rather than `[Observed]` because the kubelet/metrics-server numerator that KEDA actually reads is not exposed in Container Apps.

## Honest disclosure — empirical platform behavior captured during this run

The following platform behaviors surfaced during the 2026-06-24 live run and are documented both here and in `trigger.sh`'s header comments so a future operator can reproduce the pack without re-discovering them:

- **az-cli 2.79.0 `--offset` bug.** Passing `--offset PT15M` alone to `az monitor metrics list` (without `--start-time`/`--end-time`) raises `TypeError: unsupported operand type(s) for -: 'datetime.datetime' and 'str'` inside `list_metrics`. The workaround is to compute the start/end ISO 8601 pair up front (`METRIC_END_UTC` from `date -u`, `METRIC_START_UTC` from `date -u -v -15M` or `date -u -d "-15 minutes"`) and pass both flags explicitly. `trigger.sh` Phase 7–18 carries both flags on every `az monitor metrics list` invocation.

- **`az containerapp exec` pseudo-tty requirement.** On a non-interactive macOS shell, `az containerapp exec` fails with `tty.setcbreak()` because the underlying SSH-over-WebSocket adapter expects a pty. The workaround is to wrap each exec call with `script -q /dev/null az containerapp exec ... < /dev/null` to allocate a pty without supplying interactive input. The `capture_cgroup_file` helper in `trigger.sh` applies this wrapper and pipes through a 7-line noise filter (`INFO:`, `Disconnect`, `Use ctrl-`, `FutureWarning`, `warnings.warn`, `^WARNING:`, `^Script started/done`) before recording the cgroup file contents.

- **HTTP 429 throttling between consecutive `exec` calls.** Container Apps throttles consecutive `az containerapp exec` calls with `429 Too Many Requests`. The `capture_cgroup_file` helper is invoked three times per scenario (once per cgroup file) with a 20-second sleep between calls. The total per-scenario cgroup capture takes ~60 seconds (3 calls × ~5 s exec + 2 × 20 s sleeps).

- **Cgroup raw data carries `\r\r\n` line endings (pty artifact).** Because the captures are run through `script -q /dev/null`, the pty's line-ending normalization produces `\r\r\n` instead of `\n`. `verify.sh`'s cgroup parser explicitly strips `\r` characters before splitting on `\n` (`text.replace("\r", "").split("\n")`) to handle this. A naive `\n` split would silently fail to match the regex `^([a-zA-Z_]+)\s+(\d+)$` against `memory.stat` lines.

- **Cgroup files stored as three separate JSON keys (not a single combined key).** The initial trigger run attempted to capture all three cgroup files with one combined heredoc inside an `exec` invocation; the result was unparseable due to pty wrapping interactions. The refactored `capture_cgroup_file` helper issues three separate `exec` calls and writes the contents to three separate top-level keys in the per-scenario `*-cgroup.json` file (`memory_usage_in_bytes_raw`, `memory_limit_in_bytes_raw`, `memory_stat_raw`). The actual evidence in `10-scenario-a-cgroup.json`, `14-scenario-b-cgroup.json`, and `18-scenario-c-cgroup.json` already uses this layout; the refactored `trigger.sh` reproduces it on the first attempt.

- **Container Apps on AKS-backed cgroup v1.** The captures target `/sys/fs/cgroup/memory/memory.{usage_in_bytes,limit_in_bytes,stat}` (cgroup v1 paths). The `cgroup_version: v1` and `memory_path: /sys/fs/cgroup/memory` keys are recorded explicitly in each `*-cgroup.json` file so a future reader does not have to infer the cgroup version from file shape. If Container Apps moves the runtime to cgroup v2 in a future platform release, the verify.sh parser would need to be updated to handle the v2 file format (`memory.current`, `memory.max`, `memory.stat` with different keys).

- **`mempct_min == mempct_max` for all three scenarios.** The `MemoryPercentage (Average)` metric returned a constant value across the 15-minute window for each app (40.0 for `A`, 56.0 for `B`, 72.0 for `C`). This is consistent with the workload allocator reaching steady state quickly and holding it for the entire observation window — `app.py` allocates `TARGET_MB` of bytes in either RSS or cache mode and then idles. The constant-value property is not a measurement artifact; it is the workload behavior. The `c_strong_path` sub-gate predicates therefore use narrow expected bands (`A` in `[35,45]`, `B` in `[50,60]`, `C` in `[65,80]`) that the observed constant values fall inside.

## ACR credential safety policy

The ACR admin credential (`username` + `password`) is the one P0 secret-class surface in this lab. `trigger.sh` Phase 1 retrieves both fields into shell variables (`ACR_USERNAME`, `ACR_PASSWORD`) and passes them to `az containerapp create` via `--registry-username` / `--registry-password`. The password is NEVER written to any evidence file:

- `01-infra-resolve.json` records `acr_credential_retrieved: true` and `acr_credential_logged_to_evidence: false` as explicit assertions, but does not record the password value.
- `03-scenario-a-trigger.json`, `04-scenario-b-trigger.json`, and `05-scenario-c-trigger.json` are post-creation `az containerapp show` responses. Container Apps stores the registry password as a managed secret and exposes it in these responses only as `passwordSecretRef` (a secret NAME, never a secret VALUE). The actual secret value is opaque to `containerapp show`.
- `trigger.sh` deliberately does NOT enable `set -x` after the credential retrieval line, because `set -x` would echo the full `az containerapp create` command line including the resolved `--registry-password` argument.
- The `/tmp/trigger-${app_name}-create.json` temp file written by Phase 3–5 is `rm -f`'d immediately after the `containerapp show` capture for the same scenario, because the create response also contains the resolved password.

The PII scrub policy applied to this evidence pack (see top of this file) targets subscription/tenant GUIDs, employee aliases, employee emails, long uppercase hex tokens, and local user paths. The ACR password is handled at the trigger.sh layer (never written) rather than at the scrub layer (because there is nothing to scrub).

## File index

| Phase | Files | Source |
|---|---|---|
| Infra resolve | `01-infra-resolve.json` | `trigger.sh` Phase 1 — RG, ACR, ACA env, image digest (credentials NOT logged) |
| Image metadata | `02-image-manifest.json` | `trigger.sh` Phase 2 — `az acr repository show` for `mempct:v1` |
| Scenario A create | `03-scenario-a-trigger.json` | `trigger.sh` Phase 3 — `ca-mempct-a-below` post-create state (rss, TARGET_MB=400) |
| Scenario B create | `04-scenario-b-trigger.json` | `trigger.sh` Phase 4 — `ca-mempct-b-above` post-create state (rss, TARGET_MB=560) |
| Scenario C create | `05-scenario-c-trigger.json` | `trigger.sh` Phase 5 — `ca-mempct-cache` post-create state (cache, TARGET_MB=700) |
| HPA stabilization wait | `06-wait-markers.log` | `trigger.sh` Phase 6 — bounded 1200 s wait with elapsed markers every 120 s |
| Scenario A evidence | `07-scenario-a-revisions.json`, `08-scenario-a-replicas.json`, `09-scenario-a-memorypercentage.json`, `10-scenario-a-cgroup.json` | `trigger.sh` Phase 7–10 — revisions list, `Replicas` metric (PT1M), `MemoryPercentage` metric (PT1M), cgroup v1 capture (3 separate exec calls) |
| Scenario B evidence | `11-scenario-b-revisions.json`, `12-scenario-b-replicas.json`, `13-scenario-b-memorypercentage.json`, `14-scenario-b-cgroup.json` | `trigger.sh` Phase 11–14 — same structure as A |
| Scenario C evidence | `15-scenario-c-revisions.json`, `16-scenario-c-replicas.json`, `17-scenario-c-memorypercentage.json`, `18-scenario-c-cgroup.json` | `trigger.sh` Phase 15–18 — same structure as A |
| CLI metadata | `19-cli-versions.json`, `20-cli-containerapp-ext.json`, `21-region.json` | `trigger.sh` Phase 19–21 — `az version`, containerapp extension manifest, region/subscription/tenant (scrubbed) |
| H1 sub-gates | `22-h1-scenario-a-gate.json`, `23-h1-scenario-b-gate.json`, `24-h1-scenario-c-gate.json` | `verify.sh` Phase 22–24 — per-scenario 5 sub-gates (a scale_rule_match, b replica behavior, c mempct band, d cgroup composition, e active revision unique), strict 2-path predicate (Strong + Fallback) |
| H2 cross-scenario differential | `25-h2-differential-gate.json` | `verify.sh` Phase 25 — 6 sub-gates (a A held, b B walked to max, c C stalled despite overtarget, d cache explains divergence, e ordinal scaling proven, f three distinct apps) |

The pack contains **25 numbered evidence prefixes** (`01-*` through `25-*`) totaling **25 physical files**. Prefix `06-*` uses a `.log` extension instead of `.json`; all other prefixes are `.json`.

## Reproducibility

To reproduce this evidence pack against a fresh Azure subscription:

```bash
export AZ_SUBSCRIPTION="<your-subscription-id>"
export RG="rg-aca-lab-mempct2"
export LOCATION="koreacentral"
export BASE_NAME="mempct"

az group create --name "$RG" --location "$LOCATION" --subscription "$AZ_SUBSCRIPTION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --template-file labs/memory-percentage-vs-keda-utilization/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

export ACR_NAME=$(az deployment group show --resource-group "$RG" --name main \
    --query properties.outputs.containerRegistryName.value --output tsv)
export ENV_NAME=$(az deployment group show --resource-group "$RG" --name main \
    --query properties.outputs.environmentName.value --output tsv)

# Build the workload image into ACR (single image, runtime-configurable via env vars).
az acr build --registry "$ACR_NAME" --image mempct:v1 \
    labs/memory-percentage-vs-keda-utilization/workload

# Run the orchestrator (single script — creates 3 apps, waits 20 min, captures 21 snapshots).
bash labs/memory-percentage-vs-keda-utilization/trigger.sh

# Run verify (pure file processor — no Azure calls — emits 22..25 gates).
bash labs/memory-percentage-vs-keda-utilization/verify.sh

# Async cleanup (--no-wait, costs stop accruing immediately).
bash labs/memory-percentage-vs-keda-utilization/cleanup.sh
```

Expected runtime: ~30 minutes total (~3 min Bicep deploy, ~2 min image build, ~5 min app creates, 20 min HPA stabilization wait, ~3 min per-scenario captures including cgroup retry sleeps, ~30 s verify, immediate cleanup queue). Estimated cost: <$1 USD (Consumption plan, three short-lived 1.0Gi/0.5CPU apps running for ~30 min, ACR Basic tier, single Log Analytics workspace, Korea Central).

The `verify.sh` script is a pure file processor — it reads `evidence/01-*` through `evidence/18-*` from disk and emits `evidence/22-*` through `evidence/25-*`. It does NOT call Azure, which is why the resource group can be deleted (via `cleanup.sh --no-wait`) before `verify.sh` finishes. This makes the verification step fully replayable from the disk-captured evidence by anyone who has access to this directory.

## CLI versions

The captures in this pack were produced with az-cli **2.79.0** and containerapp extension **1.3.0b4**, recorded in `19-cli-versions.json` and `20-cli-containerapp-ext.json` respectively. The az-cli 2.79.0 `--offset` bug documented in the honest disclosure section above was discovered during this run; future az-cli releases may fix the bug, in which case the explicit `--start-time`/`--end-time` workaround in `trigger.sh` remains correct but no longer strictly necessary. The `az containerapp exec` pseudo-tty requirement and HTTP 429 throttling behavior are platform-side (not CLI-side) and are not expected to change with CLI upgrades.
