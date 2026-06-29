# Evidence pack — `acr-network-path-dns-forwarder-bypass` lab

This directory carries the live raw evidence cohort for the `acr-network-path-dns-forwarder-bypass` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-dns-forwarder-bypass/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what a single live `koreacentral` reproduction can support about Path E with one custom dnsmasq forwarder VM, one linked `privatelink.azurecr.io` zone, one ACR Private Endpoint NIC, one upstream swap from Azure DNS to public DNS, one recovery swap back to Azure DNS, and one already-running Container App revision that stayed `Healthy` throughout. It does **not** claim universal applicability across regions, tenants, DNS topologies, or platform versions.

## Reproduction parameters

| Parameter | Value |
|---|---|
| Resource group | `rg-lab-dns-forwarder-bypass-202606290940` |
| Base name | `acrdnsfwdbyp` |
| Suffix | `rdumlp` |
| Build tag | `v1` |
| Azure region | `koreacentral` |
| Registry login FQDN | `acracrdnsfwdbyprdumlp.azurecr.io` |
| Private DNS zone | `privatelink.azurecr.io` |
| dnsmasq VM | `vm-dns-rdumlp` |
| dnsmasq VM private IP | `10.60.5.4` |
| Broken probe capture window | `2026-06-29T00:49:36Z` → `2026-06-29T00:49:37Z` |
| Recovered probe capture window | `2026-06-29T00:52:31Z` → `2026-06-29T00:52:32Z` |
| Broken upstream | `8.8.8.8` |
| Restored upstream | `168.63.129.16` |
| Post-fix composite capture anchor | `2026-06-29T00:52:56Z` |

## Capture timeline

1. **Baseline sanity.** `fix-and-capture.sh` confirms `/probe` returns `first_class=private` before H1; this baseline is intentionally not committed because the canonical 12-file pack centers the H1/H2 contrast.
2. **H1 failure surface.** `01-app-spec-pre-fix.json` through `08-probe-response-pre-fix.json` capture the broken window after dnsmasq is switched to `server=8.8.8.8` and the workload `/probe` converges on `first_class=public`.
3. **H2 recovery surface.** `09-dnsmasq-config-post-fix.json` through `12-recovery-surface-post-fix.json` capture the restored dnsmasq upstream, unchanged DNS/PE/app surface, and the recovered `/probe` response returning `first_class=private`.
4. **Phase B overlay.** `verify.sh` writes Gate 14 through Gate 17 JSONs over the raw cohort without touching Azure.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, single-window UTC coherence, revision-lineage equality, unchanged PE NIC + Private DNS surfaces, and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves dnsmasq really pointed at `8.8.8.8`, `/probe` returned `first_class=public`, the already-running revision stayed `Healthy`, and the H1+H2 failure-event query stayed empty.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves dnsmasq was restored to `168.63.129.16`, `/probe` returned `first_class=private` again, and the same revision stayed `Healthy` with no new revision created during the lab.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the full normalized overlapping H1↔H2 diff, isolates `dnsmasq_upstream` + `first_class` as the trigger fields, and actively checks the workload-path silence invariant.

## Honest disclosure

- The pack captures one live Azure reproduction in `koreacentral`; it is not a statistical sample.
- `07-system-logs-pre-fix.json` is an explicit Log Analytics query payload whose `rows` list is intentionally empty across the H1+H2 window; emptiness is the evidence.
- `08-probe-response-pre-fix.json` and `12-recovery-surface-post-fix.json.probe_capture` preserve every retry attempt explicitly so the verifier never overclaims instantaneous convergence.
- Gate 14 uses file-system UTC anchors (`birthtime`, falling back to `mtime`) so reruns are byte-stable and explicit about the time source for each file.
- The pack does not prove exact DNS timing, exact retry counts, broken-window control-plane fresh pulls, byte-identical backend HTTP bodies, or TLS cipher-suite identity. Those ceilings are carried explicitly in Gate 17 `cohort_binding_note.explicit_drops`.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Pre-fix container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Full revision list in the broken window |
| `03-dnsmasq-config-pre-fix.json` | Broken-window dnsmasq upstream capture from the VM |
| `04-private-dns-record-list-pre-fix.json` | Private DNS A-record inventory during H1 |
| `05-pe-nic-config-pre-fix.json` | PE NIC configuration proving the registry/data private IP map |
| `06-acr-public-access-pre-fix.json` | ACR public access snapshot during H1 |
| `07-system-logs-pre-fix.json` | H1+H2 failure-event KQL payload (expected empty row set) |
| `08-probe-response-pre-fix.json` | Retried `/probe` capture converging on `first_class=public` |
| `09-dnsmasq-config-post-fix.json` | Recovery-state dnsmasq upstream capture from the VM |
| `10-private-dns-record-list-post-fix.json` | Private DNS A-record inventory after recovery |
| `11-revision-list-post-fix.json` | Full revision list after recovery |
| `12-recovery-surface-post-fix.json` | Composite post-fix app + ACR + PE NIC + probe surface |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/acr-network-path-dns-forwarder-bypass/` | Enters the lab directory so the verifier resolves `evidence/` relative paths correctly. |
| `bash verify.sh` | Re-emits the four Phase B gate JSON files from the committed raw cohort without touching Azure. |

```bash
cd labs/acr-network-path-dns-forwarder-bypass/
bash verify.sh
```

The verifier is hermetic: it reads only the committed files in this directory, rewrites the four gate JSONs deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
