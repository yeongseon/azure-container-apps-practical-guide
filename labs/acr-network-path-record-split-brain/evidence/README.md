# Evidence pack — `acr-network-path-record-split-brain` lab

This directory carries the live raw evidence cohort for the `acr-network-path-record-split-brain` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-record-split-brain/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path D with one ACR Private Endpoint NIC, one linked `privatelink.azurecr.io` zone, one deleted regional data A record, one restored regional data A record, and one already-running Container App revision that stayed `Healthy` throughout. It does **not** claim universal applicability across regions, tenants, DNS topologies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `rg-acr-record-split-brain-lab` |
| Base name | `acrrecsplitbrain` |
| Suffix | `ijb7kz` |
| Build tag | `v1` |
| Azure region | `koreacentral` |
| Registry login FQDN | `acracrrecsplitbrainijb7kz.azurecr.io` |
| Data FQDN | `acracrrecsplitbrainijb7kz.koreacentral.data.azurecr.io` |
| Registry record name | `acracrrecsplitbrainijb7kz` |
| Data record name | `acracrrecsplitbrainijb7kz.koreacentral.data` |
| Broken probe capture window | `2026-06-28T22:34:36Z` → `2026-06-28T22:34:36Z` |
| Recovered probe capture window | `2026-06-28T22:36:42Z` → `2026-06-28T22:36:42Z` |
| Post-fix composite capture anchor | `2026-06-28T22:37:05Z` |

## Capture timeline

1. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-probe-response-pre-fix.json` capture the broken window after the regional data A record is deleted and the `/probe` endpoint converges on `topology_class=data_nxdomain`.
2. **H2 recovery surface.** `09-private-dns-record-list-post-fix.json` through `12-pe-nic-config-post-fix.json` capture the restored data A record, the unchanged healthy revision, the recovered `/probe` response, and the unchanged PE NIC + ACR + app surface.
3. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC IP map, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the data A record is absent, `/probe` returns `data_nxdomain`, the already-running revision stays `Healthy`, and the broken-window pull-failure query stays empty.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the data A record is restored with the original PE data IP, `/probe` returns `both_private`, and the same revision stays `Healthy` without a new revision.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full normalized overlapping H1↔H2 diff, isolates the regional data A record as the trigger field, and actively checks the workload-path silence invariant.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `06-system-logs-pre-fix.json` is an explicit Log Analytics query payload whose `rows` list is intentionally empty in the broken window; emptiness is the evidence.
- `08-probe-response-pre-fix.json` and `11-probe-response-post-fix.json` preserve every retry attempt explicitly so the verifier never overclaims instantaneous convergence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact DNS timing, exact retry counts, broken-window control-plane fresh pulls, byte-identical backend HTTP bodies, or TLS cipher-suite identity. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Full revision list in the broken window |
| `03-private-dns-record-list-pre-fix.json` | A-record inventory after the regional data A record is deleted |
| `04-pe-nic-config-pre-fix.json` | PE NIC configuration proving the registry/data private IP map |
| `05-acr-public-access-pre-fix.json` | ACR public access snapshot during H1 |
| `06-system-logs-pre-fix.json` | Broken-window pull-failure KQL payload (expected empty row set) |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app YAML |
| `08-probe-response-pre-fix.json` | Retried `/probe` capture converging on `topology_class=data_nxdomain` |
| `09-private-dns-record-list-post-fix.json` | A-record inventory after the regional data A record is restored |
| `10-revision-list-post-fix.json` | Full revision list after recovery |
| `11-probe-response-post-fix.json` | Retried `/probe` capture converging on `topology_class=both_private` |
| `12-pe-nic-config-post-fix.json` | Composite post-fix app + ACR + PE NIC surface |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-record-split-brain/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-record-split-brain/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four gate JSONs deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
