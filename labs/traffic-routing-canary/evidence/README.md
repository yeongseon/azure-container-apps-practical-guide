# Evidence Pack Provenance

This directory contains the raw evidence artifacts for the `traffic-routing-canary` lab run on **2026-06-24**. All files are PII-scrubbed (subscription/tenant GUIDs replaced with the zero-GUID placeholder, employee aliases replaced with `demouser`, employee emails replaced with `user@example.com`, long uppercase hex tokens replaced with `AAAA…A` placeholders).

## Capture timeline

The lab evidence was captured in a single live-Azure window on **2026-06-24**:

- **H1 trigger window (00:13–00:18 UTC).** `trigger.sh` resolved infrastructure on the freshly deployed Container App `ca-labtraffic-ve2wnr` (RG `rg-aca-lab-traffic2`, Korea Central), captured the GOOD revision identity (`ca-labtraffic-ve2wnr--w3daylh`, image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`, createdTime `2026-06-24T00:12:40+00:00`) for later same-revision triangulation, minted a BAD revision (`ca-labtraffic-ve2wnr--badv2`, image `mcr.microsoft.com/dotnet/samples:aspnetapp` which listens on `:8080`) while leaving ingress `targetPort=80`, applied a 50/50 traffic split, ran a 30-request client probe loop (17 × HTTP 200, 13 × timeout — within the documented `[8, 22]` tolerance band for 50/50 weighted-random routing), tailed the system log stream for ProbeFailed events (18 lines), and emitted `12-h1-gate.json` (`gate_classification: canary_failure_reproduced_50_50_traffic_split`, all 5 sub-gates PASS).

- **H2 verify window (00:26–00:28 UTC).** `verify.sh` re-confirmed the BAD revision's pre-fix failure state (`runningStateDetails: "Deployment Progress Deadline Exceeded. 0/1 replicas ready. The TargetPort 80 does not match the listening port 8080."`), applied the config-plane rollback (`az containerapp ingress traffic set --revision-weight ca-labtraffic-ve2wnr--w3daylh=100`), waited 15 s for traffic propagation, captured post-fix snapshots, ran a post-fix 5-request curl probe (5 × HTTP 200), and emitted `22-h2-gate.json` (`gate_classification: canary_rolled_back_to_good_revision_intact`, all 6 sub-gates PASS).

Both gates pass, supporting the lab's hypothesis: the controlling variable for canary failure is the port-mismatched BAD revision in the 50/50 traffic split; the documented rollback (`az containerapp ingress traffic set --revision-weight GOOD=100`) restores 100% client success WITHOUT minting a new GOOD revision (triangulated proof via name + createdTime + image, all unchanged).

## Image-swap workaround note

The `trigger.sh` BAD revision is minted via an **image swap** (`mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` listens on `:80` → `mcr.microsoft.com/dotnet/samples:aspnetapp` listens on `:8080`) with the ingress `targetPort=80` left untouched. This is intentional: Container Apps' ingress `targetPort` is a Container-App–level setting shared across all revisions, so a per-revision `--target-port` override (which the original lab guide draft attempted) is architecturally impossible. The image swap is the minimal mechanism that injects a per-revision port mismatch while keeping the GOOD revision's template completely untouched, which is required for the H2 same-revision-proof triangulation.

## File index

| Phase | Files | Source |
|---|---|---|
| Trigger setup | `01-infra-resolve.json` through `04-good-revision-captured.json` | `trigger.sh` Phases 1–3 — infra resolve, baseline revisions, baseline 5-request curl, GOOD revision identity snapshot |
| Trigger fault injection | `05-containerapp-update-image.json` + `.stderr`, `06-wait-bad-revision.log`, `07-revision-list-bad.json`, `08-revision-show-bad.json`, `08-revision-show-good.json` | `trigger.sh` Phases 4–8 — image swap update, wait for BAD revision to provision, per-revision detail captures |
| Trigger traffic split + probes | `09-traffic-set-50-50.json` + `.stderr`, `10-curl-loop-30-requests.json`, `11-system-logs-tail.log` | `trigger.sh` Phases 9–10 — apply 50/50 split, 30-request curl loop, syslog tail for ProbeFailed |
| H1 gate | `12-h1-gate.json` | `trigger.sh` Phase 11 — 5 sub-gates evaluated |
| Verify pre-fix | `13-revision-pre-fix-bad.json`, `14-curl-pre-fix.json` | `verify.sh` Phases 13–14 — re-confirm BAD failure state, noisy 5-request curl on 50/50 split |
| Verify fix | `15-traffic-set-rollback.json` + `.stderr`, `16-wait-recovery.log` | `verify.sh` Phases 15–16 — apply rollback (GOOD=100), 15 s propagation wait |
| Verify post-fix | `17-revision-list-post-fix.json`, `17-revision-show-good-post-fix.json`, `18-curl-post-fix.json`, `19-cli-versions.json`, `20-cli-containerapp-ext.json`, `21-region.json` | `verify.sh` Phases 17–19 — post-fix snapshots, 5-request curl, CLI/region metadata |
| H2 gate | `22-h2-gate.json` | `verify.sh` Phase 19 — 6 sub-gates evaluated |

## Reproducibility

To reproduce this evidence pack against a fresh Azure subscription:

```bash
export AZ_SUBSCRIPTION="<your-subscription-id>"
export RG="rg-aca-lab-traffic"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION" --subscription "$AZ_SUBSCRIPTION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --template-file labs/traffic-routing-canary/infra/main.bicep

export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)

bash labs/traffic-routing-canary/trigger.sh   # emits 01-* through 12-h1-gate.json
bash labs/traffic-routing-canary/verify.sh    # emits 13-* through 22-h2-gate.json
bash labs/traffic-routing-canary/cleanup.sh   # async resource group delete (--no-wait)
```

Expected runtime: ~15 minutes total (~5 min Bicep deploy, ~5 min trigger, ~3 min verify, immediate cleanup queue). Estimated cost: <$0.10 USD (Consumption plan, two short-lived public-image revisions, single Log Analytics workspace, Korea Central).

## CLI versions

The captures in this pack were produced with the CLI versions recorded in `19-cli-versions.json` and `20-cli-containerapp-ext.json`. The `az containerapp ingress traffic set` response shape (top-level list of `{revisionName, weight}` entries — see `15-traffic-set-rollback.json`) was empirically observed with this CLI version; the H2 `b_traffic_set_rollback_succeeded` sub-gate in `verify.sh` accepts both that list shape and the full-Container-App-resource shape defensively.
