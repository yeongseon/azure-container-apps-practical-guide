---
content_sources:
  diagrams:
  - id: architecture
    type: flowchart
    source: mslearn-adapted
    based_on:
    - https://learn.microsoft.com/azure/container-apps/traffic-splitting
    - https://learn.microsoft.com/azure/container-apps/revisions
    - https://learn.microsoft.com/azure/container-apps/blue-green-deployment
content_validation:
  status: verified
  last_reviewed: '2026-04-29'
  reviewer: ai-agent
  lab_validation:
    status: reproduced
    tested_date: 2026-06-03
    az_cli_version: 2.71.0
    notes: 'Live 50/50 split reproduced via image-swap workaround. The original
      trigger.sh uses `az containerapp update --target-port 9999` which (a) is rejected
      by CLI 2.71.0 (unrecognized argument) and (b) is architecturally unable to
      reproduce per-revision failure because `targetPort` is an ingress-level
      setting shared across all revisions. Replacement pattern: keep ingress
      targetPort stable and deploy a new revision with an image whose listening
      port does not match (e.g. aspnetapp on :8080 with ingress targetPort=80).
      Empirical curl loop: 15/30 success, 15/30 timeout — exactly 50/50.'
  core_claims:
  - claim: Azure Container Apps can split traffic between multiple active revisions by assigning traffic weights.
    source: https://learn.microsoft.com/azure/container-apps/traffic-splitting
    verified: true
  - claim: To route traffic to more than one revision in Azure Container Apps, the app must use multiple revision mode.
    source: https://learn.microsoft.com/azure/container-apps/revisions
    verified: true
validation:
  az_cli:
    last_tested: null
    cli_version: null
    result: not_tested
  bicep:
    last_tested: null
    result: not_tested
---
# Traffic Routing and Canary Failure Lab

Practice traffic splitting between revisions and learn to diagnose scenarios where a bad revision receives production traffic.

## Lab Metadata

| Attribute | Value |
|---|---|
| Difficulty | Intermediate |
| Estimated Duration | 20-30 minutes |
| Tier | Consumption |
| Failure Mode | Bad revision receiving 50% traffic causes intermittent failures |
| Skills Practiced | Traffic splitting, revision management, rollback |

## 1) Background

Azure Container Apps supports traffic splitting between multiple revisions, enabling canary deployments, blue-green releases, and A/B testing. When `activeRevisionsMode` is set to `Multiple`, you can assign traffic weights to each revision.

A common failure scenario occurs when:

1. A new revision is deployed with a misconfiguration (wrong port, broken code, etc.)
2. Traffic is split between the good and bad revisions
3. Users experience intermittent failures—some requests succeed (good revision), others fail (bad revision)

This lab simulates this scenario by:

1. Deploying a healthy baseline revision
2. Creating a bad revision with an incorrect target port (9999)
3. Splitting traffic 50/50 between good and bad revisions
4. Observing intermittent failures and practicing rollback

### Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    A[User Request] --> B[Ingress Controller<br/>targetPort=80]
    B --> C{Traffic Split}
    C -->|50%| D[Good Revision<br/>image listens on :80 ✓]
    C -->|50%| E[Bad Revision<br/>image listens on :8080 ✗]
    D --> F[HTTP 200]
    E --> G[Probe fails → timeout / 5xx]
```

## 2) Hypothesis

**IF** traffic is split 50/50 between a healthy revision and a revision whose container image listens on a port that does not match the ingress `targetPort`, **THEN** approximately 50% of requests will fail (timeout or 5xx) because ingress cannot reach the listening process on the bad revision's replicas.

| Variable | Control State | Experimental State |
|---|---|---|
| Revision Count | 1 (healthy) | 2 (healthy + bad) |
| Traffic Split | 100% to healthy | 50% healthy, 50% bad |
| Bad Revision Listening Port | n/a | `:8080` (mismatched against ingress `targetPort=80`) |
| Request Success Rate | ~100% | ~50% (the bad-revision half times out) |

## 3) Runbook

### Deploy Baseline Infrastructure

```bash
export RG="rg-aca-lab-traffic"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --name "lab-traffic" \
    --resource-group "$RG" \
    --template-file "./labs/traffic-routing-canary/infra/main.bicep" \
    --parameters baseName="labtraffic"
```

| Command | Why it is used |
|---|---|
| `az group create ...` | Creates the isolated resource group used by the example. |

### Capture Resource Names

```bash
export APP_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-traffic" \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)"

export APP_FQDN="$(az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.configuration.ingress.fqdn" \
    --output tsv)"
```

### Verify Baseline (Before Trigger)

```bash
# Confirm single revision with 100% traffic
az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list ...` | Lists revisions so rollout state, traffic, and health can be verified. |

Expected output:

```text
Name                          Active    TrafficWeight    HealthState
----------------------------  --------  ---------------  -----------
ca-labtraffic-xxxxxx--xxxxx   True      100              Healthy
```

```bash
# Confirm endpoint is fully reachable
for i in {1..5}; do
    curl --silent --fail "https://${APP_FQDN}" > /dev/null && echo "Request $i: OK"
done
```

Expected: All 5 requests succeed.

### Trigger the Failure

!!! warning "trigger.sh is broken with `az` CLI 2.71.0+ and is architecturally flawed"
    The committed `labs/traffic-routing-canary/trigger.sh` runs `az containerapp update --target-port 9999`, which:

    1. **Is rejected by CLI 2.71.0+** with `unrecognized arguments: --target-port 9999` (the flag was removed from `az containerapp update`; it now lives only on `az containerapp ingress update --target-port`).
    2. **Cannot create per-revision failure even if it worked.** `targetPort` is an ingress-level setting shared across all revisions — flipping it would break the good revision too, not just the canary. There is no "bad revision serving on port 9999 while the good revision still serves on port 80" state reachable through `--target-port`.

    Use the image-swap workaround below to actually reproduce the 50/50 failure scenario. The fix is to leave ingress `targetPort` stable and create a new revision whose container image listens on a different port.

```bash
# Record the current healthy revision name BEFORE creating the bad one
GOOD_REVISION="$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query 'sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name' \
    --output tsv)"

# Create a bad revision by swapping the image to one that listens on a DIFFERENT
# port than the ingress targetPort (kept at 80). aspnetapp listens on :8080,
# so the readiness probe fails on the bad revision while the good revision
# (hello-world on :80) keeps serving traffic.
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --image "mcr.microsoft.com/dotnet/samples:aspnetapp" \
    --revision-suffix "badv2"

# Wait for the new revision to finish provisioning + probe attempts
sleep 60

BAD_REVISION="$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query 'sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name' \
    --output tsv)"

# Split traffic 50/50
az containerapp ingress traffic set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision-weight "${GOOD_REVISION}=50" "${BAD_REVISION}=50"
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list ... created[-1]` | Captures the name of the most recently created (currently healthy) revision before introducing the bad one. |
| `az containerapp update --image ... --revision-suffix badv2` | Creates a new revision whose container image listens on `:8080`, but ingress `targetPort` is still `80`. Probe failure isolates the bad behavior to this revision only. |
| `sleep 60` | Allows the new revision to finish creation, replica scheduling, and the first round of probe attempts before traffic is split. |
| `az containerapp ingress traffic set --revision-weight` | Splits ingress traffic 50/50 between the recorded good revision and the newly created bad revision. |

### Observe the Failure

```bash
# Check revision list - should show two revisions
az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "[].{name:name,active:properties.active,traffic:properties.trafficWeight,health:properties.healthState}" \
    --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list ...` | Lists revisions so rollout state, traffic, and health can be verified. |

Expected output:

```text
Name                          Active    Traffic    Health
----------------------------  --------  ---------  --------
ca-labtraffic-xxxxxx--xxxxx   True      50         Healthy
ca-labtraffic-xxxxxx--yyyyy   True      50         Healthy
```

Note: Both revisions may show "Healthy" because the health check might pass—the container is running, just on the wrong port.

```bash
# Test multiple requests - observe intermittent failures.
# IMPORTANT: use --max-time. The bad revision does not emit a graceful 502 from
# ingress; the connection just hangs because the upstream listening port is wrong.
# Without --max-time, the loop appears to "freeze" instead of showing failures.
for i in $(seq 1 30); do
    STATUS=$(curl --silent --output /dev/null --max-time 10 --write-out "%{http_code}" "https://${APP_FQDN}/")
    echo "Request $i: HTTP $STATUS"
done
```

Expected: Approximately 50% return `200`, 50% return `000` (curl timeout code, because the bad revision's replica never responds within `--max-time`).

```bash
# View current traffic distribution
az containerapp ingress traffic show \
    --name "$APP_NAME" \
    --resource-group "$RG"
```

| Command | Why it is used |
|---|---|
| `az containerapp ingress traffic ...` | Runs the Azure CLI operation required by the documented step. |

### Fix the Issue (Rollback)

Rollback by sending 100% traffic to the good revision:

```bash
# Get the good revision name (the one created first)
GOOD_REVISION=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "sort_by([].{name:name,created:properties.createdTime}, &created)[0].name" \
    --output tsv)

# Send all traffic to good revision
az containerapp ingress traffic set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision-weight "${GOOD_REVISION}=100"
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list ...` | Lists revisions so rollout state, traffic, and health can be verified. |

Optionally, deactivate the bad revision:

```bash
BAD_REVISION=$(az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "sort_by([].{name:name,created:properties.createdTime}, &created)[-1].name" \
    --output tsv)

az containerapp revision deactivate \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "$BAD_REVISION"
```

### Verify the Fix

```bash
# Confirm traffic is 100% to good revision
az containerapp ingress traffic show \
    --name "$APP_NAME" \
    --resource-group "$RG"

# Test multiple requests - all should succeed
for i in {1..10}; do
    STATUS=$(curl --silent --output /dev/null --write-out "%{http_code}" "https://${APP_FQDN}")
    echo "Request $i: HTTP $STATUS"
done
```

Expected: All requests return HTTP 200.

## 4) Experiment Log

| Step | Action | Expected | Actual | Pass/Fail |
|---|---|---|---|---|
| 1 | Deploy baseline | Single healthy revision | | |
| 2 | Test baseline | 100% success rate | | |
| 3 | Run trigger.sh | Two revisions at 50/50 | | |
| 4 | Test requests | ~50% failure rate | | |
| 5 | Rollback traffic | 100% to good revision | | |
| 6 | Test after rollback | 100% success rate | | |

## Expected Evidence

### During Failure

| Evidence Source | Expected State |
|---|---|
| `az containerapp revision list` | 2 revisions, both Active |
| `az containerapp ingress traffic show` | 50/50 split |
| Request loop | ~50% HTTP 502 |

### After Rollback

| Evidence Source | Expected State |
|---|---|
| `az containerapp ingress traffic show` | 100% to good revision |
| Request loop | 100% HTTP 200 |
| Bad revision | Deactivated (optional) |

### Observed Evidence (Live Azure Test — 2026-05-01)

**Environment:** `rg-aca-lab-test6` / `cae-lab6`, `koreacentral`, Consumption plan.
**App:** `ca-canary` (multiple-revision mode), FQDN: `<container-app-fqdn>`.

[Observed] Switched to multiple-revision mode: `az containerapp revision set-mode --mode multiple`.

[Observed] Two revisions deployed: `ca-canary--stable` (Running) and `ca-canary--canary` (Running, VERSION=canary).

[Observed] Traffic split applied: `az containerapp ingress traffic set --revision-weight "ca-canary--stable=90" "ca-canary--canary=10"`.

[Observed] `az containerapp revision list` returned: `ca-canary--stable weight=90`, `ca-canary--canary weight=10` — both Running.

[Measured] HTTP request to FQDN: `curl https://<container-app-fqdn>/` → **HTTP 200**.

[Inferred] 90/10 traffic split routes approximately 1 in 10 requests to the canary revision. Both revisions serve the same image (different env var), so all requests return HTTP 200. A real canary with a broken image would show HTTP 5xx from the 10% canary traffic.

Environment: `koreacentral`, Consumption plan, multiple-revision mode.

### Observed Evidence (Live Azure Reproduction — 2026-06-03)

**Environment:** `rg-aca-lab-traffic` / `cae-labtraffic-l6uluw`, `koreacentral`, Consumption plan, `az` CLI `2.71.0`.
**App:** `ca-labtraffic-l6uluw` (multiple-revision mode), ingress `targetPort=80`.
**Revisions:**

- Good: `ca-labtraffic-l6uluw--pnjn5yn` — image `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`, listens on `:80` — Running, 50% traffic.
- Bad: `ca-labtraffic-l6uluw--badv2` — image `mcr.microsoft.com/dotnet/samples:aspnetapp`, listens on `:8080` — Failed, 50% traffic.

[Observed] The Container App Overview blade surfaced the bad revision under the "Revisions with Issues" tab with the verbatim platform error message **"The TargetPort 80 does not match the listening port 8080. 1/1 Container crashing: app"** — proving the platform itself attributes the failure to the listening-port mismatch on the bad revision, not to ingress misconfiguration.

![Container App Overview blade showing the Revisions with Issues tab with the TargetPort/listening port mismatch error for badv2](../../assets/troubleshooting/traffic-routing-canary/01-overview-multi-revision-mode.png)

[Observed] The Revisions and replicas blade showed both revisions Active at 50/50, with the bad revision marked `Failed` and the good revision marked `Running`, each with one replica. This is the smoking gun for the canary-failure hypothesis: half of production traffic is routed to a revision the platform has already marked Failed.

![Revisions and replicas blade showing badv2=Failed/50% and pnjn5yn=Running/50%, both Active, both with one replica](../../assets/troubleshooting/traffic-routing-canary/02-revisions-50-50-split.png)

[Observed] Drilling into the bad revision's "View details" flyout repeated the same root cause as a Revision status detail, isolating the failure to the bad revision only (the good revision's flyout — capture 05 — shows the same field empty).

![Revision status details flyout for badv2 showing TargetPort 80 does not match listening port 8080](../../assets/troubleshooting/traffic-routing-canary/03-bad-revision-status-details.png)

[Observed] The Ingress blade confirmed `Target port = 80` was unchanged throughout the experiment. This falsifies the "ingress misconfiguration" hypothesis and confirms the failure is per-revision (caused by the bad image's listening port, not by a shared ingress setting). It is also what makes the original `trigger.sh` design fundamentally unable to reproduce this scenario — flipping ingress `targetPort` would affect both revisions, not isolate the failure to one.

![Ingress blade showing Target port = 80 unchanged](../../assets/troubleshooting/traffic-routing-canary/04-ingress-target-port-80.png)

[Observed] In contrast, the good revision's "View details" flyout reported `Running status: Running` with **"There are no additional running status details at this time"** — i.e. the Status details field is empty precisely because nothing is wrong with this revision. The contrast between capture 03 (bad: TargetPort error populated) and capture 05 (good: empty) is itself the per-revision isolation evidence.

![Revision status details flyout for pnjn5yn showing Running with empty Status details](../../assets/troubleshooting/traffic-routing-canary/05-good-revision-running-details.png)

[Observed] The Activity log recorded exactly three `Create or Update Container App` operations within an 18-minute window — corresponding to (a) the initial `az deployment group create`, (b) the `az containerapp update --image ... --revision-suffix badv2` that created the bad revision, and (c) the `az containerapp ingress traffic set --revision-weight` that applied the 50/50 split. All three Accepted/Succeeded, confirming the control plane received each step.

![Activity log showing three Create or Update Container App operations within an 18-minute window](../../assets/troubleshooting/traffic-routing-canary/06-activity-log-update-operations.png)

[Measured] A `curl` loop of 30 requests with `--max-time 10` against the FQDN produced **15 HTTP 200 responses and 15 timeouts (curl status `000`)** — an exact 50/50 split, matching the traffic-weight setting. The bad-revision half did not return a graceful HTTP 502; ingress simply did not get a response from the upstream replica because the listening port did not match. This is why `--max-time` is mandatory in the reproduction loop above.

```text
Request 1: HTTP 200
Request 2: HTTP 000
Request 3: HTTP 200
Request 4: HTTP 000
...
(Summary: success=15, timeout=15)
```

[Inferred] The combination of (a) Portal's verbatim "TargetPort 80 does not match listening port 8080" error, (b) the empty status details on the good revision, (c) ingress `targetPort` unchanged at 80, and (d) the 15/15 split in the curl loop confirms the hypothesis: a per-revision listening-port mismatch on one of two revisions receiving 50% traffic produces a ~50% failure rate. The hypothesis is also strengthened by the falsification target — the original `trigger.sh` design (flipping ingress `targetPort`) cannot reach this state because ingress `targetPort` is shared across revisions; the image-swap workaround in the runbook is the minimal reproduction that actually isolates the failure to a single revision.

## Portal Evidence Capture Guide

Engineers reproducing this lab should attach Azure Portal screenshots to the **Observed Evidence** section above. The captures make the hypothesis falsifiable from the UI (not just CLI) and align this lab with the [scale-rule-mismatch](./scale-rule-mismatch.md) template.

### Capture rules (apply to every screenshot)

- **Full-screen browser capture only.** Capture the entire browser window (URL bar, Portal chrome, breadcrumb). Do not crop to a single chart — reviewers must be able to verify the blade, filters, and time range.
- **PII must be replaced (not black-box masked) before commit.** Use the helper at [`scripts/portal-capture-helpers.js`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/scripts/portal-capture-helpers.js) (or the inline snippet documented in [`AGENTS.md`](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/main/AGENTS.md#portal-screenshot-capture-pii-replacement-rules)) to substitute real GUIDs/emails/tenant names with documented placeholders. Black rectangles look like leaks and are disallowed; the only acceptable mask is the Portal-blue (`#0078d4`) avatar mask applied by the helper.

### PII masking checklist

- [ ] Subscription ID (URL bar, breadcrumb, resource ID column)
- [ ] Tenant ID (URL bar, account flyout)
- [ ] Account menu top-right (display name, email, avatar initials)
- [ ] Directory / tenant name in the top-right switcher
- [ ] Real customer resource group / app / environment names (rename to lab-defaults if reused from a customer tenant)
- [ ] Email addresses in any Activity log, Access control, or Owner column
- [ ] Real Object IDs, Principal IDs, Client IDs in identity blades

### Captures to take

| # | When | Portal blade | View / filters | Filename |
|---|---|---|---|---|
| 1 | After the bad canary revision is created | Container App → Revisions | Full revisions list showing both stable and canary revisions active | `traffic-routing-canary-revisions-before-rollback.png` |
| 2 | During the incident | Container App → Traffic splitting | Traffic panel showing the canary split that sends production traffic to both revisions | `traffic-routing-canary-traffic-split.png` |
| 3 | During the incident | Container App → Monitoring → Metrics | Metric `Requests`, split by `Revision name` or `Status code category`, time `Last 15 minutes`, showing the intermittent failure pattern | `traffic-routing-canary-requests-by-revision.png` |
| 4 | During rollback | Container App → Traffic splitting | Traffic panel showing 100% restored to the stable revision | `traffic-routing-canary-traffic-after-rollback.png` |
| 5 | After rollback validation | Container App → Revisions | Revisions list showing the bad canary at 0% traffic or deactivated while the stable revision remains active | `traffic-routing-canary-revisions-after-rollback.png` |

### Asset path

Save PNGs to `docs/assets/troubleshooting/traffic-routing-canary/` (create the directory if it does not exist).

### Reference captures in Observed Evidence

Add image references inside the **Observed Evidence (Live Azure Test)** subsection above, paired with `[Observed]` evidence tags:

```markdown
[Observed] Production traffic was intentionally split across both the stable and canary revisions during the failure window:

![Traffic split between stable and canary revisions](../../assets/troubleshooting/traffic-routing-canary/traffic-routing-canary-traffic-split.png)

[Observed] Rollback completed when traffic was returned fully to the stable revision and the canary stopped receiving requests:

![Traffic restored to the stable revision after rollback](../../assets/troubleshooting/traffic-routing-canary/traffic-routing-canary-traffic-after-rollback.png)
```

## Clean Up

```bash
az group delete --name "$RG" --yes --no-wait
```

| Command | Why it is used |
|---|---|
| `az group delete ...` | Removes the lab resource group and its contained resources. |

## Related Playbook

- [Bad Revision Rollout and Rollback](../playbooks/platform-features/bad-revision-rollout-and-rollback.md)

## See Also

- [Revision Failover Lab](./revision-failover.md)
- [Revision Provisioning Failure Lab](./revision-provisioning-failure.md)

## Sources

- [Traffic splitting in Azure Container Apps](https://learn.microsoft.com/azure/container-apps/traffic-splitting)
- [Revisions in Azure Container Apps](https://learn.microsoft.com/azure/container-apps/revisions)
- [Blue-green deployment for Azure Container Apps](https://learn.microsoft.com/azure/container-apps/blue-green-deployment)
