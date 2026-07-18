# Lab: Probe and Port Mismatch

Reproducible lab demonstrating that a Container Apps revision fails to become ready when the container's listening port does not match the ingress `targetPort`, and that the fix is an **app-scope ingress edit** (`az containerapp ingress update --target-port`) that recovers the **same revision** — without minting a new one, rebuilding the image, or re-pulling.

The Bicep baseline deploys the placeholder `helloworld` image (listens on `:80`) with ingress `targetPort=8000`, so the baseline is already mismatched. The trigger builds a workload that explicitly binds to `:3000` and applies it via `az containerapp update --image` (minting revision `--0000001`) while ingress stays at `8000`, producing a documented `3000` vs `8000` mismatch that keeps the revision from reaching a ready state. Two hypotheses are tested:

1. **H1 — Port mismatch fails the revision.** The port-mismatched revision fails to provision, reports probe failure in its `runningStateDetails` and system logs, and does not serve client traffic.
2. **H2 — Ingress `targetPort` fix recovers the same revision.** Setting the ingress `targetPort` to match the container's listening port recovers the **same revision name and `createdTime`** — falsifying image-broken, pull-failure, and probe-config theories, because none of those would let the identical revision recover from a config-only ingress edit.

## Structure

```text
labs/probe-and-port-mismatch/
├── infra/main.bicep     # Log Analytics + Container Apps env + ACR + 1 app (helloworld baseline, ingress targetPort=8000)
├── workload/            # Flask app that binds to APP_PORT (default 3000), Dockerfile, requirements.txt
├── trigger.sh           # H1 — ACR build, update image to :3000 workload, capture failed state, emit 11-h1-gate.json
├── verify.sh            # H2 — ingress targetPort fix, capture same-revision recovery, emit 22-h2-gate.json
├── cleanup.sh           # Async resource group delete
└── evidence/            # Captured CLI evidence (24 numbered prefixes; see evidence/README.md)
```

## Quick Start

The trigger and verify scripts require `AZ_SUBSCRIPTION`, `RG`, `APP_NAME`, and `ACR_NAME` in the environment.

```bash
export AZ_SUBSCRIPTION="$(az account show --query "id" --output tsv)"
export RG="rg-aca-lab-probe-port"
export LOCATION="koreacentral"

az group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --name "$RG" \
    --location "$LOCATION"

az deployment group create \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --template-file labs/probe-and-port-mismatch/infra/main.bicep \
    --parameters baseName=labport

export APP_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)
export ACR_NAME=$(az deployment group show \
    --subscription "$AZ_SUBSCRIPTION" \
    --resource-group "$RG" \
    --name main \
    --query "properties.outputs.containerRegistryName.value" \
    --output tsv)

bash labs/probe-and-port-mismatch/trigger.sh   # H1 — ACR build + image update + capture failure (emits 11-h1-gate.json)
bash labs/probe-and-port-mismatch/verify.sh    # H2 — ingress fix + same-revision recovery (emits 22-h2-gate.json)
bash labs/probe-and-port-mismatch/cleanup.sh   # async resource group delete
```

## Evidence summary

The committed evidence pack was captured on **2026-06-23** against Container App `ca-labport-zopng3` (Korea Central), assembled in two phases: the original ACR build + image-update fault injection (14:05–14:06 UTC) that minted the failed revision `--0000001`, and a strengthened snapshot capture (22:23–22:40 UTC) after the provisioning poll was widened to 30 attempts × 10 s. The H1 gate confirms the failed/degraded revision state plus probe-failure evidence; the H2 gate confirms the same revision name and `createdTime` recover after the ingress `targetPort` fix. See [`evidence/README.md`](evidence/README.md) for the file index, the non-gating `06-wait-provisioning.log` note, and CLI versions.

## Cost and cleanup

Expected runtime ~30 minutes; estimated cost <$0.50 USD (Consumption plan, single container, Basic ACR SKU, single ~5 KB Python image). Run `cleanup.sh` immediately after capturing evidence.

## Related Playbook

- Lab guide: [Probe and Port Mismatch](../../docs/troubleshooting/lab-guides/probe-and-port-mismatch.md)

## See Also

- [`evidence/README.md`](evidence/README.md) — evidence pack provenance, capture timeline, and non-gating artifact notes.
