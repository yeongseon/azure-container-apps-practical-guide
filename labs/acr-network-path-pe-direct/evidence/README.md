# Evidence pack — `acr-network-path-pe-direct` lab

This directory carries the live raw evidence cohort for the `acr-network-path-pe-direct` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-pe-direct/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path B with ACR `publicNetworkAccess=Disabled`, one ACR Private Endpoint NIC, one linked `privatelink.azurecr.io` zone, and one forced fresh-pull failure/recovery arc on one Container App. It does **not** claim universal applicability across regions, tenants, DNS topologies, or platform versions.

## Capture timeline

1. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-kql-imagepull-events-pre-fix.json` capture the broken `v-broken` window after the VNet link is removed and a fresh pull is forced.
2. **H2 recovery surface.** `09-private-dns-link-list-post-fix.json` through `12-kql-imagepull-events-post-fix.json` capture the restored VNet link, healthy `v-recover` revision, and the recovery pull events.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC IP map, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the link list is empty, ACR public access stayed `Disabled`, the broken window contains `ImagePullUnauthorized` evidence for `v-broken`, and at least one `v-broken` revision entered a failing state.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves exactly one VNet link to the lab VNet was restored, the latest `v-recover` revision is `Healthy`, the recovery window contains `PullingImage` then `PulledImage`, and ACR public access still reads `Disabled`.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full normalized overlapping H1↔H2 diff, isolates the VNet-to-private-DNS link as the trigger field, and explicitly lists the unsupported inferences.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `06-system-logs-pre-fix.json` is JSONL/NDJSON, not a JSON array; `verify.sh` parses it one line at a time.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- Gate 15 intentionally fails with `h1_trigger_outcome: "trigger_did_not_force_failure"` if the forced fresh pull does **not** surface a failing `v-broken` state.
- The pack does not prove exact retry timing, exact pull durations, OCI layer SHA identity, pod UID continuity, replica suffix continuity, BUILD_TAG continuity, or revision suffix identity. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Full revision list during the broken `v-broken` window |
| `03-private-dns-link-list-pre-fix.json` | Empty link list after the VNet link is removed |
| `04-pe-nic-config-pre-fix.json` | PE NIC configuration proving the RFC1918 topology |
| `05-acr-public-access-pre-fix.json` | ACR public access snapshot (`Disabled`) during H1 |
| `06-system-logs-pre-fix.json` | Raw system-log capture around the broken pull window |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app YAML |
| `08-kql-imagepull-events-pre-fix.json` | KQL image-pull event window around the broken pull |
| `09-private-dns-link-list-post-fix.json` | Restored link list with exactly one lab-VNet link |
| `10-revision-list-post-fix.json` | Full revision list during the recovered `v-recover` window |
| `11-app-spec-post-fix.json` | Post-fix container app surface plus ACR + PE NIC snapshots |
| `12-kql-imagepull-events-post-fix.json` | KQL image-pull event window around the recovery pull |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-pe-direct/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-pe-direct/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four gate JSONs deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
