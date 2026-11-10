---
description: Source-pinned inventory of Azure Container Apps lab reproduction scripts, raw evidence, replay gates, run timestamps, cleanup proof, and gaps.
---
# Lab Reproduction Inventory

This static inventory is dated **2026-11-10** and pinned to source commit `5a712e819c5895e9c18e0b5f9c0b152e895b6418`. It queried no Azure resource and incurred no Azure cost. A passing offline `verify.sh` replay is never treated as a fresh Azure reproduction, and cleanup script presence is never treated as cleanup completion.

The machine-readable record is [`lab-reproduction-inventory.json`](lab-reproduction-inventory.json). Regenerate both files intentionally with `python3 scripts/lab_reproduction_inventory.py --write --source-commit <sha> --as-of <date>`; detect drift with `python3 scripts/lab_reproduction_inventory.py --check`.

## Historical reconciliation

Issue #375 named 36 historical labs. The pinned tree contains 36 `labs/` directories.

- Added: none
- Removed: none
- Renamed: none. No rename is asserted without repository evidence linking an old and new directory.

## Classification summary

| Classification | Labs |
|---|---:|
| `blocked` | 7 |
| `live-azure-evidence` | 28 |
| `unknown` | 1 |

`live-azure-evidence` means the committed non-gate cohort records a capture timestamp; it does not mean this inventory reran the lab. `offline-replay-only` is gate evidence without a raw cohort. `blocked`, `documentation-only`, and `unknown` preserve missing proof rather than promoting claims.

## Current lab matrix

| Lab | Classification | Last raw Azure time | Status claimed in docs | Raw files | Gate files | Cleanup proof |
|---|---|---|---|---:|---:|---|
| `labs/aca-secret-kv-ref-mi-network-path` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4b` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4c` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4d` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4e` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4f` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/aca-secret-kv-ref-mi-network-path-h4g` | `blocked` | `unknown` | No explicit status line found | 0 | 0 | `absent` |
| `labs/acr-network-path-dns-forwarder-bypass` | `live-azure-evidence` | `2026-06-29T00:52:56Z` | `docs/troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md:482` — A live reproduction on **2026-06-06** captured the full Scenario E topology and the workload-path falsification surface from the Azure Portal.<br>`labs/acr-network-path-dns-forwarder-bypass/README.md:90` — ├── fix-and-capture.sh          # Phase A live reproduction: deploy, capture the 12 raw files, run verify.sh, and start cleanup | 12 | 4 | `absent` |
| `labs/acr-network-path-firewall-allowlist` | `live-azure-evidence` | `2026-06-29T08:53:17.470748Z` | `docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:13` — status: verified<br>`docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:17` — status: reproduced<br>`docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:424` — Live reproduction in `koreacentral` on 2026-06-06 with Azure CLI `2.79.0`. RG `rg-acr-firewall-allowlist-lab`, ACR `acracrfwallowt2itdu` (`publicNetworkAccess=Enabled`, `defaultAction=Deny`, `networkRuleBypassOptions=None`), Container App `ca-acrfwallow-t2itdu`, firewall public IP `20.196.208.15`... | 12 | 4 | `absent` |
| `labs/acr-network-path-pe-direct` | `live-azure-evidence` | `2026-06-26T12:47:01.879215Z` | `docs/troubleshooting/lab-guides/acr-network-path-pe-direct.md:356` — A live reproduction on **2026-06-05** captured the full Path B topology and the falsification surface. | 12 | 4 | `absent` |
| `labs/acr-network-path-pe-forced-inspection` | `live-azure-evidence` | `2026-06-29T00:42:17Z` | `docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md:358` — > **Status: Reproduced live in koreacentral on 2026-06-06 with Azure CLI 2.79.0.** All three falsification gates PASSED. The actual values from the live run are below.<br>`docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md:389` — Live reproduction in `koreacentral` on 2026-06-06 with Azure CLI `2.79.0`. RG `rg-acr-pe-forced-inspection-lab`, ACR `acracrpefcinhh4rw` (`publicNetworkAccess=Disabled` after step 4 of `trigger.sh`), Container App `ca-acrpefci-nhh4rw`, firewall private IP `<private-ip>.4`, PE `pe-acracrpefcinhh4r...<br>`docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md:522` — A live reproduction on **2026-06-06** captured the full Scenario C topology, the workload-path falsification surface, and the firewall's KQL log evidence from the Azure Portal. | 12 | 4 | `absent` |
| `labs/acr-network-path-record-split-brain` | `live-azure-evidence` | `2026-06-28T22:37:05Z` | `docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md:330` — > **Status: Reproduced live in koreacentral on 2026-06-06 with Azure CLI 2.79.0.** All nine falsification steps PASSED. The actual values from the live run are below.<br>`docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md:360` — Live reproduction in `koreacentral` on 2026-06-06 with Azure CLI `2.79.0`. RG `rg-acr-record-split-brain-lab`, ACR `acracrrecsplitbrainb2jo7q` (`publicNetworkAccess=Disabled`), Container App `ca-acrrecsplitbrain-b2jo7q`, image `record-split-brain-lab:v2` (digest `sha256:aae2111345eba56bcec4a25fbc...<br>`docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md:445` — A live reproduction on **2026-06-06** captured the full Scenario D topology and the workload-path falsification surface from the Azure Portal. | 12 | 4 | `absent` |
| `labs/acr-pull-failure` | `live-azure-evidence` | `2026-06-22T13:28:40Z` | `docs/troubleshooting/lab-guides/acr-pull-failure.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/acr-pull-failure.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/acr-pull-failure.md:18` — notes: 'Three live reproductions: original end-to-end on 2026-05-01 (CLI 2.70.0) confirmed manifest-not-found and recovery; six 2026-06-03 Portal captures independently re-validated the broken-state → recovery arc; scripted 2026-06-22 reproduction (CLI 2.79.0) added structured H1 / H2 gate emissi... | 22 | 6 | `absent` |
| `labs/appgw-to-internal-aca-nsg-mismatch` | `unknown` | `unknown` | No explicit status line found | 11 | 0 | `absent` |
| `labs/appinsights-connection-string-missing` | `live-azure-evidence` | `2026-06-22T05:09:45Z` | No explicit status line found | 20 | 4 | `absent` |
| `labs/cd-reconnect-rbac-conflict` | `live-azure-evidence` | `2026-06-23T12:32:56.311469Z` | `docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md:15` — status: reproduced | 17 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/cpu-throttling` | `live-azure-evidence` | `2026-06-22T08:51:18Z` | No explicit status line found | 15 | 4 | `absent` |
| `labs/dapr-integration` | `live-azure-evidence` | `2026-06-26T10:30:48Z` | `labs/dapr-integration/README.md:13` — ├── fix-and-capture.sh      # Phase A live reproduction: deploy, capture 12 raw files, restore, verify, clean up | 12 | 4 | `absent` |
| `labs/diagnostic-settings-missing` | `live-azure-evidence` | `2026-06-22T09:58:16Z` | No explicit status line found | 20 | 4 | `absent` |
| `labs/image-size-startup-delay` | `live-azure-evidence` | `2026-06-22T02:28:03.376224Z` | `docs/troubleshooting/lab-guides/image-size-startup-delay.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/image-size-startup-delay.md:16` — status: reproduced | 11 | 4 | `absent` |
| `labs/ingress-target-port-mismatch` | `live-azure-evidence` | `2026-06-22T12:31:23Z` | No explicit status line found | 25 | 4 | `absent` |
| `labs/keda-no-metrics-returned` | `live-azure-evidence` | `2026-06-20T00:50:51Z` | `docs/troubleshooting/lab-guides/keda-no-metrics-returned.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/keda-no-metrics-returned.md:16` — status: reproduced | 18 | 4 | `absent` |
| `labs/managed-identity-key-vault-failure` | `live-azure-evidence` | `2026-06-26T08:25:19Z` | `labs/managed-identity-key-vault-failure/README.md:19` — ├── fix-and-capture.sh      # Phase A live reproduction: deploy/reuse RG, capture 12 raw files, apply H2, run verify.sh, and clean up | 12 | 4 | `absent` |
| `labs/memory-leak-oomkilled` | `live-azure-evidence` | `2026-06-20T06:03:15.699370Z` | `docs/troubleshooting/lab-guides/memory-leak-oomkilled.md:14` — status: verified<br>`docs/troubleshooting/lab-guides/memory-leak-oomkilled.md:18` — status: reproduced | 35 | 4 | `absent` |
| `labs/memory-percentage-vs-keda-utilization` | `live-azure-evidence` | `2026-06-24T02:31:25Z` | `docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:319` — Reproduced live in Azure region Korea Central on **2026-06-24** with | 21 | 4 | `absent` |
| `labs/metrics-load-test` | `live-azure-evidence` | `2026-06-29T00:25:19Z` | No explicit status line found | 46 | 0 | `absent` |
| `labs/observability-tracing` | `live-azure-evidence` | `2026-06-24T01:14:05Z` | `docs/troubleshooting/lab-guides/observability-tracing.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/observability-tracing.md:16` — status: reproduced | 24 | 2 | `absent` |
| `labs/probe-and-port-mismatch` | `live-azure-evidence` | `2026-06-23T22:40:05Z` | `docs/troubleshooting/lab-guides/probe-and-port-mismatch.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/probe-and-port-mismatch.md:15` — status: reproduced | 23 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/replica-node-spread` | `live-azure-evidence` | `2026-06-14T14:52:07Z` | `docs/troubleshooting/lab-guides/replica-node-spread.md:24` — status: verified<br>`docs/troubleshooting/lab-guides/replica-node-spread.md:28` — status: reproduced | 15 | 4 | `absent` |
| `labs/revision-failover` | `live-azure-evidence` | `2026-06-22T16:16:34Z` | `docs/troubleshooting/lab-guides/revision-failover.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/revision-failover.md:15` — status: reproduced | 21 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/revision-history-limit` | `live-azure-evidence` | `2026-06-22T08:16:46Z` | No explicit status line found | 14 | 4 | `absent` |
| `labs/revision-provisioning-failure` | `live-azure-evidence` | `2026-06-20T14:26:09Z` | `labs/revision-provisioning-failure/README.md:19` — ├── fix-and-capture.sh      # Phase A live reproduction: deploy/reuse RG, trigger H1, capture 12 raw files, apply H2, call verify.sh | 12 | 4 | `absent` |
| `labs/scale-rule-mismatch` | `live-azure-evidence` | `2026-06-22T15:15:39Z` | `docs/troubleshooting/lab-guides/scale-rule-mismatch.md:10` — status: verified<br>`docs/troubleshooting/lab-guides/scale-rule-mismatch.md:14` — status: reproduced | 23 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/startup-degraded-transient-failure` | `live-azure-evidence` | `2026-06-20T22:51:43Z` | `docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md:29` — status: verified<br>`docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md:33` — status: reproduced | 85 | 4 | `absent` |
| `labs/traffic-routing-canary` | `live-azure-evidence` | `2026-06-24T00:27:42Z` | `docs/troubleshooting/lab-guides/traffic-routing-canary.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/traffic-routing-canary.md:16` — status: reproduced | 25 | 2 | `absent` |
| `labs/zone-redundancy-best-effort` | `live-azure-evidence` | `2026-06-14T11:46:18Z` | `docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md:19` — status: verified<br>`docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md:23` — status: reproduced<br>`labs/zone-redundancy-best-effort/README.md:18` — ├── cleanup.sh                     # Destructive teardown for live reproductions | 50 | 4 | `absent` |

Per-file raw capture ranges, gate `evaluated_at_utc` values, reproduction scripts, exact status quotes, evidence bases, and discrepancy arrays are retained in the JSON.

## Discrepancies

- `labs/aca-secret-kv-ref-mi-network-path`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4b`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4c`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4d`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4e`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4f`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4g`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-dns-forwarder-bypass`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-firewall-allowlist`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-pe-direct`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-pe-forced-inspection`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-record-split-brain`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-pull-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/appgw-to-internal-aca-nsg-mismatch`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/appgw-to-internal-aca-nsg-mismatch`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/appinsights-connection-string-missing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/cpu-throttling`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/dapr-integration`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/diagnostic-settings-missing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/image-size-startup-delay`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/ingress-target-port-mismatch`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/keda-no-metrics-returned`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/managed-identity-key-vault-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/memory-leak-oomkilled`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/memory-percentage-vs-keda-utilization`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/metrics-load-test`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/observability-tracing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/replica-node-spread`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/revision-history-limit`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/revision-provisioning-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/startup-degraded-transient-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/traffic-routing-canary`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/zone-redundancy-best-effort`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.

## Bounded follow-up batches

These are proof-collection queues, not authorization to deploy. This inventory PR has cost class **none** because it performs no Azure work.

| Batch | Labs | Future cost class | Prerequisites |
|---:|---|---|---|
| 1 | `aca-secret-kv-ref-mi-network-path`, `aca-secret-kv-ref-mi-network-path-h4b`, `aca-secret-kv-ref-mi-network-path-h4c`, `aca-secret-kv-ref-mi-network-path-h4d`, `aca-secret-kv-ref-mi-network-path-h4e`, `aca-secret-kv-ref-mi-network-path-h4f`, `aca-secret-kv-ref-mi-network-path-h4g` | `blocked-no-run` | Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment. |
| 2 | `appgw-to-internal-aca-nsg-mismatch` | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |

## See Also

- [Contributing Guide](../contributing/index.md)
- [Lab Gate Evaluation-Time Audit](../contributing/lab-gate-evaluation-time-audit.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)

## Sources

- [Issue #422](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/422)
- [Historical issue #375](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/375)
