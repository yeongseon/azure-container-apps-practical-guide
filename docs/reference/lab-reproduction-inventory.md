---
description: Source-pinned inventory of Azure Container Apps lab reproduction scripts, raw evidence, replay gates, run timestamps, cleanup proof, and gaps.
---
# Lab Reproduction Inventory

This static inventory is dated **2026-11-10** and pinned to source commit `a9223c0130129de3947898849e02d11820ed615c`. It queried no Azure resource and incurred no Azure cost. A passing offline `verify.sh` replay is never treated as a fresh Azure reproduction, and cleanup script presence is never treated as cleanup completion.

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
| `live-azure-evidence` | 16 |
| `unknown` | 13 |

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
| `labs/acr-network-path-dns-forwarder-bypass` | `live-azure-evidence` | `2026-06-29T00:52:32Z` | `docs/troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md:57` — This behavior was reproduced in **Korea Central on 2026-06-05** with the specific topology described above (ACR Premium PE, dnsmasq on Ubuntu B1s VM as the VNet's custom DNS server with the upstream toggled between `168.63.129.16` and `8.8…<br>`docs/troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md:359` — ### Observed Evidence (Live Azure Test — 2026-06-06)<br>`labs/acr-network-path-dns-forwarder-bypass/evidence/README.md:42` — - The pack captures one live Azure reproduction in `koreacentral`; it… | 12 | 4 | `absent` |
| `labs/acr-network-path-firewall-allowlist` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:13` — status: verified<br>`docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:17` — status: reproduced<br>`docs/troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md:109` — This behavior was reproduced in **Korea Central on 2026-06-29** for the canonical Phase B evidence pack with the specific topology described above (Azure Firewall Basic, ACR Premium with `defaultAction=Deny` + `networkRuleBypassOptions=Non…<br>_6 more in JSON_ | 12 | 4 | `absent` |
| `labs/acr-network-path-pe-direct` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/acr-network-path-pe-direct.md:54` — This behavior was reproduced in **Korea Central on 2026-06-05** with the specific topology described above (ACR Premium with Private Endpoint, `privatelink.azurecr.io` linked DNS zone, Container Apps Consumption profile, managed-identity a…<br>`docs/troubleshooting/lab-guides/acr-network-path-pe-direct.md:293` — ### Observed Evidence (Live Azure Test — 2026-06-05)<br>`labs/acr-network-path-pe-direct/README.md:97` — - It captures one live Azure reproduction in `koreacentral` with ACR `publicNetworkAccess=D…<br>_1 more in JSON_ | 12 | 4 | `absent` |
| `labs/acr-network-path-pe-forced-inspection` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md:59` — This behavior was reproduced in **Korea Central on 2026-06-06** with the specific topology described above (ACR Premium PE, Azure Firewall Basic with FQDN application rules for ACR login and regional data endpoints, Container Apps Consumpt…<br>`docs/troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md:246` — Expected output (from the live run on 2026-06-06): three `az acr build` jobs complete in sequence (~30-60 seconds each, depending on layer cache), `az acr show --query public…<br>_5 more in JSON_ | 12 | 4 | `absent` |
| `labs/acr-network-path-record-split-brain` | `live-azure-evidence` | `2026-06-28T22:36:42Z` | `docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md:61` — This behavior was reproduced in **Korea Central on 2026-06-06** with the specific topology described above (ACR Premium PE, default Azure DNS at `168.63.129.16` in the VNet, `privatelink.azurecr.io` linked through a VNet link that omits `r…<br>`docs/troubleshooting/lab-guides/acr-network-path-record-split-brain.md:330` — > **Status: Reproduced live in koreacentral on 2026-06-06 with Azure CLI 2.79.0.** All nine falsification steps PASSED. The actual values from the live run are below.<br>`docs/tr…<br>_2 more in JSON_ | 12 | 4 | `absent` |
| `labs/acr-pull-failure` | `live-azure-evidence` | `2026-06-22T13:26:42Z` | `docs/troubleshooting/lab-guides/acr-pull-failure.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/acr-pull-failure.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/acr-pull-failure.md:377` — ### Observed Evidence (Live Azure Test — 2026-05-01)<br>_3 more in JSON_ | 22 | 6 | `absent` |
| `labs/appgw-to-internal-aca-nsg-mismatch` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md:50` — - `evidence/` carries the committed `2026-07-04` evidence pack captured on the re-executed live run in Korea Central; see &#91;`labs/appgw-to-internal-aca-nsg-mismatch/evidence/README.md`&#93;(https://github.com/yeongseon/azure-container-apps-prac…<br>`docs/troubleshooting/lab-guides/appgw-to-internal-aca-nsg-mismatch.md:52` — !!! success "Live-executed on 2026-07-03 (initial validation) and 2026-07-04 (re-execution + Portal screenshots)"<br>`docs/troubleshooting/lab-guides/appgw-to-internal-aca-n…<br>_8 more in JSON_ | 11 | 0 | `absent` |
| `labs/appinsights-connection-string-missing` | `unknown` | `unknown` | `labs/appinsights-connection-string-missing/README.md:117` — # 5) Run the falsification experiment (Phase A — Live-Azure reproduction).<br>`labs/appinsights-connection-string-missing/README.md:131` — - **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, builds the instrumented `:v3` image inside the lab's ACR with `az acr build`, switches the Container App to that image WITHOUT the connect…<br>`labs/appinsights-connection-string-missing/evidence/README.md:3` — This directory carries the committed canonical evidence cohort for…<br>_2 more in JSON_ | 20 | 4 | `absent` |
| `labs/cd-reconnect-rbac-conflict` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md:313` — ### Observed Evidence (Live Azure Test — 2026-06-23)<br>_4 more in JSON_ | 17 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/cpu-throttling` | `live-azure-evidence` | `2026-06-22T08:50:19Z` | `labs/cpu-throttling/README.md:88` — # 4) Run the experiment (Phase A — Live-Azure reproduction).<br>`labs/cpu-throttling/README.md:104` — - **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, switches the Container App to the inline `python:3.12-slim` CPU-burn HTTP server (no ACR build — the workload is small enough to inline as…<br>`labs/cpu-throttling/evidence/README.md:3` — This directory carries the committed canonical evidence cohort for the `cpu-throttling` lab, anchored on the live-Azure deployment in `koreacentral` on…<br>_2 more in JSON_ | 15 | 4 | `absent` |
| `labs/dapr-integration` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/dapr-integration.md:368` — ### Observed Evidence (Live Azure Reproduction — Flask-on-8000, 2026-06-26)<br>`labs/dapr-integration/evidence/README.md:22` — - The pack captures a single live Azure cohort; it is not a statistical sample across regions or tenants. | 12 | 4 | `absent` |
| `labs/diagnostic-settings-missing` | `live-azure-evidence` | `2026-06-22T09:50:06Z` | `docs/troubleshooting/lab-guides/diagnostic-settings-missing.md:29` — This lab now uses a two-phase evidence model: Phase A (`trigger.sh` + `fix-and-capture.sh`) captures the live Azure reproduction, and Phase B (`verify.sh`) re-reads the committed evidence pack and emits four derived falsification gates wit…<br>`labs/diagnostic-settings-missing/README.md:105` — # 4) Run Phase A (capture the live Azure evidence cohort).<br>`labs/diagnostic-settings-missing/README.md:116` — This lab now splits the live-Azure reproduction from the offline evidence-pack verification:<br>_1 more in JSON_ | 20 | 4 | `absent` |
| `labs/image-size-startup-delay` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/image-size-startup-delay.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/image-size-startup-delay.md:16` — status: reproduced<br>`docs/troubleshooting/lab-guides/image-size-startup-delay.md:145` — ### Observed Evidence (Live Azure Test — 2026-06-22, koreacentral)<br>_3 more in JSON_ | 11 | 4 | `absent` |
| `labs/ingress-target-port-mismatch` | `live-azure-evidence` | `2026-06-22T12:25:06Z` | `docs/troubleshooting/lab-guides/ingress-target-port-mismatch.md:315` — ### Observed Evidence (Live Azure Test — 2026-05-01)<br>`labs/ingress-target-port-mismatch/README.md:105` — # 4) Run Phase A (live Azure capture).<br>`labs/ingress-target-port-mismatch/README.md:118` — This lab now splits the live-Azure reproduction from the offline evidence-pack verification:<br>_1 more in JSON_ | 25 | 4 | `absent` |
| `labs/keda-no-metrics-returned` | `live-azure-evidence` | `2026-06-20T00:50:25Z` | `docs/troubleshooting/lab-guides/keda-no-metrics-returned.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/keda-no-metrics-returned.md:16` — status: reproduced<br>`docs/troubleshooting/lab-guides/keda-no-metrics-returned.md:19` — notes: 'All three scenarios reproduced in Korea Central against canonical infra rg-aca-no-metrics-lab (azure-cli 2.79.0, containerapp extension 1.3.0b4). Per-scenario evidence captured 2026-06-20T00:48-00:50Z: Scenario A (slow-start, revis…<br>_3 more in JSON_ | 18 | 4 | `absent` |
| `labs/managed-identity-key-vault-failure` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/managed-identity-key-vault-failure.md:370` — ### Observed Evidence (Live Azure Reproduction — 2026-06-03)<br>`labs/managed-identity-key-vault-failure/evidence/README.md:22` — - The pack captures a single live Azure cohort from Jun 26 2026; it is not a statistical sample across regions or tenants. | 12 | 4 | `absent` |
| `labs/memory-leak-oomkilled` | `live-azure-evidence` | `2026-06-20T06:02:57Z` | `docs/troubleshooting/lab-guides/memory-leak-oomkilled.md:14` — status: verified<br>`docs/troubleshooting/lab-guides/memory-leak-oomkilled.md:18` — status: reproduced<br>`docs/troubleshooting/lab-guides/memory-leak-oomkilled.md:21` — notes: "All three scenarios reproduced in Korea Central (rg-aca-memleak-lab). Scenario A (hard-oom) produced 76 exit-code-137 events on revision ca-oom-hard--18xosgl within the first 60 seconds after deployment, then CrashLoopBackOff. Scen…<br>_3 more in JSON_ | 35 | 4 | `absent` |
| `labs/memory-percentage-vs-keda-utilization` | `live-azure-evidence` | `2026-06-24T02:31:25Z` | `docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md:18` — notes: "Re-reproduced in Korea Central on 2026-06-24 with az-cli 2.79.0 and containerapp extension 1.3.0b4, in addition to the original 2026-06-02 run. Scenario A held at replicas_max=2 with mempct=40.0; Scenario B walked to replicas_max=2…<br>_5 more in JSON_ | 21 | 4 | `absent` |
| `labs/metrics-load-test` | `live-azure-evidence` | `2026-06-29T00:25:19Z` | No explicit status line found | 46 | 0 | `absent` |
| `labs/observability-tracing` | `live-azure-evidence` | `2026-06-24T01:14:05Z` | `docs/troubleshooting/lab-guides/observability-tracing.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/observability-tracing.md:16` — status: reproduced<br>`docs/troubleshooting/lab-guides/observability-tracing.md:19` — notes: 'Reproduced end-to-end in rg-aca-lab-observability (koreacentral); baseline secretRef → invalid literal → secretRef restored across revisions 0m6ek7p → 0000001 → 0000002; six Portal captures attached with PII-replacement masking. Te…<br>_5 more in JSON_ | 24 | 2 | `absent` |
| `labs/probe-and-port-mismatch` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/probe-and-port-mismatch.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/probe-and-port-mismatch.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/probe-and-port-mismatch.md:18` — notes: 'Reproduced end-to-end on 2026-06-03 against rg-aca-lab-probe (subscription and resource names redacted). PR-A failure-state captures (2026-06-03 08:47 +0900) confirm: TargetPort 8000 vs gunicorn :3000, --0000001 Failed at 100% traf…<br>_5 more in JSON_ | 23 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/replica-node-spread` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/replica-node-spread.md:24` — status: verified<br>`docs/troubleshooting/lab-guides/replica-node-spread.md:28` — status: reproduced<br>`docs/troubleshooting/lab-guides/replica-node-spread.md:31` — notes: "Phase A live-Azure reproduction on 2026-06-14 in koreacentral (rg-aca-rns-lab) produced the H3 PASS verdict, H1 &#91;Strongly Suggested&#93; confirmed (Consumption scale-30 produced &#91;27, 27, 27&#93; boot_time clusters across 3 top-scale repeat…<br>_4 more in JSON_ | 15 | 4 | `absent` |
| `labs/revision-failover` | `live-azure-evidence` | `2026-06-22T16:16:12Z` | `docs/troubleshooting/lab-guides/revision-failover.md:11` — status: verified<br>`docs/troubleshooting/lab-guides/revision-failover.md:15` — status: reproduced<br>`docs/troubleshooting/lab-guides/revision-failover.md:356` — ### Observed Evidence (Live Azure Test — 2026-05-01)<br>_4 more in JSON_ | 21 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/revision-history-limit` | `live-azure-evidence` | `2026-06-22T08:01:59Z` | `labs/revision-history-limit/README.md:85` — - **Phase A — Live-Azure reproduction.** The original lab that deploys real infrastructure to Azure, runs the 10-update env-var burst, and samples the live revision list at t+0, t+5m, and t+15m. Phase A produced the canonical cohort that l…<br>`labs/revision-history-limit/evidence/README.md:3` — This directory contains the raw evidence artifacts for the `revision-history-limit` lab. The lab is a **bounded-observation** test of the Azure Container Apps preview setting `maxInactiveRevisions` (CLI alias `--revision-history-limit`) —… | 14 | 4 | `absent` |
| `labs/revision-provisioning-failure` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/revision-provisioning-failure.md:360` — ### Observed Evidence (Live Azure Test — 2026-05-01)<br>`docs/troubleshooting/lab-guides/revision-provisioning-failure.md:387` — Reproduced in `rg-aca-lab-rev-prov` / `cae-labrevprov-j2qmuu`, `koreacentral`, Consumption plan. App: `ca-labrevprov-j2qmuu`. Startup probe set to `httpGet.path=/health`, **`port=9999`** (no listener — connection refused), `failureThreshol…<br>`docs/troubleshooting/lab-guides/revision-provisioning-failure.md:438` — Reproduced in `rg-aca-lab-revprov` / `cae-labrevprov-e2upm2`, `koreacentral`, Co… | 12 | 4 | `absent` |
| `labs/scale-rule-mismatch` | `live-azure-evidence` | `2026-06-22T15:12:56Z` | `docs/troubleshooting/lab-guides/scale-rule-mismatch.md:10` — status: verified<br>`docs/troubleshooting/lab-guides/scale-rule-mismatch.md:14` — status: reproduced<br>`docs/troubleshooting/lab-guides/scale-rule-mismatch.md:229` — Gates 10 and 19 were originally emitted during the live run and were later re-evaluated offline from the unchanged raw evidence. Each replay writes its invocation time as top-level `evaluated_at_utc`; this is not a capture or current valid…<br>_2 more in JSON_ | 23 | 2 | `recorded-output-present-not-assumed-complete` |
| `labs/startup-degraded-transient-failure` | `live-azure-evidence` | `2026-06-20T22:41:49Z` | `docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md:29` — status: verified<br>`docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md:33` — status: reproduced<br>`docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md:161` — `trigger.sh --preflight` is the live deployment sanity gate before proceeding to Section 3. The historical `verify.sh` that produced `evidence/verify-001.log` ran 9 live Azure health checks, but the current Phase B `verify.sh` is a replay-…<br>_2 more in JSON_ | 85 | 4 | `absent` |
| `labs/traffic-routing-canary` | `unknown` | `unknown` | `docs/troubleshooting/lab-guides/traffic-routing-canary.md:12` — status: verified<br>`docs/troubleshooting/lab-guides/traffic-routing-canary.md:16` — status: reproduced<br>`docs/troubleshooting/lab-guides/traffic-routing-canary.md:19` — notes: 'Live 50/50 split reproduced via image-swap workaround. The original trigger.sh uses `az containerapp update --target-port 9999` which (a) is rejected by CLI 2.71.0 (unrecognized argument) and (b) is architecturally unable to reprod…<br>_7 more in JSON_ | 25 | 2 | `absent` |
| `labs/zone-redundancy-best-effort` | `live-azure-evidence` | `2026-06-12T12:38:48Z` | `docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md:19` — status: verified<br>`docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md:23` — status: reproduced<br>`docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md:341` — ### Observed Evidence (Live Azure Reproduction) | 50 | 4 | `absent` |

Per-file raw capture ranges, gate `evaluated_at_utc` values, reproduction scripts, exact status quotes, evidence bases, and discrepancy arrays are retained in the JSON.

## Discrepancies

- `labs/aca-secret-kv-ref-mi-network-path`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4b`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4b`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4c`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4c`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4d`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4d`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4e`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4e`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4f`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4f`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/aca-secret-kv-ref-mi-network-path-h4g`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/aca-secret-kv-ref-mi-network-path-h4g`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/acr-network-path-dns-forwarder-bypass`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-firewall-allowlist`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/acr-network-path-firewall-allowlist`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-firewall-allowlist`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/acr-network-path-pe-direct`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/acr-network-path-pe-direct`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-pe-direct`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/acr-network-path-pe-forced-inspection`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/acr-network-path-pe-forced-inspection`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-network-path-pe-forced-inspection`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/acr-network-path-record-split-brain`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/acr-pull-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/appgw-to-internal-aca-nsg-mismatch`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/appgw-to-internal-aca-nsg-mismatch`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/appgw-to-internal-aca-nsg-mismatch`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/appinsights-connection-string-missing`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/appinsights-connection-string-missing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/appinsights-connection-string-missing`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/cd-reconnect-rbac-conflict`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/cd-reconnect-rbac-conflict`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/cpu-throttling`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/dapr-integration`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/dapr-integration`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/dapr-integration`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/diagnostic-settings-missing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/image-size-startup-delay`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/image-size-startup-delay`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/image-size-startup-delay`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/ingress-target-port-mismatch`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/keda-no-metrics-returned`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/managed-identity-key-vault-failure`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/managed-identity-key-vault-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/managed-identity-key-vault-failure`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/memory-leak-oomkilled`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/memory-percentage-vs-keda-utilization`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/metrics-load-test`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/observability-tracing`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/probe-and-port-mismatch`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/probe-and-port-mismatch`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/replica-node-spread`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/replica-node-spread`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/replica-node-spread`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/revision-history-limit`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/revision-provisioning-failure`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/revision-provisioning-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/revision-provisioning-failure`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/startup-degraded-transient-failure`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/traffic-routing-canary`: Raw evidence is committed, but no capture timestamp was found; last Azure run remains unknown.
- `labs/traffic-routing-canary`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.
- `labs/traffic-routing-canary`: Committed artifacts do not contain an explicit capture anchor that establishes a live Azure run time.
- `labs/zone-redundancy-best-effort`: A cleanup script exists, but no committed teardown output proves cleanup ran or completed.

## Bounded follow-up batches

These are proof-collection queues, not authorization to deploy. This inventory PR has cost class **none** because it performs no Azure work.

| Batch | Discrepancy type | Labs | Size | Future cost class | Prerequisites |
|---:|---|---|---:|---|---|
| 1 | `missing-live-run-proof` | `aca-secret-kv-ref-mi-network-path`, `aca-secret-kv-ref-mi-network-path-h4b`, `aca-secret-kv-ref-mi-network-path-h4c`, `aca-secret-kv-ref-mi-network-path-h4d`, `aca-secret-kv-ref-mi-network-path-h4e`, `aca-secret-kv-ref-mi-network-path-h4f`, `aca-secret-kv-ref-mi-network-path-h4g`, `managed-identity-key-vault-failure` | 8 | `blocked-no-run` | Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment. |
| 2 | `missing-live-run-proof` | `acr-network-path-firewall-allowlist`, `acr-network-path-pe-direct`, `acr-network-path-pe-forced-inspection` | 3 | `high` | Explicit cost and cleanup approval; Azure Firewall/Private Endpoint prerequisites. |
| 3 | `missing-live-run-proof` | `appgw-to-internal-aca-nsg-mismatch`, `appinsights-connection-string-missing`, `cd-reconnect-rbac-conflict`, `dapr-integration`, `image-size-startup-delay`, `probe-and-port-mismatch`, `replica-node-spread`, `revision-provisioning-failure` | 8 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 4 | `missing-live-run-proof` | `traffic-routing-canary` | 1 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 5 | `missing-teardown-proof` | `aca-secret-kv-ref-mi-network-path`, `aca-secret-kv-ref-mi-network-path-h4b`, `aca-secret-kv-ref-mi-network-path-h4c`, `aca-secret-kv-ref-mi-network-path-h4d`, `aca-secret-kv-ref-mi-network-path-h4e`, `aca-secret-kv-ref-mi-network-path-h4f`, `aca-secret-kv-ref-mi-network-path-h4g`, `managed-identity-key-vault-failure` | 8 | `blocked-no-run` | Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment. |
| 6 | `missing-teardown-proof` | `acr-network-path-dns-forwarder-bypass`, `acr-network-path-firewall-allowlist`, `acr-network-path-pe-direct`, `acr-network-path-pe-forced-inspection`, `acr-network-path-record-split-brain` | 5 | `high` | Explicit cost and cleanup approval; Azure Firewall/Private Endpoint prerequisites. |
| 7 | `missing-teardown-proof` | `acr-pull-failure`, `appgw-to-internal-aca-nsg-mismatch`, `appinsights-connection-string-missing`, `cpu-throttling`, `dapr-integration`, `diagnostic-settings-missing`, `image-size-startup-delay`, `ingress-target-port-mismatch` | 8 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 8 | `missing-teardown-proof` | `keda-no-metrics-returned`, `memory-leak-oomkilled`, `memory-percentage-vs-keda-utilization`, `metrics-load-test`, `observability-tracing`, `replica-node-spread`, `revision-history-limit`, `revision-provisioning-failure` | 8 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 9 | `missing-teardown-proof` | `startup-degraded-transient-failure`, `traffic-routing-canary`, `zone-redundancy-best-effort` | 3 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 10 | `raw-evidence-without-explicit-capture-anchor` | `managed-identity-key-vault-failure` | 1 | `blocked-no-run` | Policy-free subscription or a Key Vault Private Endpoint redesign; explicit authorization before deployment. |
| 11 | `raw-evidence-without-explicit-capture-anchor` | `acr-network-path-firewall-allowlist`, `acr-network-path-pe-direct`, `acr-network-path-pe-forced-inspection` | 3 | `high` | Explicit cost and cleanup approval; Azure Firewall/Private Endpoint prerequisites. |
| 12 | `raw-evidence-without-explicit-capture-anchor` | `appgw-to-internal-aca-nsg-mismatch`, `appinsights-connection-string-missing`, `cd-reconnect-rbac-conflict`, `dapr-integration`, `image-size-startup-delay`, `probe-and-port-mismatch`, `replica-node-spread`, `revision-provisioning-failure` | 8 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |
| 13 | `raw-evidence-without-explicit-capture-anchor` | `traffic-routing-canary` | 1 | `low-to-moderate` | Azure subscription access, per-lab prerequisites, and a plan to retain raw capture plus teardown output. |

## See Also

- [Contributing Guide](../contributing/index.md)
- [Lab Gate Evaluation-Time Audit](../contributing/lab-gate-evaluation-time-audit.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)

## Sources

- [Issue #422](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/422)
- [Historical issue #375](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/375)
