---
description: Author-facing reference of per-lab Azure Portal capture matrices for troubleshooting labs. Contributor and agent reference only — see AGENTS.md for authoritative PII rules.
---
# Lab Portal Capture Briefs

!!! info "Audience: contributors and agents, not lab readers"
    This page is an **author-facing reference**. It documents which Azure Portal blades to capture when reproducing each troubleshooting lab, with the filenames the lab's **Observed Evidence** sections already cross-reference. Lab readers do not need to read this page — they consume the captures from each lab's Observed Evidence section directly.

    The captures themselves live under `docs/assets/troubleshooting/<lab-slug>/`. Each lab's `## Observed Evidence` section embeds the PNGs and provides reader-facing analysis. This page exists so that re-reproducing a lab on a fresh Azure environment produces the same filenames in the same order.

## Why this file exists

Previously, every lab guide carried a `## Portal Evidence Capture Guide` section after its Observed Evidence. That section repeated generic capture rules (full-screen browser, no black-box masking, PII replacement) across nine labs, then listed a per-lab capture matrix.

The generic rules are duplicated authoritatively in [AGENTS.md → Portal Screenshot Capture (PII Replacement Rules)](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/AGENTS.md#portal-screenshot-capture-pii-replacement-rules). The duplication caused three problems:

1. **Readers saw author-only content.** Lab readers reached the bottom of each guide and encountered ~30-120 lines of meta-instructions written for the engineer reproducing the lab, not for the engineer learning from it.
2. **The duplicated text drifted.** Seven of nine labs still said "use solid black rectangles" (the old policy); two of nine had been updated to "do **not** use solid black rectangles" (the current policy that matches AGENTS.md). Readers saw contradictory capture guidance depending on which lab they opened.
3. **Per-lab capture matrices were buried inside reader pages.** The matrices are useful — but only to contributors. Consolidating them here keeps the matrices accessible without polluting the reader path.

## Generic capture rules

These apply to every lab. The authoritative source is [AGENTS.md → Portal Screenshot Capture (PII Replacement Rules)](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/AGENTS.md#portal-screenshot-capture-pii-replacement-rules). Summary:

- **Full-screen browser capture only.** Capture the entire browser window (URL bar, Portal chrome, breadcrumb). Do not crop to a single chart — reviewers must be able to verify the blade, filters, and time range.
- **PII must be replaced with placeholder text, never black-box masked.** Use the shared helper at [`scripts/portal-capture-helpers.js`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.js) — or the inline `browser_run_code_unsafe` snippet documented in AGENTS.md — to rewrite GUIDs to `00000000-0000-0000-0000-000000000000`, `MCAPS*` subscription names to `Visual Studio Enterprise Subscription`, the `Microsoft Non-Production` tenant badge to `Contoso`, employee emails / aliases / display names to `user@example.com` / `demouser` / `Demo User`, and `*.onmicrosoft.com` to `contoso.onmicrosoft.com`. The Account-menu avatar (the only DOM element that cannot be textually rewritten) is masked using Playwright's native `mask` with Portal blue (`#0078d4`).
- **Solid black rectangles are forbidden.** They look like leaks and break visual continuity. If a value cannot be rewritten and is not a known avatar/badge, fail the capture and update the PII rules rather than fall back to a black rectangle.
- **Re-open every committed PNG and verify visually.** Confirm no `MICROSOFT NON-PRODUCTION` badge, no real subscription / tenant GUIDs, no `*@microsoft.com` / `Yeongseon Choe` / `ychoe`, and the avatar is the solid Portal-blue square (not black).

### PII verification checklist (apply to every PNG before commit)

- [ ] All GUIDs (subscription, tenant, object, principal, resource IDs, correlation IDs) rendered as `00000000-0000-0000-0000-000000000000`
- [ ] Subscription name rendered as `Visual Studio Enterprise Subscription` (no `MCAPS-*` prefix)
- [ ] Tenant badge in the top-right rendered as `Contoso` (no `MICROSOFT NON-PRODUCTION` text)
- [ ] No `*@microsoft.com` or `*@*.onmicrosoft.com` emails anywhere in the frame
- [ ] No `ychoe` or `Yeongseon Choe` anywhere (rewritten to `demouser` / `Demo User`)
- [ ] `*.onmicrosoft.com` bare domains rendered as `contoso.onmicrosoft.com`
- [ ] Account-menu avatar masked with solid Portal-blue (`#0078d4`), not a black rectangle
- [ ] Global search bar dropdown is dismissed (recent resources from other labs must not be visible)
- [ ] Search bars, filter chips, and input controls scrubbed (the helper covers `input.value` and `textarea.value`)
- [ ] Real customer resource group / app / environment names renamed to lab defaults if reused from a customer tenant

## Per-lab capture matrices

Each section below documents the captures committed under `docs/assets/troubleshooting/<lab-slug>/` and embedded in the corresponding lab's **Observed Evidence** section. Reuse the same filenames when re-reproducing a lab on a fresh environment so the image references continue to resolve.

### acr-network-path-dns-forwarder-bypass

The 6 captures committed under `docs/assets/troubleshooting/acr-network-path-dns-forwarder-bypass/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After deploy | Container Apps environment → Networking | VNet integration on, workload subnet `snet-aca` listed | `01-cae-networking-blade.png` |
| 2 | After deploy | Virtual Network → Overview (DNS servers section) | Custom DNS server `10.60.5.4` configured (NOT Azure-provided DNS) — anchors the "custom resolver in front of the linked Private DNS Zone" topology | `02-vnet-custom-dns.png` |
| 3 | After deploy | Azure Container Registry → Networking → Public access tab | `Public network access: Disabled` | `03-acr-public-access-disabled.png` |
| 4 | After deploy | ACR → Networking → Private access tab | Approved private endpoint `pe-acracrdnsfwd34jpw6` with `Connection state: Approved` | `04-acr-private-endpoint-approved.png` |
| 5 | After deploy | Private DNS zone `privatelink.azurecr.io` → Recordsets | A records mapping the ACR registry FQDN + data endpoint FQDN to the PE NIC IPs | `05-private-dns-records.png` |
| 6 | After deploy | Container App → Revisions and replicas | Revision `--0000002` with `Running status: Running at max`, `Traffic: 100%`, `1 replica` — proves the DNS forwarder topology eventually resolves ACR through the linked Private DNS Zone | `06-revisions-healthy.png` |

### acr-network-path-firewall-allowlist

The 8 captures committed under `docs/assets/troubleshooting/acr-network-path-firewall-allowlist/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After deploy | Container Apps environment → Networking | VNet integration on, workload subnet `snet-aca` listed | `01-cae-networking-blade.png` |
| 2 | After deploy | Virtual Network → Overview | Address space `10.80.0.0/16` with three subnets visible | `02-vnet-overview.png` |
| 3 | During the active-allowlist window (PR-A) | ACR → Networking → Public access tab | `Selected networks` with firewall public IP `20.196.208.15` listed in `networkRuleSet.ipRules` | `03-acr-networking-public-ipallowlist.png` |
| 4 | After deploy | Azure Firewall → Overview | Basic SKU, public IP `20.196.208.15`, private IP `10.80.2.4` | `04-firewall-overview.png` |
| 5 | After deploy | Firewall policy → Application rules | 4 rules: `allow-acr-login`, `allow-acr-data`, `allow-mcr`, `allow-acs-mirror` | `05-firewall-policy-app-rules.png` |
| 6 | After deploy | Route table → Routes | `default-via-afw` UDR `0.0.0.0/0` → Virtual appliance `10.80.2.4` (forces all egress through the firewall and pins the SNAT source IP) | `06-route-table.png` |
| 7a | After fix is applied | Container App → Revisions and replicas → **Active revisions** tab | Active revision `--0000003` `Running at max` with `100%` traffic | `07a-revisions-active.png` |
| 7b | After fix is applied | Container App → Revisions and replicas → **Inactive revisions** tab | Inactive revisions `--y5eac1h` (bootstrap), `--0000001` (v1), `--0000002` (v-broken) all deactivated — documents the full revision history during the experiment | `07b-revisions-inactive.png` |

### acr-network-path-pe-direct

The 7 captures committed under `docs/assets/troubleshooting/acr-network-path-pe-direct/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Healthy baseline | Container App → Overview | `Status: Running`, populated `Application Url` | `01-app-overview-running.png` |
| 2 | Healthy baseline | Container App → Revisions and replicas | Latest revision `Running (at max)`, 100% traffic, 1 replica | `02-revisions-healthy-v1.png` |
| 3 | Healthy baseline | ACR → Networking | `Public network access: Disabled`, approved PE connection visible | `03-acr-networking-private.png` |
| 4 | Healthy baseline | Private Endpoint → Overview | NIC IPs visible in the PE subnet | `04-pe-overview-nic.png` |
| 5 | Healthy baseline | Private Endpoint → DNS configuration | Both ACR FQDNs (registry + data endpoint) mapped to PE NIC IPs | `05-pe-dns-config.png` |
| 6 | Healthy baseline | Private DNS zone `privatelink.azurecr.io` → Recordsets | A records pointing to PE NIC IPs | `06-private-dns-records.png` |
| 7 | During falsification window | Container App → Replicas | Split-replica state — one `Running` replica alongside one `Not running` replica, capturing the moment a fresh replica fails to pull while the existing replica's cached image keeps it healthy (the split-replica window that distinguishes "PE works" from "PE is misconfigured") | `07-revisions-unhealthy-broken.png` |

### acr-network-path-pe-forced-inspection

The 10 captures committed under `docs/assets/troubleshooting/acr-network-path-pe-forced-inspection/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After deploy | Container Apps environment → Networking | VNet integration on, workload subnet `snet-aca` listed | `01-cae-networking-blade.png` |
| 2 | After deploy | VNet → Subnets | `snet-aca`, `snet-pe`, `AzureFirewallSubnet`, `AzureFirewallManagementSubnet` with CIDR and delegations | `02-vnet-subnets.png` |
| 3 | After deploy | ACR → Networking → Public access tab | `Public network access: Disabled` | `03-acr-networking.png` |
| 4 | After deploy | ACR → Networking → Private access tab | Approved Private Endpoint `pe-acracrpefcinhh4rw` | `04-acr-private-endpoint.png` |
| 5 | After deploy | Azure Firewall → Overview | Basic SKU, private IP `10.90.3.4` | `05-firewall-overview.png` |
| 6 | After deploy | Firewall policy → Application rules | 4 rules: `allow-acr-login`, `allow-acr-data`, `allow-mcr`, `allow-acs-mirror` | `06-firewall-app-rules.png` |
| 7 | After deploy (the smoking gun) | Route table → Routes | `default-via-afw` PLUS two `/32` UDRs `pe-10-90-2-4` + `pe-10-90-2-5` all pointing at firewall private IP `10.90.3.4` — the two `/32` routes are the structural defect that forces PE-bound traffic through the firewall instead of taking the direct PE path | `07-route-table-routes.png` |
| 8 | After deploy | Private Endpoint NIC → Overview | Primary private IP `10.90.2.4` | `08-pe-nic-overview.png` |
| 9 | After deploy | Private Endpoint → DNS configuration | Both FQDN-to-IP mappings: data endpoint `10.90.2.4`, login endpoint `10.90.2.5` | `09-pe-dns-configuration.png` |
| 10 | After load applied | Log Analytics → Logs (Azure Firewall workspace) | KQL against `AZFWApplicationRule` returning 15 rows of `acracrpefcinhh4rw.azurecr.io` and data-endpoint FQDN matches sourced from `snet-aca` IP `10.90.1.160` — proves the firewall is silently inspecting PE-bound traffic that should be taking the direct PE path | `10-law-azfw-kql.png` |

!!! warning "Capture 07 is the smoking gun"
    The two `/32` UDR entries (`pe-10-90-2-4`, `pe-10-90-2-5`) pinned to the firewall private IP are the structural defect for this lab. Without those `/32` routes, ACA-to-ACR traffic would take the direct PE path; with them, the firewall silently inspects every PE-bound request, surfacing as a class of "ACR is private but throughput is wrong" symptoms. Capture 10's LAW KQL is the firewall-log proof.

### acr-network-path-record-split-brain

The 7 captures committed under `docs/assets/troubleshooting/acr-network-path-record-split-brain/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After deploy | Container Apps environment → Networking | VNet integration on, workload subnet `snet-aca` listed | `01-cae-networking-blade.png` |
| 2 | After deploy | Virtual Network → Overview (DNS servers section) | `DNS servers: Azure provided DNS service` (default — NOT a custom resolver, to isolate the per-record authority failure mode from the resolver-topology failure mode covered by acr-network-path-dns-forwarder-bypass) | `02-vnet-default-azure-dns.png` |
| 3 | After deploy | ACR → Networking → Public access tab | `Public network access: Disabled` | `03-acr-public-access-disabled.png` |
| 4 | After deploy | ACR → Networking → Private access tab | Approved private endpoint `pe-acracrrecsplitbrainb2jo7q` with registry and data-endpoint FQDN split | `04-acr-private-endpoint-approved.png` |
| 5a | Baseline (PR-A, healthy) | Private DNS zone `privatelink.azurecr.io` → Recordsets | **3 record sets**: SOA + registry A + data A | `05a-private-dns-records-baseline.png` |
| 5b | Broken state (PR-B) | Private DNS zone `privatelink.azurecr.io` → Recordsets | **Only 2 record sets**: SOA + registry A — the data A record has been deleted, producing the per-record authority failure (registry FQDN still resolves through the linked zone, but data-endpoint FQDN fails authority and falls back to public DNS) | `05b-private-dns-records-broken.png` |
| 6 | After fix is applied | Container App → Revisions and replicas | Revision `--0000002` `Running at max`, `Traffic: 100%`, `1 replica` — proves the recovery once the missing data A record is restored | `06-revisions-healthy.png` |

!!! note "Capture pair 05a / 05b is the proof"
    The split-brain failure mode is invisible at the zone-level (the zone exists and is linked to the VNet in both states). The proof lives in the Recordsets blade contents: 3 records in the baseline state (capture 05a) vs 2 records in the broken state (capture 05b). Re-shoot both captures on the **same zone resource** so the only visual difference is the row count in the Recordsets list.

### acr-pull-failure

!!! warning "Failure-mode-specific evidence surfaces"
    The captures listed below assume the pull failure occurs **after** a revision has been created (for example, a tag that exists but cannot be pulled due to auth, or a registry network failure during pull). For the **manifest-missing-before-revision** case reproduced in the 2026-06-03 subsection — where the image tag does not exist in ACR — the platform never creates a revision and the system log table is never materialized. In that case, use the surfaces shown in that subsection instead: **Overview** (Status `Unknown`, `Application Url = Ingress disabled`), **Revisions and replicas** (empty Active and Inactive tabs), and **Activity Log → Create or Update Container App: Failed** (Summary tab only — the JSON tab is rendered by a Monaco editor that bypasses the standard PII replacement helper).

The 6 captures committed under `docs/assets/troubleshooting/acr-pull-failure/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | During the incident (after the failed deployment) | Container App → Overview | Essentials panel showing `Status = Unknown` and `Application Url = Ingress disabled` — the platform never assigned an FQDN because no revision reached an ingress-ready state | `01-overview-unknown.png` |
| 2 | During the incident | Container App → Revisions and replicas | Both the **Active** and **Inactive** tabs render "No revisions to display" — the manifest pull failed so early that the platform never created a revision row | `02-revisions-no-revision.png` |
| 3 | During the incident | Container App → Activity log | List view filtered to the resource group, showing a single `Create or Update Container App` operation with `Status = Failed`, originated by the deployment principal | `03-activity-log-failed.png` |
| 4 | During the incident | Activity log → failed operation → Summary tab | Summary tab only — terminal status `Failed`, event category `ResourceOperationFailure`. **Do not capture the JSON tab**: it is rendered by a Monaco editor that bypasses the standard PII replacement helper | `04-activity-log-detail.png` |
| 5 | After the fix is applied (`az acr build` + `az containerapp update --image labacr:v1`) | Container App → Overview | Essentials panel showing `Status = Running` and a populated `Application Url` after the platform creates the recovered revision | `05-overview-recovered.png` |
| 6 | After the fix is applied | Container App → Revisions and replicas | Recovered revision in `Health state = Healthy`, `Running state = RunningAtMaxScale`, 100% traffic, 1 replica | `06-revisions-healthy.png` |

### cd-reconnect-rbac-conflict

The 5 captures committed under `docs/assets/troubleshooting/cd-reconnect-rbac-conflict/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Immediately after `./trigger.sh` finishes | Resource Group → Deployments | Default list view showing seed `lab-cd-rbac` and `lab-ra-initial` Succeeded plus `lab-ra-reconnect` Failed | `01-deployments-list.png` |
| 2 | Same point as #1 | Resource Group → Deployments → `lab-ra-reconnect` | Deployment detail with "Your deployment failed" banner and the `RoleAssignmentExists` error containing the existing 32-char-hex assignment ID | `02-deployment-failed-detail.png` |
| 3 | During diagnosis | Azure Container Registry → Access control (IAM) → **Role assignments** tab | Use the scoped "Search by name" filter inside the IAM blade (NOT the global search bar) and filter to `github-actions-lab`; expect exactly one `AcrPush` assignment for the simulated CD service principal | `03-iam-orphaned-assignment.png` |
| 4 | After `./verify.sh` completes Step 4 (retry) | Resource Group → Deployments → `lab-ra-verify-recovery` | Deployment detail with green "Your deployment is complete" banner | `04-deployment-recovered.png` |
| 5 | After `./verify.sh` completes Step 5 | Azure Container Registry → Access control (IAM) → **Role assignments** tab | Same scoped filter as #3; expect exactly one active `AcrPush` assignment (the freshly created one, different underlying GUID from #3 — verify in CLI output since the GUID renders as the zero-GUID placeholder after PII replacement) | `05-iam-after-fix.png` |

### cold-start-scale-to-zero

The 2 captures committed under `docs/assets/troubleshooting/cold-start-scale-to-zero/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After `min replicas` is set to 0 and the configuration is applied | Container App → Application → Scale and replicas | Scale blade showing `Min replicas: 0`, `Max replicas: 10`, `Cooldown period: 300`, `Polling interval: 30`, `Current number of replicas: 0`, and the `http-scaler` rule of type HTTP scaling | `01-scale-blade-min-zero.png` |
| 2 | After cooldown elapses with no inbound traffic | Container App → Revisions and replicas | Revision `--0000005` with `Running status: Scaled to 0`, `Traffic: 100%`, and `0 replicas` — the platform-level proof that scale-to-zero has fired | `02-revisions-scaled-to-zero.png` |

### dapr-integration

The 6 captures committed under `docs/assets/troubleshooting/dapr-integration/`:

| # | When in the reproduction | Portal blade | What to verify on-screen | Filename |
|---|---|---|---|---|
| 1 | Baseline (before `trigger.sh`) | Container App → Overview | `Status: Running`, `Location: Korea Central`, `Resource group: rg-aca-lab-dapr`, `Application Url` populated | `01-overview.png` |
| 2 | Baseline (before `trigger.sh`) | Container App → Dapr | `Dapr: Enabled`, `App ID: dapr-labdapr-bh2uom`, `App port: 8000`, `App protocol: HTTP` | `02-dapr-baseline-appport-8000.png` |
| 3 | After trigger (CLI workaround applied) | Container App → Dapr (click **Refresh** in blade) | `App port: 8081`, `Dapr: Enabled`, `App ID: dapr-labdapr-bh2uom`, `App protocol: HTTP` | `03-dapr-after-trigger-appport-8081.png` |
| 4 | After trigger | Container App → Revisions | Revision `ca-labdapr-bh2uom--xafdl2m` row: `Running status: Degraded`, `Traffic: 100%`, `Replicas: 2` | `04-revisions-degraded.png` |
| 5 | After trigger | Container App → Containers (**Properties** tab) | `Image and tag: azuredocs/containerapps-helloworld:latest`, `Registry login server: mcr.microsoft.com` — anchors the `[Not Proven]` causation caveat | `05-containers-helloworld-image.png` |
| 6 | After restoring `--dapr-app-port 8000` (CLI workaround applied) | Container App → Revisions | Revision `ca-labdapr-bh2uom--xafdl2m` still shows `Running status: Degraded` — directly demonstrates the `[Not Proven]` causation caveat | `06-revisions-still-degraded-after-restore.png` |

!!! warning "Dapr blade stale-cache caveat"
    The Dapr blade has a known stale-cache behavior: the inline **Refresh** button inside the blade iframe must be clicked after applying a CLI mutation, otherwise the previous value persists in the panel even though the underlying resource has changed.

### ingress-target-port-mismatch

The 16 captures committed under `docs/assets/troubleshooting/ingress-target-port-mismatch/` are organized as **8 failure/fix pairs**. The lab's Observed Evidence section walks through them in pair order so that each post-fix capture sits directly next to its pre-fix counterpart on the same Portal blade with the same view / filters — making the falsification argument visual.

Re-shoot both captures of every pair on the **same revision name** (the failure and the fix are on the same revision — ingress is an application-scope setting and ingress updates do not create new revisions). Use the verification CLI documented in the lab's Observed Evidence section to confirm `LatestRevisionName` is identical across both windows before committing.

| Pair | Portal blade | Failure capture (pre-fix) | Fix capture (post-fix) |
|---|---|---|---|
| 1 | Container App → Overview | `case-trap-01-overview-running-but-degraded.png` — `Status: Running` plus the fourth **"Issues"** tab alongside `Essentials`, `Properties`, `Capabilities` | `case-trap-09-overview-fixed-no-issues-tab.png` — only three tabs, the **"Issues"** tab is gone |
| 2 | Container App → Revisions and replicas | `case-trap-02-revisions-degraded.png` — active revision in **Degraded** state with the warning icon | `case-trap-10-revisions-healthy-fixed.png` — same revision name in **Healthy / Running** state with the success icon |
| 3 | Revisions and replicas → revision row → "View details" flyout | `case-trap-03-revision-status-details-flyout.png` — verbatim platform message `The TargetPort 8001 does not match the listening port 80. 1/1 Container crashing: containerapps-helloworld` | `case-trap-11-revision-detail-fixed.png` — placeholder text `There are no additional running status details at this time.` |
| 4 | Container App → Ingress | `case-trap-04-ingress-targetport-8001.png` — `Target port: 8001` | `case-trap-12-ingress-targetport-80-fixed.png` — `Target port: 80` |
| 5 | Container App → Containers | `case-trap-05-containers-image-config.png` — image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` (control variable) | `case-trap-13-containers-fixed.png` — identical image (same listening port `:80`) |
| 6 | Container App → Monitoring → Metrics | `case-trap-06-metrics-503-spike.png` — `Requests` chart with sustained 5xx spike during the failure window | `case-trap-14-metrics-200-fixed.png` — same `Requests` chart with the post-fix 2xx burst (`Sum Requests = 327`) |
| 7 | Container App → Log stream | `case-trap-07-logstream-listening-port-80.png` — container emitting `Listening on :80` during the failure | `case-trap-15-logstream-fixed.png` — same `Listening on :80` after the fix (the "dog that did not bark") |
| 8 | Log Analytics → KQL query editor | `case-trap-08-loganalytics-kql-targetport.png` — result row with the verbatim `TargetPort 8001 does not match the listening port 80` message | `case-trap-16-loganalytics-fixed.png` — **same query** over `ago(5m)` returning `No results found` |

### keda-no-metrics-returned

The 7 captures committed under `docs/assets/troubleshooting/keda-no-metrics-returned/`. The lab reproduces three scenarios sharing the same KEDA scale rule (`metadata.type=Utilization`) to isolate when the "no metrics returned" warning is a real failure signal vs. a benign warm-up artifact.

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Scenario A `ca-nometrics-slow`, during the first ~90 seconds after deployment | Container App → Log stream (Category: System) | "no metrics returned" entries appearing during the startup-probe window; errors stop after the container becomes Ready; Replica Count stays at 1 | `scenario-a-slow-system-logs.png` |
| 2 | Scenario A, same time as #1 | Container App → Monitoring → Metrics | `Memory Percentage` and `Replica Count` split for the slow-start window; Memory stays low because the container is still sleeping/initializing and not yet serving requests | `scenario-a-slow-metrics.png` |
| 3 | Scenario B `ca-nometrics-crash`, during CrashLoopBackOff | Container App → Log stream (Category: System) | Recurring "no metrics returned" / "invalid metrics" entries plus container exit code 1 (`ProcessExited`) events; the pattern repeats with increasing intervals as Kubernetes applies CrashLoopBackOff exponential backoff | `scenario-b-crash-system-logs.png` |
| 4 | Scenario B, same time as #3 | Container App → Monitoring → Metrics | `Total Replica Restart Count` platform metric showing the matching restart trace | `scenario-b-crash-restart-count.png` |
| 5 | Scenario C `ca-nometrics-healthy`, during the first ~60 seconds after deployment | Container App → Log stream (Category: System) | ~10 "no metrics returned" entries during the first ~60 seconds then no further errors; Total Replica Restart Count remains 0 | `scenario-c-healthy-system-logs.png` |
| 6 | All scenarios, post-deployment | Log Analytics → KQL query editor | `summarize` of `type=DEPRECATED` warning messages by `ContainerAppName_s` across all three apps; expect exactly one DEPRECATED warning per app | `all-deprecated-warning.png` |
| 7 | All scenarios, post-deployment | Log Analytics → KQL query editor | `render timechart` of "no metrics returned" / "invalid metrics" / "failed to get" entries bucketed by 5-minute bins and broken out by `ContainerAppName_s`; initial deployment burst concentrated in the first bin (~25 errors) tailing off to a ~1-error-per-5-minute-bin baseline dominated by the crash-loop app | `kql-error-timeline.png` |

!!! note "Capture 5 (Scenario C) is the differential negative control"
    The lab body identifies capture 5 (`scenario-c-healthy-system-logs.png`) as **the most important screenshot in the lab: it proves the error appears even when nothing is wrong with the container**. Scenario C's container started instantly but the Kubernetes Metrics Server needed ~60s to warm up for the new pod, and `Total Replica Restart Count` is 0. Without capture 5, the Scenario A and B "no metrics returned" entries could be misread as caused by the slow-start or crash-loop conditions; capture 5 falsifies that misreading by showing the same warning text on a fully healthy container. Re-capture must preserve the System-category filter and confirm `Total Replica Restart Count = 0` for `ca-nometrics-healthy` at the same capture time.

### managed-identity-key-vault-failure

The 6 captures committed under `docs/assets/troubleshooting/managed-identity-key-vault-failure/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | During diagnosis | Container App → Identity | System-assigned identity blade with `Status: On` and object (principal) ID visible | `01-identity-blade-system-assigned-on.png` |
| 2 | During diagnosis, before RBAC fix | Key Vault → Access control (IAM) → Role assignments | Filter by the Container App principal name; result count `All (0)` with `No results.` | `02-kv-iam-no-role-for-app-principal.png` |
| 3 | During the incident | Container App → Revisions and replicas | Active revision shown as `Running` with healthy replicas while the secret-dependent endpoint is failing | `03-revisions-running-during-incident.png` |
| 4 | During the incident | Container App → Monitoring → Metrics | `Requests` metric, last 30 minutes, split by `Status Code Category`; chart dominated by 5xx | `04-metrics-requests-5xx-during-incident.png` |
| 5 | After the RBAC fix | Key Vault → Access control (IAM) → Role assignments | Same principal-name filter, now showing 1 result: `Key Vault Secrets User` assigned to the app principal | `05-kv-iam-role-assigned-after-fix.png` |
| 6 | After the fix | Container App → Monitoring → Metrics | Same `Requests` / `Status Code Category` split, time range extended to include post-fix traffic; 2xx rises alongside the earlier 5xx population | `06-metrics-requests-2xx-after-fix.png` |

!!! tip "Why Metrics, not Log stream"
    Gunicorn in the lab image is configured without access logs, and the Flask handler catches the Key Vault exception and returns it in the HTTP 500 response body. The **Log stream** blade therefore contains no useful failure signal. **Metrics → Requests split by Status Code Category** is the correct Portal evidence for this lab — it shows the 5xx population during the incident and the 2xx recovery after the role assignment.

### memory-leak-oomkilled

The 62 captures committed under `docs/assets/troubleshooting/memory-leak-oomkilled/`. The lab compares three scenarios sharing one Container Apps environment and one Log Analytics workspace: `ca-oom-hard` (Hard OOM at startup, allocates ~600 MiB above the 0.5Gi ceiling), `ca-oom-leak` (gradual leak, 30 MiB per tick until the ceiling), and `ca-oom-healthy` (control). The captures are organized into 8 cluster groups that mirror the lab body's `## 6) Portal Evidence` H3 sections.

#### Resource Group landing (capture 01)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Anytime after `./trigger.sh` provisions the three scenarios | Resource group `rg-aca-memleak-lab` → Overview | Default resource list showing the Log Analytics workspace, ACR, Container Apps environment, and the three Container Apps (`ca-oom-hard`, `ca-oom-leak`, `ca-oom-healthy`) | `01-resource-group-overview.png` |

#### Scenario A — `ca-oom-hard` (Hard OOM, captures 02-16d-full)

**Overview and revisions during failure** (captures 02-04):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 2 | During the live incident, before `trigger-fix.sh` | `ca-oom-hard` → Overview | `ProvisioningState: Failed`, `RunningStatus: Stopped` | `02-ca-oom-hard-overview.png` |
| 3 | Same | `ca-oom-hard` → Revisions and replicas | Failing revision `ca-oom-hard--18xosgl` visible | `03-ca-oom-hard-revisions.png` |
| 4 | Same | Revisions and replicas → revision row → detail flyout | `HealthState: Unhealthy` | `04-ca-oom-hard-revision-detail.png` |

**Container configuration and scale rule** (captures 05-06):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 5 | During incident | `ca-oom-hard` → Containers → Properties tab | `memory: 0.5Gi`, `cpu: 0.25`; the failing-revision env vars `MODE=hard-oom` and `HARD_OOM_MB=600` are set by `trigger-scenario-a.sh` and visible in the **Environment variables** tab of the same blade (not captured here) | `05-ca-oom-hard-containers.png` |
| 6 | Same | `ca-oom-hard` → Scale | Active KEDA configuration `min 1`, `max 1` | `06-ca-oom-hard-scale.png` |

**Log stream during CrashLoopBackOff** (captures 07-08):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 7 | During incident | `ca-oom-hard` → Log stream (Category: System) | `ContainerTerminated` / `ProcessExited` entries with `exit code '137'` | `07-ca-oom-hard-logstream-system.png` |
| 8 | Same | `ca-oom-hard` → Log stream (Category: Application) | `[hard-oom] allocating ...` line followed by `[hard-oom] allocated N/600 MiB` progress climbing to ~400-450 MiB and then nothing — the expected `[app] listening on :8000` line is **never** printed because the kernel killed the process during the allocation loop, before `serve()` was reached | `08-ca-oom-hard-logstream-application.png` |

**Metrics during failure** (captures 09-13):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 9 | During incident | `ca-oom-hard` → Monitoring → Metrics | `Memory Percentage` — at cgroup ceiling | `09-ca-oom-hard-metric-memory-percentage.png` |
| 10 | Same | Metrics | `Memory Working Set Bytes` — same shape in absolute bytes | `10-ca-oom-hard-metric-memory-working-set-bytes.png` |
| 11 | Same | Metrics | `CPU Usage` — near zero (container exits before doing significant work) | `11-ca-oom-hard-metric-cpu-usage.png` |
| 12 | Same | Metrics | `RestartCount` — climbing in steps | `12-ca-oom-hard-metric-restart-count.png` |
| 13 | Same | Metrics | `Replica Count` — flipping between 0 and 1 as Kubernetes attempts and aborts restarts | `13-ca-oom-hard-metric-replica-count.png` |

**Logs (KQL) and Activity Log during failure** (captures 14-15):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 14 | During incident | Log Analytics → Logs blade | Cross-scenario exit-event KQL confirming failure pattern is isolated to `ca-oom-hard` | `14-ca-oom-hard-logs-kql.png` |
| 15 | During incident | `ca-oom-hard` → Activity Log | Every `Create or Update Container App` operation against the resource | `15-ca-oom-hard-activity-log.png` |

**Diagnose and Solve during the live incident, pre-fix** (captures 16, 16b, 16c, 16d, 16d-full):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 16 | During incident, failing revision still active | `ca-oom-hard` → Diagnose and Solve Problems | Landing page | `16-ca-oom-hard-diagnose.png` |
| 16b | Same | Diagnose and Solve → Availability and Performance | Category overview while the failing revision is active | `16b-ca-oom-hard-diagnose-availability.png` |
| 16c | Same | Diagnose and Solve → Container App Memory Usage detector | Thresholds exceeded | `16c-ca-oom-hard-diagnose-memory-usage.png` |
| 16d | Same | Diagnose and Solve → Container Exit Events detector | Exit code 137 cluster | `16d-ca-oom-hard-diagnose-exit-events.png` |
| 16d-full | Same | Diagnose and Solve → Container Exit Events detector | Full-blade view for completeness alongside 16d | `16d-ca-oom-hard-diagnose-exit-events-full.png` |

#### Scenario B — `ca-oom-leak` (Gradual leak, captures 17-25)

**Overview, containers, scale** (captures 17-19):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 17 | During gradual leak | `ca-oom-leak` → Overview | Active revision in the leak window | `17-ca-oom-leak-overview.png` |
| 18 | Same | `ca-oom-leak` → Containers → Properties tab | `memory: 0.5Gi`, `cpu: 0.25`; differentiating env vars `MODE=leak` and `LEAK_MB_PER_TICK=30` are set by `trigger-scenario-b.sh` and visible in the **Environment variables** tab of the same blade (not captured here) | `18-ca-oom-leak-containers.png` |
| 19 | Same | `ca-oom-leak` → Scale | Same min/max as the other scenarios | `19-ca-oom-leak-scale.png` |

**Log streams during progressive leak** (captures 20-21):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 20 | After the leak crosses the ceiling | `ca-oom-leak` → Log stream (Category: System) | Eventual `ContainerTerminated` after the leak crosses the ceiling | `20-ca-oom-leak-logstream-system.png` |
| 21 | During the leak | `ca-oom-leak` → Log stream (Category: Application) | Progressive `[leak] tick N: +30 MiB, total retained K MiB` entries — the signature pattern that distinguishes a gradual leak from a hard OOM | `21-ca-oom-leak-logstream-application.png` |

**Metrics showing the staircase pattern** (captures 22-25):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 22 | During multi-cycle leak window | Metrics | `Memory Percentage` — linear climb, drop to baseline on OOMKill, climb again — the staircase | `22-ca-oom-leak-metric-memory-percentage.png` |
| 23 | Same | Metrics | `Memory Working Set Bytes` — same staircase in absolute bytes | `23-ca-oom-leak-metric-memory-working-set-bytes.png` |
| 24 | Same | Metrics | `RestartCount` — tracks kill-and-restart cycles | `24-ca-oom-leak-metric-restart-count.png` |
| 25 | Same | Metrics | `Replica Count` — tracks kill-and-restart cycles | `25-ca-oom-leak-metric-replica-count.png` |

#### Scenario C — `ca-oom-healthy` (Healthy control, captures 26-28)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 26 | Steady state | `ca-oom-healthy` → Overview | `Healthy` | `26-ca-oom-healthy-overview.png` |
| 27 | Same | Metrics | `Memory Percentage` — flat at a very low level | `27-ca-oom-healthy-metric-memory-percentage.png` |
| 28 | Same | Revisions and replicas | Single active revision with `HealthState: Healthy` and no restart history — the differential control proving the platform, image, environment, and network path are all fine | `28-ca-oom-healthy-revisions.png` |

#### Environment and Log Analytics workspace (captures 29-30)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 29 | Anytime | Container Apps environment → Overview | Single environment shared by all three scenarios; forwards system + application logs to one Log Analytics workspace — what makes the cross-scenario KQL queries possible | `29-environment-overview.png` |
| 30 | Anytime | Log Analytics workspace → Overview | Workspace receiving logs from all three scenarios | `30-loganalytics-workspace-overview.png` |

#### KQL verification queries — Logs blade (captures 31, 32a, 32, 33, 34-growth, 34-azuremetrics, 35, 36)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 31 | Post-incident | Log Analytics → Logs | Cross-scenario `summarize` — single best one-shot view of "which scenarios are OOMing" (concentrated on `ca-oom-hard`, smaller quantity on `ca-oom-leak`, absent on `ca-oom-healthy`) | `31-kql-cross-scenario-exit-events.png` |
| 32a | Same | Logs | Schema-discovery query listing columns on `ContainerAppConsoleLogs_CL` | `32a-kql-schema-discovery.png` |
| 32 | Same | Logs | Leak-tick query rendering progressive `[leak] tick` entries on `ca-oom-leak` | `32-kql-ca-oom-leak-app-log-ticks.png` |
| 33 | Same | Logs | `ContainerTerminated` detail query on `ca-oom-hard` — projects exact log text + revision name, giving full audit trail of every SIGKILL the failing revision received | `33-kql-ca-oom-hard-container-terminated.png` |
| 34-growth | Same | Logs | `render timechart` of `total retained MiB` extracted from leak tick logs — the staircase visualization (each step = 30 MiB allocation; each drop = OOMKill + restart) | `34-kql-memory-growth-timechart.png` |
| 34-azuremetrics | Same | Logs | `AzureMetrics` table query for `MemoryPercentage` returning **zero rows** for Azure Container Apps — the wrong-path teaching capture | `34-kql-memory-percentage-azuremetrics.png` |
| 35 | Same | Logs | `ca-oom-leak` `ProbeFailed` entries — downstream symptom (readiness probe fails once leak exhausts memory budget) | `35-kql-ca-oom-leak-probefailed.png` |
| 36 | Same | Logs | `ca-oom-hard` `ScaledObjectCheckFailed` entries — downstream symptom (KEDA scaler-check fails because it cannot read metrics from a Not-Ready container) | `36-kql-ca-oom-hard-scaledobjectcheckfailed.png` |

!!! note "Capture 34-azuremetrics is the wrong-path teaching capture"
    The lab body explicitly documents this capture as the empty-result evidence that Azure Container Apps platform metrics (`MemoryPercentage`, `WorkingSetBytes`, `CpuPercentage`, `RestartCount`, `Replicas`) are **not** routed into the `AzureMetrics` Log Analytics table. The correct paths are the Azure Monitor Metrics service directly (the **Metrics** blade in the Portal, or `az monitor metrics list --resource ... --metric ...` from the CLI). Re-capture must preserve the `AzureMetrics | where Resource == "CA-OOM-LEAK" | where MetricName == "MemoryPercentage"` query text and the zero-row result so future operators see the wrong path documented next to the right paths.

#### Post-fix verification (captures 37-43)

**Overview, revisions, and containers after the fix** (captures 37, 38, 38b, 43):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 37 | After `trigger-fix.sh` updates Scenario A to `MODE=healthy` with `memory=1.0Gi` | `ca-oom-hard` → Overview | `Running`; new healthy revision `ca-oom-hard--0000001` is the active revision | `37-ca-oom-hard-overview-postfix.png` |
| 38 | Same | `ca-oom-hard` → Revisions and replicas | New healthy revision `ca-oom-hard--0000001` alongside the failing one (now inactive but preserved for evidence) | `38-ca-oom-hard-revisions-postfix.png` |
| 38b | Same | Revisions and replicas | Inactive failing revision `ca-oom-hard--18xosgl` retained for evidence | `38b-ca-oom-hard-revisions-inactive.png` |
| 43 | Same | `ca-oom-hard` → Containers → Properties tab | Confirms new memory allocation `memory: 1.0Gi` | `43-ca-oom-hard-containers-postfix.png` |

**Metrics after the fix** (captures 39, 39b, 39c):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 39 | After fix | Metrics | Initial Metrics blade view after the fix | `39-ca-oom-hard-metrics-blade-initial.png` |
| 39b | Same | Metrics | `Memory Working Set Bytes` stable at ~15 MiB (Python runtime), well below the new 1Gi ceiling | `39b-ca-oom-hard-metrics-memoryworkingset.png` |
| 39c | Same | Metrics | Metric picker dropdown confirming all Container Apps metric dimensions are available per revision and per replica | `39c-ca-oom-hard-metrics-dropdown.png` |

**Activity Log of the fix operations** (captures 40, 41, 42):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 40 | After fix | `ca-oom-hard` → Activity Log | Listing the create + fix operations | `40-ca-oom-hard-activity-log.png` |
| 41 | Same | Activity Log | Entry expanded showing operation status, timestamps | `41-ca-oom-hard-activity-log-create-expanded.png` |
| 42 | Same | Activity Log | Operation detail | `42-ca-oom-hard-activity-log-operation-detail.png` |

#### Diagnose and Solve Problems — Portal-native OOM diagnosis (captures 44-47)

**Landing + Availability and Performance** (captures 44, 44b):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 44 | After fix | `ca-oom-hard` → Diagnose and Solve Problems | Landing page exposing 7 troubleshooting categories | `44-ca-oom-hard-diagnose-solve.png` |
| 44b | Same | Diagnose and Solve → Availability and Performance | Category aggregating 13 detectors; Revisions Health chart shows new revision `ca-oom-hard--0000001` green alongside inactive failing revision `ca-oom-hard--18xosgl` red — side-by-side fix-validation view | `44b-ca-oom-hard-diagnose-availability-performance.png` |

**Container App Memory Usage detector (post-fix)** (captures 44c, 44d):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 44c | After fix | Diagnose and Solve → Container App Memory Usage | Green check reading "No revisions detected with Memory usage exceeding warning or critical thresholds" — independently confirms the fix | `44c-ca-oom-hard-diagnose-memory-detector.png` |
| 44d | Same | Container App Memory Usage detector | Per-replica chart showing `Memory: 1Gi` config and 80% warning threshold, with the new replica running well under | `44d-ca-oom-hard-diagnose-memory-perrevision.png` |

**Container Exit Events detector — killer evidence** (captures 45, 45b, 45c, 45d):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 45 | After fix | Diagnose and Solve → Container Exit Events | Header counter reads `28 exit event(s)`; Portal's own diagnosis text: *"Resource exhaustion - containers terminated with SIGKILL (exit code 137) ... This is commonly caused by Out of Memory (OOM) conditions."* | `45-ca-oom-hard-diagnose-exit-events.png` |
| 45b | Same | Container Exit Events detector | Common root causes (port mismatch, missing env vars/secrets, probe misconfig, application errors) + cross-references to `ContainerAppConsoleLogs_CL`/`ContainerAppSystemLogs_CL` + Health Probe Failures detector | `45b-ca-oom-hard-diagnose-exit-codes-table.png` |
| 45c | Same | Container Exit Events detector | Bar chart of exit events across 24-hour window (two series: `exit code '137' and reason 'ProcessExited'` + `exit code '137'`); per-revision table totals **76 exit events** for `ca-oom-hard--18xosgl` (52 ProcessExited + 24 exit-137-only) — confirms SIGKILL count | `45c-ca-oom-hard-diagnose-exit-events-graph.png` |
| 45d | Same | Container Exit Events detector | `Successful Checks (3)` section listing the other detectors that passed: Health Probe Failures, Image Pull Failures, Ingress Port — the Portal's **differential diagnosis** ruling out probes, image pull, and port configuration | `45d-ca-oom-hard-diagnose-exit-events-checks.png` |

**Differential ruling-out** (captures 46, 47):

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 46 | After fix | Diagnose and Solve → Container Create Failures | "No container creation failures have been detected" — proves failing revision was **created successfully** then killed at runtime, not blocked at containerd | `46-ca-oom-hard-diagnose-container-create-failures.png` |
| 47 | Same | Diagnose and Solve → Health Probe Failures | "No Health Probe failures were detected" between the failure window timestamps — confirms OOM was not caused by a misconfigured probe (kernel SIGKILL fired before any probe could fail) | `47-ca-oom-hard-diagnose-health-probe-failures.png` |

!!! warning "Capture 45 carries the Portal's own OOM diagnosis text — re-shoot it verbatim"
    Capture 45 is the single most valuable Portal capture in the lab because it contains the Portal's **own** SIGKILL→OOM attribution text rendered by the Container Exit Events detector: *"Resource exhaustion - containers terminated with SIGKILL (exit code 137) ... This is commonly caused by Out of Memory (OOM) conditions."* The companion lab playbook quotes this string as the binding evidence that the operator does not need to interpret raw `exit code 137` themselves. Re-captures must preserve this verbatim text and the `28 exit event(s)` header counter; if either changes (e.g., new Portal copy), update the playbook quote in the same PR. Captures 45c (per-revision drill-down totalling 76 events) and 45d (Successful Checks differential) together complete the killer-evidence triple.

### memory-percentage-vs-keda-utilization

The 3 captures committed under `docs/assets/troubleshooting/memory-percentage-vs-keda-utilization/`. The lab runs three Container Apps with identical KEDA `Utilization=50` memory-percentage scale rules but different workload shapes: A holds per-replica memory below the threshold, B holds it above the threshold, and C drives the **Portal** `MemoryPercentage` well above the threshold using reclaimable page cache — the divergence proof that KEDA does not read the Portal value.

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Scenario A `ca-mempct-a-below`, 30-minute steady state | `ca-mempct-a-below` → Monitoring → Metrics | `Avg Memory Percentage (Preview)` split by `Replica` + `Max Replica Count`, time range Last 30 minutes; both replicas (`mdkj6`, `z77lh`) report `MemoryPercentage` flat at 40%; `Replica Count (Max) = 2`; `ceil(2 * 40 / 50) = 2` matches observed replicas | `scenario-a-below.png` |
| 2 | Scenario B `ca-mempct-b-above`, after sustained scale-out | `ca-mempct-b-above` → Monitoring → Metrics | Same split + range; all visible per-replica series report `MemoryPercentage` flat at 56%; `Replica Count (Max) = 20` (the configured `maxReplicas`); per-replica utilization stays above 50% because each new replica also runs the same 600 MiB allocation, so HPA keeps recomputing `ceil(N * 56 / 50)` and scales out continuously until the cap | `scenario-b-above.png` |
| 3 | Scenario C `ca-mempct-cache`, with page-cache-dominated memory | `ca-mempct-cache` → Monitoring → Metrics | Same split + range; three active replicas report `MemoryPercentage` at 71.9-72% (well above the 50% threshold); `Replica Count (Max) = 3`, far below what `ceil(N * 72 / 50)` would predict | `scenario-c-cache.png` |

!!! note "Capture 3 is the divergence proof — KEDA does not read the Portal MemoryPercentage"
    Capture 3 (`scenario-c-cache.png`) is the lab's binding evidence that the Portal `Avg Memory Percentage (Preview)` metric and the KEDA scaler input are **not the same value**. The Portal value reflects the cgroup working set including reclaimable page cache, while KEDA evaluates a Kubernetes Metrics Server value against the container's requested memory. In Scenario C the cache-heavy workload pushes the Portal metric to ~72% while the KEDA scaler input remained below the 50% threshold, so KEDA did not scale further. Without capture 3, the divergence claim is theoretical; with capture 3, an operator can directly see that a 72% Portal reading produced only 3 replicas (not the ~5 the formula predicts), and infer that the scaler is reading a different value. Re-capture must preserve the per-replica `MemoryPercentage` series at 71.9-72% and `Replica Count (Max) = 3` in the same 30-minute window.

### observability-tracing

The 6 captures from the 2026-06-03 reproduction, committed under `docs/assets/troubleshooting/observability-tracing/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | Steady state | Container App → Overview | Essentials panel with `Status: Running`, `Location: Korea Central`, `Environment type: Workload profiles`, and the `Application Url` link | `01-overview.png` |
| 2 | Before the trigger | Container App → Containers → Environment variables (Based on revision `ca-labobs-622oal--0m6ek7p`) | Shows `APPLICATIONINSIGHTS_CONNECTION_STRING` Source = "Reference a secret", Value = `appinsights-connection-stri...` | `02-env-vars-baseline-secretref.png` |
| 3 | During the incident | Container App → Containers → Environment variables (Based on revision `ca-labobs-622oal--0000001`) | Same env var, Source = "Manual entry", Value textarea showing the literal `InstrumentationKey=00000000-...;IngestionEndpoint` (suffix clipped by the textarea) | `03-env-vars-after-trigger-literal.png` |
| 4 | During the incident | Application Insights `appi-labobs-622oal` → Transaction search | Filter chips `Local Time: Last 24 hours (Automatic)`, `View as: Traces`, `Event types = All selected`; "See all data in the last 24 hours" prompt (no executed result table) | `04-appinsights-transaction-search.png` |
| 5 | During the incident | Application Insights `appi-labobs-622oal` → Logs | KQL `traces \| count`; Time range `Last hour`; Results column header `Count` with single row `0` | `05-appinsights-logs-traces-count-zero.png` |
| 6 | After the fix | Container App → Containers → Environment variables (Based on revision `ca-labobs-622oal--0000002`) | Same env var, Source = "Reference a secret", Value = `appinsights-connection-stri...` | `06-env-vars-restored-secretref.png` |

### probe-and-port-mismatch

The 11 captures committed under `docs/assets/troubleshooting/probe-and-port-mismatch/`. The lab is structured as two paired reproductions on the **same** Container App and (critically for falsification) the **same revision**: PR-A documents the failure state (`ca-labprobe-shes3s--0000001` with `targetPort: 8000` while the workload listens on `:3000`), and PR-B documents the after-fix state on the same revision after a single ingress-only edit (`targetPort: 3000`).

!!! warning "The baseline revision `--coxh910` is NOT a healthy control"
    The Bicep template (`labs/probe-and-port-mismatch/infra/main.bicep`) deploys a baseline that is **already mismatched on first deploy**: the placeholder image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` (which listens on port 80) is combined with ingress `targetPort: 8000`. The baseline revision `ca-labprobe-shes3s--coxh910` is therefore also emitting `ProbeFailed` events during the capture window (visible in capture 06). PR-A captures both `--0000001` and `--coxh910` in the Active revisions list only to document the full active-revisions list visible in the Portal at capture time; the controlled comparison to a healthy state is provided by PR-B, which holds the image (and therefore the listening port) constant on `--0000001` and changes only `targetPort` from 8000 → 3000.

#### Failure state — trigger revision `--0000001` (captures 01-06, 2026-06-02)

**Trigger applied:** ACR build of the workload in `labs/probe-and-port-mismatch/workload/` (Flask + Gunicorn, `CMD ["gunicorn", "--bind", "0.0.0.0:3000", ...]`) → `az containerapp registry set` → `az containerapp update --image .../ca-labprobe-shes3s:v1` → `az containerapp ingress update --target-port 8000`. The shipped `labs/probe-and-port-mismatch/trigger.sh` does this in a single `az containerapp update` call; the capture-day sequence was split into the three commands above as a workaround for unrecognized-argument errors on the locally installed `containerapp` CLI extension.

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After trigger applied | `ca-labprobe-shes3s` → Overview | Platform `Status: Running` but **Revisions with Issues** section displays the verbatim Portal message `The TargetPort 8000 does not match the listening port 3000. 1/1 Container crashing: app` — the platform-emitted attribution naming both the configured `targetPort` (8000) and the workload's actual listening port (3000) | `01-overview-failed.png` |
| 2 | Same | Revisions and replicas | **Active revisions** tab showing `--0000001` with `Running status: Failed`, `Traffic: 100%` and baseline `--coxh910` with `Running status: Degraded`, `Traffic: 0%` (the baseline was observed flapping between Activating/Degraded during the capture window) | `02-revisions-failed.png` |
| 3 | Same | Containers | Active container `app` configured with the custom-built image `acrlabprobeshes3s.azurecr.io/ca-labprobe-shes3s:v1` — confirms the image swap | `03-containers-failed.png` |
| 4 | Same | Ingress | `Target port: 8000`, external HTTP ingress enabled — the value the trigger wrote and the value the Overview blade's error message refers to | `04-ingress-failed.png` |
| 5 | Same | Log stream (Category: Application, Based on revision: `--0000001`) | Gunicorn startup output `Listening at: http://0.0.0.0:3000` — the workload's actual listening port, captured from inside the container's own startup logs | `05-logstream-failed.png` |
| 6 | Same | Log stream (Category: System) | Continuous `ProbeFailed` events for **both** revisions: `--0000001` `"Probe of StartUp failed with status code: 1"` with `Count: 955` and `--coxh910` with `Count: 1041` (counts incrementing in real time) | `06-system-logs-failed.png` |

#### After-fix state — same revision `--0000001` (captures 07-11, 2026-06-03)

**Fix applied:** A single ingress-only edit on the same app, with no image change, no revision-template change, and no scaling change: `az containerapp ingress update --resource-group $RG --name $APP_NAME --target-port 3000`. The dependent variable (revision health) flips from `Failed` to `Running` while every other input is held constant, which falsifies the alternative theories enumerated under PR-A (broken image, ACR pull failure, probe-config bug, revision-template defect).

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 7 | After fix | `ca-labprobe-shes3s` → Overview | `Status: Running`; the `Revisions with Issues` banner present in capture 01 is gone | `07-overview-recovered.png` |
| 8 | Same | Revisions and replicas | **Same** revision name `ca-labprobe-shes3s--0000001` as the failure state (capture 02), now with `Running status: Running`, `Traffic: 100%`; baseline `--coxh910` no longer present in Active revisions; `Created: 6/3/2026 8:17:46 AM` field identical to the same revision's `Created` value in capture 02 | `08-revisions-recovered.png` |
| 9 | Same | Ingress | `Target port: 3000`, matching the workload's actual listening port (compare to capture 04 which showed 8000) | `09-ingress-recovered.png` |
| 10 | Same | Log stream (Category: Application, Based on revision: `--0000001`) | The same gunicorn startup output and listening port 3000 from the same revision as the failure state — the "dog that did not bark" evidence that the workload did not change | `10-logstream-recovered.png` |
| 11 | Same | Log stream (Category: System) | `RevisionUpdate`, `RevisionDeactivating`, and the platform controller event `"No revision restart or provisioning was needed."` — no `ProbeFailed` entries | `11-system-logs-recovered.png` |

!!! note "Same-revision recovery is triangulated from 3 independent platform signals"
    Capture 8 + capture 11 together establish that the ingress edit did **not** mint a new revision. The same-revision-recovery claim is triangulated from three independent signals that operators can read directly off the Portal blades without trusting any single one:
    1. **Revision name** — `ca-labprobe-shes3s--0000001` is identical in capture 02 (failure state) and capture 08 (after-fix state).
    2. **`Created` timestamp** — the Portal-rendered `revision.properties.createdTime` value reads `6/3/2026 8:17:46 AM` in capture 08, identical to the value the Portal renders for the same revision in capture 02. The platform is reporting the same creation time before and after the `targetPort` change.
    3. **Platform-emitted controller event** — capture 11 shows the System-category Log stream emitting `"No revision restart or provisioning was needed."` during the ingress edit window, confirming the platform itself did not deactivate or recreate the revision in response to the edit.

    Re-captures of 08 and 11 must preserve all three signals; if any one of them differs from capture 02 (e.g., a new revision name, a new `Created` timestamp, or a `RevisionProvisioned` event in System logs), the same-revision-recovery claim is broken and the fix must be re-attempted.

### replica-node-spread

The 5 captures committed under `docs/assets/troubleshooting/replica-node-spread/`:

| # | When | Portal blade | What it proves | Filename |
|---|---|---|---|---|
| C1 | After deploy | Resource group → Overview | Two apps + env + ACR + LAW + UAMI all present in the same RG; eliminates the "deployment is split across RGs" confounder | `01-rg-overview.png` |
| C2 | After deploy | Container Apps env → Workload profiles | Both Consumption and Dedicated D8 profiles listed on the same env; confirms the experimental setup | `02-env-workload-profiles.png` |
| C3 | After scaling app-consumption to 30 | app-consumption → Revisions and replicas (Active revisions tab) | Active revision row shows the running replica count = 30 at top scale; revision name and provisioning state visible | `03-app-consumption-30-replicas.png` |
| C4 | After scaling app-dedicated-d8 to 10 | app-dedicated-d8 → Revisions and replicas (Active revisions tab) | Active revision row shows the running replica count = 10 at top scale under the Dedicated D8 profile | `04-app-dedicated-d8-10-replicas.png` |
| C5 | After deploy | app-consumption → Overview (Essentials section) | Confirms `Environment type: Workload profiles` for `app-consumption`'s parent environment, which is the prerequisite for the app-level `workloadProfileName: Consumption` binding set in `infra/main.bicep` | `05-app-consumption-workload-profile.png` |

### revision-failover

The 6 captures from the 2026-06-03 reproduction, committed under `docs/assets/troubleshooting/revision-failover/`:

| # | When | Portal blade | What it proves | Filename |
|---|---|---|---|---|
| 1 | After the bad rollout, before opening Revisions | Container App → Overview | The `Revisions with issues` banner surfaces the failure at the top-level blade | `01-overview-revisions-with-issues.png` |
| 2 | After the bad rollout creates a new revision | Container App → Revisions and replicas (Active revisions tab) | All active revisions listed with traffic %, running status, and replica counts — the broken revision is the one holding 100 % traffic | `02-revisions-and-replicas-blade.png` |
| 3 | Click the broken revision name → Basics tab of the flyout | Revision details flyout (Basics) | `Status details` shows the exact `TargetPort N does not match the listening port M` message that pinpoints the misconfiguration | `03-revision-detail-broken-v2-flyout.png` |
| 4 | In the same flyout, click the **Logs** tab | Revision details flyout (Logs) | Real-time stderr proves the container itself bound to its listening port — falsifying any "the app crashed" hypothesis | `04-show-logs-broken-v2.png` |
| 5 | After `az containerapp ingress update --target-port <correct>`, refresh Revisions | Container App → Revisions and replicas | The previously broken revision turns `Running` (green) without any image change — proving the failure was purely the ingress port mismatch | `05-revisions-after-rollback-healthy.png` |
| 6 | After full experiment | Container App → Activity log | Lab activity entries (mix of `Create or Update Container App`, `Auth Token for Container App Dev APIs`, `List Container App Secrets`) all show `Accepted` / `Succeeded` — supporting the inference that the control plane never rejected the misconfiguration and the failure surfaced only at runtime probe time | `06-activity-log-update-events.png` |

### revision-provisioning-failure

Two reproductions of this lab have produced complementary capture sets. Reuse the same filenames when re-reproducing on a fresh environment.

#### 2026-06-03 reproduction (port variant — 6 captures)

The first reproduction triggered the failure with a startup probe on a wrong **port**.

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After the bad startup probe revision is created | Container App → Overview | **Revisions with Issues** tab showing the new failed revision | `01-overview-revisions-with-issues.png` |
| 2 | During diagnosis | Container App → Revisions and replicas | Active revisions grid showing failed vs healthy revisions side by side | `02-revisions-list-failed-vs-healthy.png` |
| 3 | During diagnosis | Container App → Revisions → failed revision | Revision detail flyout showing `Failed` / `Unhealthy` / `0/1 replicas` | `03-revision-detail-failed.png` |
| 4 | During diagnosis | Revision detail → Logs tab | System + Historical logs showing `ProbeFailed → ContainerTerminated(ProbeFailure)` cascade | `04-revision-detail-logs-tab.png` |
| 5 | During diagnosis | Container App → Activity log | `Create or Update Container App` events from the revision update | `05-activity-log.png` |
| 6 | During diagnosis | Container App → Diagnose and solve problems | Container Apps Diagnostics landing — Availability and Performance / Deployment categories | `06-diagnose-and-solve-problems.png` |

#### 2026-06-20 reproduction (path variant — 34 captures)

The second reproduction triggered the failure with a startup probe on a wrong **path** (image swapped to `nginx:alpine`, which correctly returns 404 for unknown paths).

**Baseline (healthy) — captures 07-11**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 7 | Before trigger | Resource Group → Overview | Resource list (Container App, environment, Log Analytics, ACR) | `07-resource-group-overview.png` |
| 8 | Before trigger | Container App → Overview | Status `Running`, **Revisions with issues** tab empty | `08-ca-overview-baseline.png` |
| 9 | Before trigger | Container App → Revisions and replicas | Single Healthy revision row | `09-revisions-baseline-healthy.png` |
| 10 | Before trigger | Container App → Containers | Image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`, no probes | `10-containers-baseline-noprobe.png` |
| 11 | Before trigger | Containers → Health probes | Empty health-probes pane (baseline has none) | `11-containers-baseline-healthprobes-empty.png` |

**Failure state — captures 12-18**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 12 | After trigger | Container App → Overview | Status banner with revisions-with-issues tab populated | `12-overview-failure-state.png` |
| 13 | After trigger | Container App → Revisions and replicas | Failed revision `badpath2` listed | `13-revisions-failed-state.png` |
| 14 | After trigger | Revisions → `badpath2` detail | Revision detail flyout `Provisioning Failed`, `0/1 replicas` | `14-revision-detail-badpath2-failed.png` |
| 15 | After trigger | Revision detail → Logs tab | Real-time + Application selected; shows `No replica running — Try selecting Historical display option` (diagnostic of the restart loop) | `15-revision-detail-logs-tab.png` |
| 16 | After trigger | Revision detail → Logs → Historical system logs | `ProbeFailed → ContainerTerminated(ProbeFailure)` cascade (GOLD) | `16-revision-historical-system-logs.png` |
| 17 | After trigger | Container App → Containers | Image swapped to `nginx:alpine` | `17-containers-failure-nginx-image.png` |
| 18 | After trigger | Containers → Health probes | Liveness + Readiness fully visible; Startup probes section enabled (config fields below the fold) | `18-containers-health-probes-bad-path.png` |

**Log evidence (Portal Log Stream) — captures 19-20**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 19 | After trigger | Container App → Log stream → Application | Nginx graceful-shutdown sequence (SIGQUIT + per-worker exits) on the failing replica; raw 404 entries captured to `evidence/10-kql-console-logs.json` | `19-log-stream-failure.png` |
| 20 | After trigger | Container App → Log stream → System | Live system log stream showing real-time probe failure events (GOLD) | `20-log-stream-system-realtime.png` |

**Activity Log — capture 21**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 21 | After trigger | Container App → Activity log | `Create or Update Container App` deployment event from trigger | `21-activity-log-deployment-event.png` |

**Diagnose and solve problems — captures 22-27**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 22 | After trigger | Container App → Diagnose and solve problems | Diagnostics landing — Availability and Performance / Deployment categories | `22-diagnose-solve-problems-overview.png` |
| 23 | After trigger | Diagnose → Availability and Performance | Detector list for the Availability and Performance category | `23-availability-performance-detectors.png` |
| 24 | After trigger | Detector: **Container Exit Events** | Default view — recent container exits with exit codes | `24-detector-container-exit-events.png` |
| 25 | After trigger | Detector: **Container Create Failures** | Container-create failure summary | `25-detector-container-create-failures.png` |
| 26 | After trigger | Detector: **Health Probe Failures** | Probe failure summary | `26-detector-health-probe-failures.png` |
| 27 | After trigger | Detector: **Image Pull Failures** | Image-pull failure summary | `27-detector-image-pull-failures.png` |

**Metrics — captures 28-29**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 28 | After trigger | Container App → Metrics | Metrics blade landing | `28-metrics-blade-overview.png` |
| 29 | After trigger | Metrics → Replica Count | Replica-count time series during failure window | `29-metrics-replica-count.png` |

**KQL evidence (Log Analytics) — captures 30-33**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 30 | After trigger | Log Analytics → Logs | `ContainerAppSystemLogs_CL` filtered to `Reason == "ProbeFailed"` (GOLD) | `30-kql-probefailed-query.png` |
| 31 | After trigger | Log Analytics → Logs | Probe-failure to container-termination correlation join | `31-kql-event-correlation.png` |
| 32 | After trigger | Log Analytics → Logs | KQL editor pitfall: two stacked queries with no blank-line separator → syntax error. Actual nginx 404 + SIGCHLD evidence captured to `labs/revision-provisioning-failure/evidence/10-kql-console-logs.json` (GOLD raw artifact) | `32-kql-console-logs.png` |
| 33 | After trigger | Log Analytics → Logs | Summary aggregated by `Reason` | `33-kql-summary-by-reason.png` |

**Falsification (KQL) — captures 34-35**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 34 | After fix | Log Analytics → Logs | KQL proving the healthy revision produces zero probe failures | `34-kql-falsification-healthy.png` |
| 35 | After fix | Log Analytics → Logs | Time-chart of failures over the failure → recovery window | `35-kql-timechart-failures.png` |

**Recovery (post-fix evidence) — captures 36-40**

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 36 | After fix | Container App → Overview | Status `Running`, 100% traffic on the recovered revision | `36-overview-recovered-healthy.png` |
| 37 | After fix | Container App → Revisions and replicas | New healthy revision `badpath3` with 100% traffic | `37-revisions-recovered-badpath3-healthy.png` |
| 38 | After fix | Container App → Log stream → Application | Application category, revision `badpath3`: clean nginx startup + `GET / HTTP/1.1 200 896` probe success (GOLD) | `38-log-stream-recovered-clean.png` |
| 39 | After fix | Log Analytics → Logs | Post-fix KQL grouped by revision showing zero failures on the recovered revision (GOLD) | `39-kql-postfix-verification-by-revision.png` |
| 40 | After fix | Detector: **Container Exit Events** → Container Exits drilldown | Per-revision exit-code breakdown showing the failed revision is no longer producing exits | `40-detector-container-exit-events-postfix.png` |

### scale-rule-mismatch

The 6 captures committed under `docs/assets/troubleshooting/scale-rule-mismatch/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After baseline deploy, before load | Container App → Monitoring → Metrics | Metric `Replica count`, Aggregation `Max`, Time `Last 5 minutes` | `scale-rule-mismatch-baseline.png` |
| 2 | During sustained load with `concurrentRequests=500` | Container App → Monitoring → Metrics | Two charts pinned side-by-side: `Replica count` (Max) and `Requests` (Sum, split by Status code category), Time `Last 15 minutes` | `scale-rule-mismatch-load-stuck.png` |
| 3 | During sustained load with `concurrentRequests=500` | Container App → Monitoring → Log stream (or Logs → KQL `ContainerAppSystemLogs_CL \| where Reason_s contains "KEDA"`) | Visible `KEDAScalersStarted` event | `scale-rule-mismatch-keda-logs.png` |
| 4 | Before fix | Container App → Application → Scale and replicas | Full scale settings panel showing `Min=1`, `Max=2`, HTTP rule `concurrentRequests=500` | `scale-rule-mismatch-config-before.png` |
| 5 | After fix (`concurrentRequests=10`, `maxReplicas=10`) | Container App → Monitoring → Metrics | `Replica count` (Max), Time `Last 15 minutes` showing scale-out above 1 | `scale-rule-mismatch-after-fix.png` |
| 6 | After fix | Container App → Application → Scale and replicas | Full scale settings panel showing `Min=1`, `Max=10`, HTTP rule `concurrentRequests=10` | `scale-rule-mismatch-config-after.png` |

### startup-degraded-transient-failure

The 42 captures committed under `docs/assets/troubleshooting/startup-degraded-transient-failure/`. The lab is a falsification experiment: a zone-redundant 3-replica subject app (`subject-app`, `STARTUP_DELAY_SECONDS=25`, dedicated `/healthz` probe) is subjected to 3 perturbation events that promote revisions `0000001` → `0000002` → `0000003`, with a k6 loadgen job, a perturbation-sampler, and an audit-sampler running in parallel. The binding falsification verdict comes from k6 bucket aggregation: zero client-visible 5xx across all 126 buckets spanning baseline + 3 perturbation events. The captures are organized into 6 cluster groups that mirror the lab body's `### Observed Evidence (Portal Captures — 2026-06-20)` H4 sections.

!!! note "Captures 25 and 29 are committed but not embedded in the lab body"
    `25-subject-app-revisions-event2-replicas-expanded.png` and `29-subject-app-revisions-event3-replicas-expanded.png` exist on disk but are not referenced from `docs/troubleshooting/lab-guides/startup-degraded-transient-failure.md`. They are documented here as raw evidence captures for event 2 and event 3 replicas-expanded views respectively, so future cleanup can either embed them into the lab body or delete them from disk. Both are listed below with `(25)` / `(29)` row markers and `(not embedded)` annotations.

!!! note "Resource Group + Container Apps Environment Overview are CLI-only by design"
    The baseline cluster header in the lab body reads "captures 01-18" but only captures 03-18 exist on disk. Positions 01 (Resource Group `rg-aca-startup-degraded` Overview) and 02 (Container Apps Environment `cae-sdlab-j2fs74` Overview) are intentionally not captured: per the lab body, *"the original captures of those two blades did not render correctly"*, so they are documented as structured prose + `az` CLI commands instead of Portal screenshots. The `az resource list --resource-group rg-aca-startup-degraded` and `az containerapp env show --name cae-sdlab-j2fs74` commands in the lab body serve as the equivalent evidence.

#### Baseline (captures 03-18, 16 PNGs)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 3 | Pre-perturbation, after `./trigger.sh` provisions infrastructure | `subject-app` → Overview | Active revision `subject-app--bhly9qa`, healthy state | `03-subject-app-overview.png` |
| 4 | Same | `subject-app` → Revisions and replicas | Baseline revision `subject-app--bhly9qa` running min=max=3 | `04-subject-app-revisions.png` |
| 5 | Same | Revisions and replicas → expanded replicas | All 3 baseline replicas listed | `05-subject-app-replicas-expanded.png` |
| 6 | Same | `subject-app` → Ingress | Baseline ingress configuration | `06-subject-app-ingress.png` |
| 7 | Same | `subject-app` → Scale | min=max=3, KEDA scale rule visible | `07-subject-app-scale.png` |
| 8 | Same | `subject-app` → Containers | Baseline container image + properties | `08-subject-app-containers.png` |
| 9 | Same | Containers → Health probes | `/healthz` probe path (dedicated, not the workload `/` path — the most common probe misconfiguration) | `09-subject-app-health-probes.png` |
| 10 | Same | `subject-app` → Log stream | Baseline application log stream | `10-subject-app-log-stream.png` |
| 11 | Same | `subject-app` → Monitoring → Metrics | Default panel — baseline | `11-subject-app-metrics-default.png` |
| 12 | Same | Metrics | Response time chart — baseline | `12-subject-app-metrics-response-time.png` |
| 13 | Same | Container Apps Environment → Workload profiles | Consumption profile, zone-redundant configuration | `13-env-workload-profiles.png` |
| 14 | Same | `audit-sampler` Job → Overview | Baseline job configuration (see Known issue: capture 42 Failed status is benign) | `14-job-audit-sampler-overview.png` |
| 15 | Same | `perturbation-sampler` Job → Overview | Baseline job configuration | `15-job-perturbation-sampler-overview.png` |
| 16 | Same | `loadgen-k6` Job → Overview | Baseline job configuration | `16-job-loadgen-k6-overview.png` |
| 17 | After baseline run | `loadgen-k6` → Execution history | `baseline-20260620213447` run completing successfully (zero 5xx) | `17-job-loadgen-k6-execution-history-baseline.png` |
| 18 | Same | Log Analytics workspace `log-sdlab-j2fs74` → Overview | Baseline workspace state | `18-law-overview.png` |

#### Perturbation events 1 & 2 in flight (captures 19-26, 8 PNGs on disk; 25 not embedded in body)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 19 | During event 1 (revision `--0000001` rolling out) | `subject-app` → Revisions and replicas | Rolling rollout in progress: old revision scaling down while new revision scales up | `19-subject-app-revisions-during-perturbation.png` |
| 20 | Same | `subject-app` → Log stream | No error-level entries from subject container during transition | `20-subject-app-log-stream-during-perturbation.png` |
| 21 | Same | `subject-app` → Monitoring → Metrics | Navigation context during event 1; the metric series in this capture is **not yet selected**, so the chart is intentionally empty — see captures 11 and 12 for the populated default and response-time charts | `21-subject-app-metrics-during-perturbation.png` |
| 22 | Same | `subject-app` → Activity log | `Microsoft.App/containerApps/write` operation that triggered the new revision via `ROLLOUT_GENERATION` env-var change | `22-subject-app-activity-log-during-perturbation.png` |
| 23 | During event 2 transition (revision `--0000002` rolling out) | Revisions and replicas | Event 2 transition view | `23-subject-app-revisions-event2-transition.png` |
| 24 | Same | Revisions and replicas (refreshed) | Event 2 refreshed view | `24-subject-app-revisions-event2-refreshed.png` |
| (25) | During event 2 | Revisions and replicas → expanded replicas | Event 2 replicas-expanded view (raw evidence) — **(not embedded in lab body; on disk only)** | `25-subject-app-revisions-event2-replicas-expanded.png` |
| 26 | During events 1 & 2 window | `subject-app` → Diagnose and Solve Problems | Landing page | `26-subject-app-diagnose-solve-home.png` |

#### Perturbation event 3 + post-experiment state (captures 27-32, 6 PNGs on disk; 29 not embedded in body)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 27 | Pre-event 3 | Revisions and replicas | Pre-event 3 state | `27-subject-app-revisions-pre-event3.png` |
| 28 | During event 3 (revision `--0000003` rolling out) | Revisions and replicas | Deprovisioning of prior revision visible | `28-subject-app-revisions-event3-deprovisioning.png` |
| (29) | During event 3 | Revisions and replicas → expanded replicas | Event 3 replicas-expanded view (raw evidence) — **(not embedded in lab body; on disk only)** | `29-subject-app-revisions-event3-replicas-expanded.png` |
| 30 | Post-event 3 | Diagnose and Solve → Availability and Performance | Category overview post-perturbation | `30-subject-app-ds-availability-performance.png` |
| 31 | Same | Log stream | Post-event 3 — no error-level entries from subject container | `31-subject-app-log-stream-post-event3.png` |
| 32 | Same | Event logs | Platform's `RollingRevisionCompleted` markers — no error events | `32-subject-app-event-logs-post-perturbation.png` |

#### LAW Logs evidence — the ZERO-ERRORS smoking gun (captures 33-39, 7 PNGs)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 33 | Post-experiment | LAW → Logs → Tables list | Left-rail tables list showing **only 3 base tables** exist (`ContainerAppConsoleLogs_CL`, `ContainerAppSystemLogs_CL`, platform `Usage`); no `LoadgenSample_CL`, `RevisionStateSample_CL`, `ReplicaInventorySample_CL`, or `PerturbationWindowMarker_CL` — the Custom Tables Gap | `33-law-logs-tables-list-custom-gap.png` |
| 34 | Same | LAW → Logs | System events summary across all 4 revisions | `34-law-logs-system-events-summary.png` |
| 35 | Same | LAW → Logs | `ProbeFailed` timechart — corroborative evidence of server-side probe failures without client-visible 5xx | `35-law-logs-probefailed-timechart.png` |
| 36 | Same | LAW → Logs | Revision lifecycle timeline across all 4 revisions | `36-law-logs-revision-lifecycle-timeline.png` |
| 37 | Same | LAW → Logs | k6 buckets aggregate — **126 buckets across `baseline-20260620213447` and `perturbation-20260620220432` runs, all with `err_total == 0`**, including the 3 perturbation events | `37-law-logs-k6-buckets-zero-errors.png` |
| 38 | Same | LAW → Logs | Sampler `RevisionStateSample` rows with `perturbation_id` attribution | `38-law-logs-sampler-revisionstate-perturbation-id.png` |
| 39 | Same | LAW → Logs | Audit-sampler `ReplicaInventorySample` summary — 583 records covering all 4 revisions × Running/NotRunning state | `39-law-logs-audit-replica-inventory.png` |

!!! warning "Capture 37 is the binding falsification visual"
    Capture 37 is the lab's gold visual. The lab body identifies it as: *"126 buckets across both baseline-20260620213447 and perturbation-20260620220432 runs, all with `err_total == 0`, including the 3 perturbation events. This is the Portal-level confirmation of the Section 8 Q5 falsification verdict."* Re-captures must preserve the bucket count (126), the run names (`baseline-20260620213447`, `perturbation-20260620220432`), and the `err_total == 0` column. If any of these values differ from re-capture, the falsification verdict is broken and the lab's H0 conclusion must be re-derived. Captures 33 and 35 are corroborative: capture 35 suggests probe failures occurred server-side without corresponding client-visible 5xx, but the binding verdict still comes from capture 37 (the k6 bucket aggregate), not from the probe-failure timechart.

#### Companion job lifecycles (captures 40-42, 3 PNGs)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 40 | Post-experiment | `perturbation-sampler` → Execution history | 3 runs (one per event), all `Succeeded` | `40-job-perturbation-sampler-execution-history.png` |
| 41 | Same | `loadgen-k6` → Execution history | 2 runs (baseline + continuous), both `Succeeded` | `41-job-loadgen-k6-execution-history.png` |
| 42 | Same | `audit-sampler` → Execution history | 15 prior executions marked `Failed` (one every 5 minutes from 21:30:25Z to 22:40:00Z), current 22:45:00Z execution `Running` | `42-job-audit-sampler-execution-history.png` |

!!! note "Capture 42 audit-sampler Failed executions are benign — do NOT interpret as a failure mode"
    The lab body explicitly documents this as a benign Portal-level artifact, not a data-ingestion failure. The audit-sampler job spec has `replicaTimeout=240` (4 minutes), but the audit container runs as a long-lived sampler daemon that emits a `ReplicaInventorySample` every 30 seconds. The platform sends SIGTERM at the 240-second mark, the container exits with a non-zero code, and ACA marks the execution as `Failed`. Data ingestion is **unaffected**: the audit container produced 583 records in `ContainerAppConsoleLogs_CL` during the repro window — covering all 4 revisions × Running/NotRunning state (visible in capture 39). The `qB-replica-inventory-*.json` raw export shows 342 unique sample rows with complete revision/replica/state attribution. **Operators MUST NOT alert on `audit-sampler` execution failure count.** Per the lab body Known Issues section, the documented options are: (1) accept Failed status (current design — data is complete, only the Portal badge is misleading); (2) trap SIGTERM and exit 0 (would also mask any real failures — not recommended); (3) change job semantics from cron-daemon to one-shot snapshot (would lose continuous sampling cadence — not recommended).

#### Final state (captures 43-44, 2 PNGs)

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 43 | Post-experiment | `subject-app` → Overview | Final active revision `subject-app--0000003` after all 3 rollouts completed | `43-subject-app-overview-final.png` |
| 44 | Same | Log Analytics workspace → Overview | Post-ingestion state with the lab's data plane volume | `44-law-overview-post-ingestion.png` |

### traffic-routing-canary

The 6 captures committed under `docs/assets/troubleshooting/traffic-routing-canary/`:

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After the bad revision is created and traffic split is applied | Container App → Overview | "Revisions with Issues" tab visible with the TargetPort/listening-port mismatch error | `01-overview-multi-revision-mode.png` |
| 2 | During the incident | Container App → Revisions and replicas | Active revisions tab showing both revisions at 50/50 with the bad one marked Failed | `02-revisions-50-50-split.png` |
| 3 | During the incident | Container App → Revisions and replicas → bad revision → View details | Revision status details flyout for the bad revision showing the TargetPort error | `03-bad-revision-status-details.png` |
| 4 | During the incident | Container App → Ingress | Ingress blade showing `Target port = 80` (unchanged) to prove the failure is per-revision, not ingress-level | `04-ingress-target-port-80.png` |
| 5 | During the incident | Container App → Revisions and replicas → good revision → View details | Revision status details flyout for the good revision showing `Running` with empty Status details (contrast against #3) | `05-good-revision-running-details.png` |
| 6 | After the incident | Container App → Activity log | The three `Create or Update Container App` operations corresponding to deployment + image-swap + traffic-set | `06-activity-log-update-operations.png` |

### zone-redundancy-best-effort

The captures committed under `docs/assets/troubleshooting/zone-redundancy-best-effort/`. The lab distinguishes **required** (validates H0a), **optional** (adds depth), and **conditional** (depends on optional setup) captures.

**Required captures (7) — validate H0a**

| # | When | Portal blade | What it proves | Filename |
|---|---|---|---|---|
| C1 | After deploy, before perturb | Container Apps env → Overview | Environment surfaces zone-redundant status alongside region | `01-env-overview-zone-redundant.png` |
| C2 | After deploy | Container Apps env → Workload profiles | Confirms the Consumption profile inside the workload-profile environment used by this lab; zone redundancy is configured at the environment level | `02-env-workload-profiles.png` |
| C3 | After deploy | app-min3 → Overview | Single app shows `Running` with `Min replicas = Max replicas = 3` visible in the Configuration tile | `03-app-min3-overview.png` |
| C4 | After deploy | app-min3 → Revisions and replicas | All 3 replicas listed under one revision; running state green | `04-app-min3-revisions-replicas-baseline.png` |
| C6 | Anytime after Phase 1 has produced samples | Log Analytics → Logs editor | Q1 ingestion-check query pasted, returning `HealthRatio` near 1.0 | `06-log-analytics-q1-ingestion.png` |
| C7 | After perturbation run #1 | Log Analytics → Logs editor | Q3 clustered-churn query showing the perturbation-induced row | `07-log-analytics-q3-clustered-churn.png` |
| C11 | After perturbation runs | app-min3 → Metrics blade | Replica Count + Restart Count chart showing the perturbation dip and recovery | `11-app-min3-metrics-replicas.png` |

**Optional captures (2) — add depth if time and signal allow**

| # | When | Portal blade | What it proves | Filename |
|---|---|---|---|---|
| C10 | After perturbation runs across all three apps | Log Analytics → Logs editor | Q7 multi-app comparison, side-by-side `MaxReplacementFraction` | `10-log-analytics-q7-multi-app.png` |
| C12 | After perturbation runs | app-min3 → Log stream (live) | Real-time logs showing the restart sequence (ContainerTerminated → ContainerStarted) | `12-app-min3-log-stream.png` |

**Conditional captures (4) — depend on optional setup or specific scenarios**

| # | Condition | Portal blade | Filename |
|---|---|---|---|
| C9 | Only after you deploy the optional custom subject-app image. With the default `helloworld` image, the `AppRequests` table has no rows to display. | Log Analytics → Logs editor | `09-log-analytics-q5-503-correlation.png` |
| C13 | Only after you deploy the optional 3-panel workbook covering Q3 + Q4 + Q7. The workbook ARM template ships at `labs/zone-redundancy-best-effort/workbook/`. | Azure Monitor → Workbooks | `13-workbook-3-panel-overview.png` |
| C6a | If your reviewer also asks for the result-table-only screenshot separated from the editor view | Log Analytics → Logs editor (result pane) | `06a-log-analytics-q1-ingestion-table.png` |
| C14 | Only if you wire up an Azure Monitor alert on Q3 during the lab and need to evidence the firing alert | Azure Monitor → Alerts | `14-azure-monitor-alert.png` |

## See Also

- [AGENTS.md → Portal Screenshot Capture (PII Replacement Rules)](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/AGENTS.md#portal-screenshot-capture-pii-replacement-rules) — authoritative PII replacement rules and the inline `browser_run_code_unsafe` snippet for MCP Playwright captures.
- [`scripts/portal-capture-helpers.js`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.js) — the reusable helper that applies PII replacement and masks the Account-menu avatar in one call.
- [`scripts/portal-capture-helpers.md`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.md) — usage instructions for both standalone Playwright and the MCP `browser_run_code_unsafe` tool.
- [Contributing](./index.md) — repository structure, document templates, and contribution workflow.
