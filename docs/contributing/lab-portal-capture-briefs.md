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

## See Also

- [AGENTS.md → Portal Screenshot Capture (PII Replacement Rules)](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/AGENTS.md#portal-screenshot-capture-pii-replacement-rules) — authoritative PII replacement rules and the inline `browser_run_code_unsafe` snippet for MCP Playwright captures.
- [`scripts/portal-capture-helpers.js`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.js) — the reusable helper that applies PII replacement and masks the Account-menu avatar in one call.
- [`scripts/portal-capture-helpers.md`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.md) — usage instructions for both standalone Playwright and the MCP `browser_run_code_unsafe` tool.
- [Contributing](./index.md) — repository structure, document templates, and contribution workflow.
