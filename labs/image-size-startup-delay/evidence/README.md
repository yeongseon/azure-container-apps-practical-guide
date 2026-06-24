# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `image-size-startup-delay` lab run on **2026-06-22**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens replaced with `AAAA…A` placeholders, local user paths replaced with `/Users/demouser`).

## Capture timeline

The lab evidence was captured in a single live-Azure window on **2026-06-22** against one Container App that went through three revisions in RG `rg-aca-lab-imagesize` (Korea Central, az-cli 2.83.0):

- **Phase 1 — Initial deploy (02:14:46 UTC).** Bicep created Log Analytics workspace, Container Apps environment, and Container App `ca-imgsize-acerjw` with image `python:3.11` and command override `["python", "-m", "http.server", "8080"]`. Public Docker Hub (no ACR). minReplicas=1, maxReplicas=1. CPU 0.5, memory 1.0 Gi. This produced revision `--5487avi` (Scenario A: scripted large image).

- **Phase 2 — Trigger captures Scenario A (02:14:48–02:15:02 UTC).** Initial revision `--5487avi` pulled `python:3.11` in 8.88 s (408,944,640 bytes; image size from the `Successfully pulled image` log line) and reached `Healthy` with the container bound to port 8080. `trigger.sh` ran a polling loop and recorded the table output and a 50-line tail of system logs into `01-trigger-large-image.txt`.

- **Phase 3 — Off-script falsification revision created (02:24:20 UTC, manual diagnostic).** An additional revision `--0000001` was manually created using image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` while keeping the same Bicep command override `python -m http.server 8080`. This is the **off-script Scenario C** falsification check. The helloworld image is an nginx-based Microsoft Docs sample with no Python runtime, so the executable override could not run. The revision pulled the helloworld image in 1.62 s cold (33,554,432 bytes), then on three subsequent replica restart attempts in 12 ms / 11 ms / 9 ms (warm pulls against the now-cached image on the same node), each time hitting `ContainerCreateFailure` with `exec: "python": executable file not found in $PATH`. Four `ContainerTerminated` events were captured against replica `ca-imgsize-acerjw--0000001-666f66947d-mjk8g` between 02:24:38 and 02:26:13 UTC.

- **Phase 4 — Verify captures Scenario B (02:26:43–02:27:18 UTC).** `verify.sh` captured the pre-fix system logs into `system-logs-large.json` (which therefore contains the helloworld `ContainerCreateFailure` events because that was the currently-active revision at capture time), then ran `az containerapp update --image python:3.11-alpine` to deploy the trimmed image. Container Apps created revision `--0000002` (Scenario B: scripted small image). The revision pulled `python:3.11-alpine` in 2.88 s (19,922,944 bytes) and reached `Healthy`. `verify.sh` then captured the post-fix system logs into `system-logs-small.json` (which contains both the lingering helloworld events from the deactivating Scenario C revision AND the python:3.11-alpine cold pull). The verify.sh script's "Old image" line in `02-verify-small-image.txt` reads `containerapps-helloworld` (not `python:3.11`) because verify.sh resolves the CURRENT image at runtime via `az containerapp show`, and at that moment the active image was the off-script helloworld scenario.

- **Phase 5 — Post-experiment artifact captures (later 02:27 UTC).** Additional artifacts captured: `03-revisions-list.json` (active revision only), `04-containerapp-summary.json` (FQDN, location, latest revision), `05-revisions-all.json` (all 3 revisions including the inactive `--5487avi` and `--0000001`), `06-kql-pull-events.json` (KQL `Successfully pulled image` events across all revisions — 6 entries: 1 cold for each of large/alpine and 1 cold + 3 warm for helloworld), `07-containerapp-full-config.json` (full ACA resource configuration, ~7 KB), `08-environment-logs-config.json` (Container Apps Environment `appLogsConfiguration` proving Log Analytics wiring), `09-kql-event-summary.json` (full revision lifecycle grouped by `Reason_s` with per-revision rollups — KEDAScalersStarted → PullingImage → PulledImage → ContainerCreated → ContainerStarted → ContainerTerminated → KEDAScalersStopped → ScaledObjectDeleted).

- **Verify Phase 10–13 — Gate emission (replayable, no Azure calls).** `verify.sh` is a pure file processor against `evidence/03-*` through `evidence/09-*` (and `system-logs-*.json`). It computes four falsifiable gates evaluated against a strict 2-path predicate (Strong path = exact field match in a specific JSON file; Fallback path = substring search in raw text). All four gates were emitted with `utc_captured` matching the verify-run timestamp:
    - `10-h1-a-large-cold-pull-gate.json` → `scripted_large_cold_pull_observed_and_healthy` (3/3 sub-gates PASS)
    - `11-h1-b-small-cold-pull-gate.json` → `scripted_small_cold_pull_observed_and_healthy` (3/3 sub-gates PASS)
    - `12-h1-c-speedup-ratio-gate.json` → `scripted_cold_pull_speedup_material` (2/2 sub-gates PASS, observed ratio 3.08× ≥ threshold 2.5×)
    - `13-h2-falsification-gate.json` → `small_image_alone_not_sufficient_for_healthy_startup` (3/3 sub-gates PASS)

All four gates pass on the Strong path with no Fallback-path fallback required.

## Cross-scenario differential proof — why this is not a fake-fix lab

This lab has a "before/after fix" surface (`verify.sh` literally swaps the image), but the falsifiable claim is **not** that the smaller image is universally better. The falsifiable claim is the **two-part contrast** captured by the four gates:

- **H1 (Gates 10/11/12) — base-image size dominates cold-pull time when the runtime contract is satisfied.** Both scripted revisions (`python:3.11` at 408 MB and `python:3.11-alpine` at 20 MB) execute the identical workload contract (same command `python -m http.server 8080`, same target port 8080, same Container Apps Environment, same cgroup/CPU/memory shape). The only intentionally changed variable is the base-image size. The 3.08× cold-pull speedup on a 20.5× smaller image (Gate 12) isolates image size as the controlling variable for cold-pull time on this Container Apps Environment, in this region, on this run.

- **H2 (Gate 13) — small image alone is not sufficient for fast healthy startup.** The off-script helloworld revision (`--0000001`) had the FASTEST cold pull of all three (1.62 s) and was the SECOND-SMALLEST image (34 MB), yet the container repeatedly hit `ContainerCreateFailure` because the image has no Python runtime to execute the Bicep command override. This rules out the alternative hypothesis that "a small image alone implies a fast healthy startup". The runtime inside the image must also match the executed command. Gate 13's `gate_classification` records this falsifiable claim.

The H1 gates prove that **when** the runtime contract holds, image size is the dominant cold-pull cost. The H2 gate proves that image size **alone** is not a sufficient condition for healthy startup. The two halves together yield the operator guidance in the lab guide's `## 13. Solution` section: trim base images for cold-start latency reduction, AND verify the executable exists in the chosen image before deploying with `command:` overrides.

## Honest disclosure — empirical platform behavior captured during this run

The following observations surfaced during the 2026-06-22 live run and are documented both here and in `trigger.sh`'s header comments so a future operator can reproduce the pack without re-discovering them:

- **`system-logs-large.json` and `system-logs-small.json` BOTH contain the helloworld `ContainerCreateFailure` events.** These two files were captured by `verify.sh` at 02:26:43 UTC (pre-fix) and 02:27:17 UTC (post-fix). The off-script helloworld revision (`--0000001`) was active at 02:26:43 UTC (pre-fix capture) and was still in the middle of being deactivated at 02:27:17 UTC (post-fix capture). Both system-log captures therefore include the 4 `ContainerTerminated` events from the helloworld replica `ca-imgsize-acerjw--0000001-666f66947d-mjk8g`. The naming "large/small" refers to the verify.sh phase (pre-fix vs post-fix), NOT to which image was actually active at capture time. The authoritative per-revision data is in `06-kql-pull-events.json` (which keys every event by `RevisionName_s`).

- **`02-verify-small-image.txt` "Old image" line reads `containerapps-helloworld`, not `python:3.11`.** `verify.sh` resolves the CURRENT image at runtime with `az containerapp show --query 'properties.template.containers[0].image'`. At the moment verify.sh ran, the operator had already manually switched the app to the off-script helloworld image as part of the falsification check. So the verify.sh "Old image:" diagnostic line reads `containerapps-helloworld`, not the originally-deployed `python:3.11`. This is a true reflection of platform state at the moment of capture; it is NOT a bug in verify.sh.

- **All three revisions report `healthState: Healthy` in `05-revisions-all.json`.** Azure Container Apps marks revisions `Healthy` at deploy time and does not always update that field when later container terminations occur on the same revision. The off-script helloworld revision (`--0000001`) reports `healthState: Healthy` despite its 4 `ContainerCreateFailure` events. The authoritative signal for the falsification gate (Gate 13) is the `ContainerTerminated` count in `09-kql-event-summary.json` and the `Type: Warning` + `Reason: ContainerTerminated` events in `system-logs-large.json`, NOT the revision-level `healthState` field. The verify.sh Gate 13 predicates therefore key off the `ContainerTerminated` count for the helloworld revision and the `exec: "python": executable file not found in $PATH` error signature, not off the `healthState` field.

- **Mutable image tags.** `python:3.11` and `python:3.11-alpine` are floating tags on public Docker Hub. The image sizes recorded in this evidence (408,944,640 bytes for `python:3.11`; 19,922,944 bytes for `python:3.11-alpine`; 33,554,432 bytes for `containerapps-helloworld`) are the sizes pulled on 2026-06-22. A future re-run via `trigger.sh` may pull a different digest under the same tag and observe slightly different byte counts. The committed 2026-06-22 evidence is the authoritative baseline for this evidence pack. The Gate 12 speedup-ratio threshold (≥ 2.5×) is intentionally lower than the observed 3.08× to absorb minor pull-time variance on re-runs while still falsifying the case where the two image sizes converge.

- **Warm-pull data comes only from the off-script helloworld revision.** The "warm pulls collapse to single-digit milliseconds" observation in the lab guide's `## 9. Analysis` and `## 15. Takeaway` sections is supported by the 12 ms / 11 ms / 9 ms pulls of the helloworld image on replica restart attempts 2, 3, and 4 (all on the same replica `--0000001-666f66947d-mjk8g`, after the initial 1.62 s cold pull on attempt 1). The lab does NOT have warm-pull measurements for the scripted `python:3.11` or `python:3.11-alpine` revisions because each was a single-replica deploy that did not restart on the same node. The warm-pull claim is therefore narrower than "warm pulls always collapse regardless of image size" — it is "on this Container Apps Environment in this run, the helloworld image's per-pull cost dropped from 1.62 s cold to 9–12 ms warm on the same node". The Gate 13 predicates use only the cold/fail signature for the helloworld revision; the warm-pull observation is reported as supporting context in the lab guide but is not gate-asserted.

## File index

| Phase | Files | Source |
|---|---|---|
| Trigger output (Scenario A) | `01-trigger-large-image.txt` | `trigger.sh` Phase 2 — table output + 50-line system-log tail capturing the cold pull of `python:3.11` (8.88 s, 408,944,640 bytes) |
| Verify output (Scenario B) | `02-verify-small-image.txt` | `verify.sh` Phase 4 — pre/post comparison output capturing the cold pull of `python:3.11-alpine` (2.88 s, 19,922,944 bytes); the "Old image:" line reads `containerapps-helloworld` because verify.sh resolves runtime state |
| Active revision | `03-revisions-list.json` | Single-revision mode final state — only the active `--0000002` (python:3.11-alpine) |
| Container App summary | `04-containerapp-summary.json` | Container App essentials (FQDN, location, latest revision) |
| All revisions | `05-revisions-all.json` | All 3 revisions including the inactive `--5487avi` (python:3.11), the inactive off-script `--0000001` (helloworld), and the active `--0000002` (python:3.11-alpine) — all 3 report `healthState: Healthy` (see honest disclosure above) |
| KQL pull events | `06-kql-pull-events.json` | `ContainerAppSystemLogs_CL | where Log_s contains "Successfully pulled image"` — 6 entries keyed by `RevisionName_s` (cold for each of large/alpine; cold + 3 warm for helloworld) |
| Container App full config | `07-containerapp-full-config.json` | Full ACA resource configuration (~7 KB) |
| Environment logs config | `08-environment-logs-config.json` | Container Apps Environment `appLogsConfiguration` proving Log Analytics wiring |
| KQL event summary | `09-kql-event-summary.json` | Full revision lifecycle grouped by `Reason_s` with per-revision rollups; the helloworld revision shows `ContainerTerminated PullCount=4` (the 4 failed start attempts) |
| Pre-fix system logs | `system-logs-large.json` | Raw system logs from `verify.sh` pre-fix capture (02:26:43 UTC) — contains the helloworld `ContainerCreateFailure` events because that revision was active at capture time |
| Post-fix system logs | `system-logs-small.json` | Raw system logs from `verify.sh` post-fix capture (02:27:17 UTC) — contains both the lingering helloworld events from the deactivating revision AND the python:3.11-alpine cold pull at 02:27:18 |
| H1 gates | `10-h1-a-large-cold-pull-gate.json`, `11-h1-b-small-cold-pull-gate.json`, `12-h1-c-speedup-ratio-gate.json` | `verify.sh` Phase 10–12 — Scenario A cold pull (3 sub-gates: pull event, image size, revision healthy), Scenario B cold pull (3 sub-gates: pull event, image size, revision healthy), speedup ratio (2 sub-gates: parse both durations, assert ratio ≥ 2.5) — strict 2-path predicate (Strong = exact `Log_s` match in `06-kql-pull-events.json`; Fallback = substring search in `system-logs-*.json`) |
| H2 falsification gate | `13-h2-falsification-gate.json` | `verify.sh` Phase 13 — small_image_alone_not_sufficient: 3 sub-gates (helloworld pulled fastest of all 3 revisions, ContainerTerminated count ≥ 3 for helloworld revision, runtime mismatch error signature `exec: "python": executable file not found in $PATH` present in raw logs) |

The pack contains **15 physical files** under `evidence/`: **11 trigger/verify-captured artifacts** (01–09 numbered + 2 system-logs-* files) AND **4 verify.sh-emitted gate JSONs** (10/11/12/13).

## Reproducibility

To reproduce this evidence pack against a fresh Azure subscription:

```bash
export AZ_SUBSCRIPTION="<your-subscription-id>"
export RG="rg-aca-lab-imagesize"
export LOCATION="koreacentral"
export BASE_NAME="imgsize"

az group create --name "$RG" --location "$LOCATION" --subscription "$AZ_SUBSCRIPTION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --template-file labs/image-size-startup-delay/infra/main.bicep \
    --parameters baseName="$BASE_NAME"

export APP_NAME=$(az deployment group show --resource-group "$RG" --name main \
    --query properties.outputs.containerAppName.value --output tsv)

# Run the orchestrator (single script — drives all 3 scenarios A/B/C deterministically).
bash labs/image-size-startup-delay/trigger.sh

# Run verify (pure file processor — no Azure calls — emits 10..13 gates).
bash labs/image-size-startup-delay/verify.sh

# Async cleanup (--no-wait, costs stop accruing immediately).
bash labs/image-size-startup-delay/cleanup.sh
```

Expected runtime: ~15 minutes total (~2 min Bicep deploy, ~1 min initial python:3.11 cold pull, ~1 min off-script helloworld revision + 4 restart attempts, ~1 min python:3.11-alpine cold pull, ~5 min revision/KQL captures, ~10 s verify, immediate cleanup queue). Estimated cost: <$0.50 USD (Consumption plan, single-replica 1.0 Gi / 0.5 CPU app running for ~15 min across 3 revisions, single Log Analytics workspace, public Docker Hub registry — no ACR, Korea Central).

The `verify.sh` script is a pure file processor — it reads `evidence/01-*` through `evidence/09-*` and `system-logs-*.json` from disk and emits `evidence/10-*` through `evidence/13-*`. It does NOT call Azure (other than the one `az containerapp update` call that performs the image swap in Phase 4 — see Gate naming caveat below), which is why the resource group can be deleted (via `cleanup.sh --no-wait`) before `verify.sh` finishes the gate-emission phases.

**Note on `verify.sh` and `trigger.sh` boundaries.** The historical `verify.sh` from the 2026-06-22 run performed the image swap (`az containerapp update --image python:3.11-alpine`) and captured the post-fix system logs. The refactored `verify.sh` in this commit is **pure file processor only** — it reads existing evidence and emits gates. The image-swap and post-fix capture logic moved into `trigger.sh` Phase 4 (so that the rerun orchestration is self-contained in `trigger.sh`). The committed 2026-06-22 evidence under `01-*` through `09-*` and `system-logs-*.json` remains the canonical baseline; re-running `trigger.sh` against a fresh subscription will overwrite these files with new timestamps.

## CLI versions and platform context

The captures in this pack were produced with az-cli **2.83.0**, recorded directly in the lab guide frontmatter (`lab_validation.az_cli_version`). The lab uses public Docker Hub images (`python:3.11`, `python:3.11-alpine`, `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`) so no ACR credential surface exists in this lab and no credential safety policy is required. The only Azure-side resources are the Container Apps Environment, the Container App, and one Log Analytics workspace. The lab runs entirely on the Consumption plan tier and does not require Workload Profiles or VNet integration.
