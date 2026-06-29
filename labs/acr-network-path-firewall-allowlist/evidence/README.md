# Evidence pack — `acr-network-path-firewall-allowlist` lab

This directory carries the live raw evidence cohort for the `acr-network-path-firewall-allowlist` lab plus the derived Phase B gate outputs emitted by `labs/acr-network-path-firewall-allowlist/verify.sh`.

The claim ceiling is deliberately narrow: this pack proves only what one live `koreacentral` reproduction can support about Path A with one Azure Firewall Basic instance, one ACR Premium registry exposed publicly, one firewall public IP allow-listed in `networkRuleSet.ipRules`, one broken `v-broken` fresh-pull window, one recovered `v-recover` fresh-pull window, and one already-cached `v1` revision that kept serving traffic throughout H1.

## Capture timeline

1. **Baseline-presence proof.** `05-baseline-success-window.json` proves the healthy `v1` pull emitted successful pull markers before the allowlist entry was removed.
2. **H1 failure surface.** `01` through `08` capture the broken window after the firewall public IP was removed from the ACR allowlist and `v-broken` failed with a DENIED/403 surface while the old `v1` revision kept serving.
3. **H2 recovery surface.** `09` through `12` capture the restored allowlist, healthy `v-recover` revision, and successful post-fix pull markers.
4. **Phase B overlay.** `verify.sh` re-parses the raw files and deterministically writes Gate 14 through Gate 17.

## Gate overview

- **Gate 14 — `14-cohort-integrity-gate.json`**: validates canonical file presence, parseability, bounded UTC coherence, pre/post lineage equality, anchor consistency (RG, app, ACR, firewall public IP), and README cross-references.
- **Gate 15 — `15-h1-trigger-produces-failure-gate.json`**: proves baseline presence, confirms the allowlist entry was removed while ACR stayed locked down, proves the DENIED/403 failure named the firewall public IP for `v-broken`, proves the broken revision failed, and proves the old `v1` revision kept serving.
- **Gate 16 — `16-h2-fix-restores-recovery-gate.json`**: proves the allowlist entry was restored, the latest `v-recover` revision is Healthy, the recovery window contains `PullingImage` + `PulledImage`, and the post-fix evidence shows `v-broken` was not retroactively repaired after explicit deactivation.
- **Gate 17 — `17-bounded-falsification-gate.json`**: performs the bounded H1↔H2 diff and carries the non-vacuous silence-gate proof required for this final Path A pack.

## File index

| File | Purpose |
|---|---|
| `01-app-spec-pre-fix.json` | Broken-window container app surface plus capture metadata |
| `02-revision-list-pre-fix.json` | Revision list during H1 showing `v1` plus the failed `v-broken` attempt |
| `03-acr-network-rules-pre-fix.json` | ACR rule set after the firewall public IP was removed |
| `04-firewall-metadata-pre-fix.json` | Firewall public/private IP metadata and policy anchor |
| `05-baseline-success-window.json` | Baseline successful pull window proving non-vacuous success markers |
| `06-system-logs-pre-fix.json` | Structured H1 system-log window containing the DENIED/403 evidence |
| `07-containerapp-spec-pre-fix.yaml` | Full pre-fix container app YAML |
| `08-h1-failure-window.json` | Composite H1 payload: broken-window `/` response, counts, and DENIED rows |
| `09-acr-network-rules-post-fix.json` | ACR rule set after the firewall public IP was restored |
| `10-revision-list-post-fix.json` | Revision list during H2 showing healthy `v-recover` |
| `11-app-spec-post-fix.json` | Composite post-fix app + ACR + firewall surface |
| `12-h2-recovery-window.json` | Composite H2 payload: `v-recover` response and successful pull markers |
| `14-cohort-integrity-gate.json` | Derived Gate 14 output |
| `15-h1-trigger-produces-failure-gate.json` | Derived Gate 15 output |
| `16-h2-fix-restores-recovery-gate.json` | Derived Gate 16 output |
| `17-bounded-falsification-gate.json` | Derived Gate 17 output |

## Reproducibility

```bash
cd labs/acr-network-path-firewall-allowlist/
bash verify.sh
```

The verifier is hermetic: it reads only the committed raw cohort in this directory, rewrites the four Phase B gate JSON files deterministically, prints per-gate verdicts for all 17 gates, and exits `0` only when every gate passes.
