# Lab: Traffic Routing Canary Failure

Reproducible lab demonstrating that the controlling variable for a failed canary release is the **port-mismatched BAD revision in a weighted traffic split**, and that the fix is a **config-plane rollback** (`az containerapp ingress traffic set --revision-weight GOOD=100`) that restores 100% client success **without minting a new GOOD revision**.

The lab deploys one Container App running the GOOD `helloworld` image (listens on `:80`, ingress `targetPort=80`), then mints a BAD revision by swapping in `mcr.microsoft.com/dotnet/samples:aspnetapp` (listens on `:8080`) while leaving ingress `targetPort=80`, and applies a 50/50 traffic split so roughly half of client requests hit the failing revision. Two hypotheses are tested:

1. **H1 — Canary failure reproduced.** With a 50/50 split, a 30-request client loop sees a mix of HTTP 200 and timeouts within the documented `[8, 22]` tolerance band for weighted-random routing, and the system log stream shows `ProbeFailed` events on the BAD revision.
2. **H2 — Rollback restores success without a new GOOD revision.** Setting the traffic weight to `GOOD=100` restores 100% client success and the GOOD revision is proven untouched by triangulation — its name, `createdTime`, and image are all unchanged.

> **Image-swap workaround.** Container Apps' ingress `targetPort` is an app-level setting shared across all revisions, so a per-revision `--target-port` override is architecturally impossible. The BAD revision is therefore minted via an image swap (`:80` → `:8080`) with ingress `targetPort=80` left untouched — the minimal mechanism that injects a per-revision port mismatch while keeping the GOOD revision's template completely unchanged (required for the H2 same-revision proof). See [`evidence/README.md`](evidence/README.md).

## Structure

```text
labs/traffic-routing-canary/
├── infra/main.bicep     # Log Analytics + Container Apps env + 1 app (GOOD helloworld revision, ingress targetPort=80)
├── trigger.sh           # H1 — capture GOOD identity, mint BAD revision, apply 50/50 split, 30-request probe loop, emit 12-h1-gate.json
├── verify.sh            # H2 — re-confirm BAD failure, roll back to GOOD=100, capture recovery, emit 22-h2-gate.json
├── cleanup.sh           # Async resource group delete (--no-wait)
└── evidence/            # Captured CLI evidence (22 numbered prefixes; see evidence/README.md)
```

## Quick Start

```bash
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-traffic2"
export LOCATION="koreacentral"

az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file labs/traffic-routing-canary/infra/main.bicep \
    --parameters baseName=labtraffic

export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)

bash labs/traffic-routing-canary/trigger.sh   # H1 — emits 01-* through 12-h1-gate.json
bash labs/traffic-routing-canary/verify.sh    # H2 — emits 13-* through 22-h2-gate.json
bash labs/traffic-routing-canary/cleanup.sh   # async resource group delete
```

## Evidence summary

The committed evidence pack was captured on **2026-06-24** against Container App `ca-labtraffic-ve2wnr` (RG `rg-aca-lab-traffic2`, Korea Central):

- **H1** minted the BAD revision `--badv2` (`mcr.microsoft.com/dotnet/samples:aspnetapp`, listening on `:8080`), applied the 50/50 split, and a 30-request loop returned 17 × HTTP 200 and 13 × timeout — within the `[8, 22]` band. All 5 sub-gates PASS.
- **H2** confirmed the BAD revision's `runningStateDetails` (`The TargetPort 80 does not match the listening port 8080`), rolled back to `GOOD=100`, and a post-fix probe returned 5/5 HTTP 200 with the GOOD revision (`--w3daylh`) proven untouched. All 6 sub-gates PASS.

See [`evidence/README.md`](evidence/README.md) for the full file index, image-swap workaround note, and CLI versions.

## Cost and cleanup

Expected runtime ~15 minutes; estimated cost <$0.10 USD (Consumption plan, two short-lived public-image revisions, one Log Analytics workspace, Korea Central). Run `cleanup.sh` immediately after capturing evidence.

## Related Playbook

- Lab guide: [Traffic Routing Canary Failure](../../docs/troubleshooting/lab-guides/traffic-routing-canary.md)

## See Also

- [`evidence/README.md`](evidence/README.md) — evidence pack provenance, capture timeline, and image-swap workaround note.
