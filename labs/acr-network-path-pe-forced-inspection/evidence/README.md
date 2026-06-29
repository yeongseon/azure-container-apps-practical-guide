# Evidence pack — `acr-network-path-pe-forced-inspection` lab

This directory carries the live raw evidence cohort for the `acr-network-path-pe-forced-inspection` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-pe-forced-inspection/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path C with one ACR Private Endpoint, one Azure Firewall Basic instance, one default route to the firewall, two PE NIC IPs, one bypass window created by removing the two customer `/32` PE routes, and one recovery window created by restoring those routes. It does **not** claim universal applicability across regions, tenants, firewall policies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `rg-lab-pe-forced-inspection-202606290915` |
| Base name | `acrpefci` |
| Azure region | `koreacentral` |
| Registry login FQDN | `acracrpefcid6pdtg.azurecr.io` |
| Data FQDN | `acracrpefcid6pdtg.koreacentral.data.azurecr.io` |
| Firewall private IP | `10.90.3.4` |
| Baseline pull window | `2026-06-29T00:05:14Z` → `2026-06-29T00:25:14Z` |
| H1 trigger timestamp | `2026-06-29T00:27:13Z` |
| H2 recovery timestamp | `2026-06-29T00:35:22Z` |

## Capture timeline

1. **Baseline-presence proof.** `01-app-spec-pre-fix.json` through `07-containerapp-spec-pre-fix.yaml` capture the PE-only baseline and the firewall log window proving Azure Firewall did see ACR traffic before the bypass.
2. **H1 silence window.** `02-revision-list-pre-fix.json`, `03-route-table-pre-fix.json`, and `08-h1-silence-window.json` capture the broken window after the two customer `/32` PE routes are removed, where pulls still succeed but the firewall sees zero new ACR rows.
3. **H2 recovery window.** `09-route-table-post-fix.json` through `12-h2-recovery-window.json` capture the restored `/32` routes, healthy `v-recover` revision, and the return of ACR rows in the firewall log.
4. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC IP map, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves the baseline-presence subgate, the `/32` routes were removed while the default route stayed, the v-bypass pull still succeeded under PE-only ACR, the H1 firewall query returned zero rows, and the workload-silence invariant held.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the exact `/32` routes were restored, the latest active `v-recover` revision is Healthy, the H2 firewall query returned rows again, and the workload-silence invariant still held.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full silence-gate bounded-falsification check: baseline-presence, bypass-absence, recovery-presence, workload-silence, held constants, and explicit claim ceiling.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `06-firewall-log-baseline.json`, `08-h1-silence-window.json`, and `12-h2-recovery-window.json` preserve explicit firewall-query windows because the silence-gate claim depends on time-bounded absence versus presence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact Azure Firewall ingestion latency, exact pull durations, OCI layer digests, route-propagation subsecond timing, pod continuity, or the specific internal ACA component identity behind the observed workload-subnet source IP. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Baseline app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | H1 revision list after `v-bypass` reaches Healthy |
| `03-route-table-pre-fix.json` | Route-table inventory after the PE `/32` routes are removed |
| `04-pe-nic-config-pre-fix.json` | PE NIC configuration proving the two ACR private IPs |
| `05-acr-public-access-pre-fix.json` | ACR public-access snapshot during H1 |
| `06-firewall-log-baseline.json` | Baseline firewall-log window proving ACR visibility before the bypass |
| `07-containerapp-spec-pre-fix.yaml` | Full baseline container app YAML |
| `08-h1-silence-window.json` | H1 composite payload: zero firewall rows, v-bypass response, system-log summary |
| `09-route-table-post-fix.json` | Route-table inventory after the PE `/32` routes are restored |
| `10-revision-list-post-fix.json` | H2 revision list after `v-recover` reaches Healthy |
| `11-app-spec-post-fix.json` | Composite post-fix app + ACR + PE NIC surface |
| `12-h2-recovery-window.json` | H2 composite payload: firewall rows restored, v-recover response, system-log summary |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-pe-forced-inspection/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-pe-forced-inspection/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four Phase B gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
