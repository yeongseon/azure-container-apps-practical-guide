---
content_sources:
  diagrams:
    - id: shift-traffic-only-when-release-criteria
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
        - https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment
    - id: when-slo-and-dependency-metrics
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
        - https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment
    - id: deactivate-stale-revisions-after-confidence-window
      type: sequenceDiagram
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
        - https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment
content_validation:
  status: verified
  last_reviewed: 2026-11-07
  reviewer: agent
  core_claims:
    - claim: Revisions are immutable snapshots of each version of a container app.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Azure Container Apps supports single and multiple revision modes.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: In multiple revision mode, you can have multiple active revisions and split traffic between revisions.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Labels provide unique URLs that route traffic to specific revisions.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Container Apps doesn't charge for inactive revisions and purges the oldest inactive revisions after the available revision count exceeds 100.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
---
# Revision Strategy Best Practices for Azure Container Apps

This guide explains how to operate revisions as a controlled release mechanism in Azure Container Apps, including rollout safety, rollback speed, and lifecycle hygiene. It focuses on practical decision patterns you can apply in production pipelines.

Use this page for the decision framework, then go deeper with the dedicated [Blue/Green Deployment](blue-green-deployment.md) and [Canary Deployment](canary-deployment.md) playbooks.

## Why This Matters

Production Container Apps behavior depends on explicit platform choices for ingress, scale, identity, observability, and release safety. This page turns the cited Microsoft Learn guidance into reviewable practices that can be checked before promotion.

## Prerequisites

- Azure CLI 2.57+ with Container Apps extension
- Existing app (`$APP_NAME`) in resource group (`$RG`) and environment (`$ACA_ENV_NAME`)
- Container image in Azure Container Registry (`$ACR_NAME`)
- Team agreement on release gates and rollback criteria

```bash
az extension add --name containerapp --upgrade
az containerapp show --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
```


| Command | Purpose |
|---|---|
| `az extension add` | Installs or updates the Container Apps Azure CLI extension. |
| `--name` | Selects the target container app or extension. |
| `--upgrade` | Updates the extension when an older version is installed. |
| `az containerapp show` | Shows the selected container app configuration. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--output` | Selects the command output format. |
| `az containerapp revision list` | Lists revisions and their current operational fields. |


## Recommended Practices

### Treat revisions as the unit of release risk

A revision is immutable once created. That immutability gives you repeatability if and only if your release process is revision-first.

Revision-first release means:

1. Build one immutable image tag.
2. Deploy that image to create one revision candidate.
3. Validate health and telemetry on that specific revision.
4. Shift traffic only when release criteria pass.

<!-- diagram-id: shift-traffic-only-when-release-criteria -->
```mermaid
flowchart TD
    accTitle: Release gate for a revision candidate
    accDescr: An immutable image creates a candidate revision. Readiness and release evidence decide whether production traffic shifts or remains on the stable revision.

    IMAGE["Immutable image<br/>release identifier"]
    CANDIDATE["Candidate revision<br/>immutable app version"]
    READY["Gate 1<br/>startup and readiness probes"]
    EVIDENCE["Gate 2<br/>errors, latency, dependencies"]
    PROMOTE["Shift production traffic<br/>to candidate"]
    HOLD["Keep traffic on<br/>stable revision"]
    INVESTIGATE["Inspect candidate logs,<br/>probes, and dependencies"]

    IMAGE -->|Deploy revision-scope change| CANDIDATE
    CANDIDATE --> READY
    READY -->|Pass| EVIDENCE
    READY -->|Fail| HOLD
    EVIDENCE -->|Pass| PROMOTE
    EVIDENCE -->|Fail| HOLD
    HOLD --> INVESTIGATE
```

*Figure: Readiness is necessary but not sufficient for promotion. Traffic remains on the known-good revision until both platform readiness and the release team's explicit evidence gates pass.*

### Decide single vs multiple revision mode by release complexity

Use revision mode as a product of operational complexity, not developer preference.

| Decision point | Single mode | Multiple mode |
|---|---|---|
| Deployment simplicity | Highest | Moderate |
| Canary and staged rollout | Not suitable | Native fit |
| Rollback speed | Fast for simple replace | Fast with pre-warmed old revision |
| Operational overhead | Low | Higher |
| Experimentation (A/B) | Limited | Strong |

Use **single revision mode** when:

- The app is low-risk and stateless.
- You deploy frequently with narrow blast radius.
- You do not need partial traffic exposure.

Use **multiple revision mode** when:

- You need canary, blue-green, or A/B routing.
- You want quick rollback by weight reassignment.
- You must run controlled side-by-side validation.

```bash
az containerapp revision set-mode \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --mode multiple
```


| Command | Purpose |
|---|---|
| `az containerapp revision set-mode` | Sets stable single or multiple active revision mode. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--mode` | Specifies the active revision mode. |


!!! warning "Switching revision mode changes release behavior"
    In single mode, old revisions are automatically deactivated after successful replacement. In multiple mode, you must manage deactivation and traffic intentionally to avoid drift and unnecessary cost.

### Use a revision suffix convention that is machine-sortable

Revision suffixes should encode release chronology and source identity.

Recommended suffix examples:

- `20260404-1`
- `20260404-2`
- `git-8f2c1d4`

Avoid opaque suffixes that force manual lookup.

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:20260404-1" \
  --revision-suffix "20260404-1"
```


| Command | Purpose |
|---|---|
| `az containerapp update` | Updates the app and creates a revision when revision-scope settings change. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--image` | Specifies the container image for the revision. |
| `--revision-suffix` | Sets a release-specific suffix on the new revision. |


Naming policy recommendations:

1. Keep suffix length short enough for readability in dashboards.
2. Include sortable date token for timeline reconstruction.
3. Include release sequence if multiple deployments per day occur.

### Use labels for stable endpoints and weights for controlled migration

Labels and traffic weights solve different operational problems.

| Need | Preferred mechanism | Why |
|---|---|---|
| Stable URL for specific revision | Revision label | Deterministic route for validation or partner integration |
| Gradual production shift | Traffic weights | Fine-grained progressive exposure |
| Instant failback | Traffic weights to previous revision | Fast rollback without redeploy |
| Parallel test environments | Labels | Isolated testing without affecting weighted production flow |

Label assignment example:

```bash
az containerapp revision label add \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$APP_NAME--20260404-1" \
  --label "candidate"
```


| Command | Purpose |
|---|---|
| `az containerapp revision label add` | Assigns a label URL to the selected revision. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--revision` | Selects the exact revision to manage. |
| `--label` | Specifies the revision label. |


Traffic weighting example:

```bash
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$APP_NAME--20260404-1=10" "$APP_NAME--20260403-4=90"
```


| Command | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Updates ingress traffic routing rules. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--revision-weight` | Assigns main-URL traffic percentages to named revisions. |


### Apply repeatable traffic splitting patterns

#### Canary rollout pattern

Use canary when you want statistical confidence before full migration.

Typical progression:

1. 5% for smoke + error budget check.
2. 25% for medium-volume observation.
3. 50% for sustained behavior under normal load.
4. 100% when SLO and dependency metrics remain healthy.

<!-- diagram-id: when-slo-and-dependency-metrics -->
```mermaid
flowchart TD
    accTitle: Canary traffic and evidence decision
    accDescr: The main application URL reaches managed ingress, which applies configured weights to active stable and canary revisions. Revision-scoped evidence decides whether to increase canary traffic or restore stable traffic.

    CLIENT["Request callers<br/>main application URL"]
    INGRESS["Managed Envoy ingress<br/>weighted request routing"]
    STABLE["Stable active revision<br/>example: 95 percent"]
    CANARY["Canary active revision<br/>example: 5 percent"]
    STABLE_REPLICAS["Stable revision replicas"]
    CANARY_REPLICAS["Canary revision replicas"]
    GATE["Evaluate SLO and<br/>dependency evidence"]
    ADVANCE["Increase canary weight<br/>in a controlled stage"]
    RESTORE["Restore stable revision<br/>to 100 percent"]

    CLIENT ==>|HTTPS request| INGRESS
    INGRESS ==>|Configured stable weight| STABLE
    INGRESS ==>|Configured canary weight| CANARY
    STABLE ==>|Route request| STABLE_REPLICAS
    CANARY ==>|Route request| CANARY_REPLICAS
    STABLE_REPLICAS -->|Baseline evidence| GATE
    CANARY_REPLICAS -->|Candidate evidence| GATE
    GATE -->|Healthy| ADVANCE
    GATE -->|Unhealthy| RESTORE

    LEGEND["Arrow key<br/>thick = request transport<br/>solid = evidence or release decision"]
```

*Figure: The percentages are an example, not a required progression. Compare stable and candidate evidence before changing the configured weights.*

Promotion criteria examples:

- Error rate delta < 0.3% vs baseline.
- P95 latency increase < 15%.
- No sustained liveness probe failures.

#### Blue-green pattern

Use blue-green when cutover must be fast and binary.

Flow:

1. Keep blue revision at 100% production traffic.
2. Deploy green revision with 0% traffic.
3. Validate green via revision label endpoint.
4. Switch traffic to green in one operation.
5. Keep blue active temporarily for immediate failback.

```bash
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$APP_NAME--green=100" "$APP_NAME--blue=0"
```


| Command | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Updates ingress traffic routing rules. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--revision-weight` | Assigns main-URL traffic percentages to named revisions. |


#### A/B pattern

Use A/B when comparing behavior across revision variants.

- Keep experiment duration bounded.
- Define explicit success metrics in advance.
- Avoid long-lived A/B states that complicate operations.

### Design rollback as a first-class fast path

Rollback should be one command and one decision, not a multi-step scramble.

Rollback readiness checklist:

- Previous stable revision remains active during rollout window.
- Traffic command is scripted in pipeline.
- Alert routing includes release context.
- On-call has clear rollback threshold.

Rollback command pattern:

```bash
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$APP_NAME--20260403-4=100" "$APP_NAME--20260404-1=0"
```


| Command | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Updates ingress traffic routing rules. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--revision-weight` | Assigns main-URL traffic percentages to named revisions. |


!!! warning "Do not rollback by rebuilding old image"
    Rebuild-based rollback is slower and may not reproduce the same artifact. Route traffic back to an existing known-good revision whenever possible.

### Build a zero-downtime deployment workflow

Zero-downtime in Container Apps depends on health-gated promotion and controlled traffic movement.

Recommended workflow:

1. Deploy new image with explicit revision suffix.
2. Keep traffic on current stable revision.
3. Validate startup/readiness and key telemetry on new revision.
4. Shift traffic gradually or switch atomically by strategy.
5. Observe post-cutover SLO window.
6. Deactivate stale revisions after confidence window ends.

<!-- diagram-id: deactivate-stale-revisions-after-confidence-window -->
```mermaid
sequenceDiagram
    accTitle: Health-gated revision promotion and cleanup sequence
    accDescr: The release pipeline creates a candidate, validates it through its label URL, changes main application traffic only after the gate passes, observes a confidence window, and then deactivates the stale revision.

    actor OP as Release pipeline
    participant CONTROL as Container Apps control plane
    actor CLIENT as Request caller
    participant LABEL as Candidate label URL
    participant INGRESS as Managed ingress
    participant CANDIDATE as Candidate replica
    participant STABLE as Stable replica
    participant OBS as Monitoring

    OP->>CONTROL: Deploy immutable image as candidate revision
    CONTROL-->>OP: Candidate provisioned and active
    OP->>LABEL: Resolve candidate validation endpoint
    OP->>INGRESS: HTTPS request to candidate label URL
    INGRESS->>CANDIDATE: Route to labeled revision
    CANDIDATE-->>INGRESS: Candidate response
    INGRESS-->>OP: Return validation response
    CANDIDATE-->>OBS: Emit candidate logs and metrics
    OBS-->>OP: Readiness and release evidence
    alt Release gate passes
        OP->>CONTROL: Update main URL traffic weights
        alt Representative request selects stable weight
            CLIENT->>INGRESS: Production request to main URL
            INGRESS->>STABLE: Route request to stable revision
            STABLE-->>INGRESS: Stable response
            INGRESS-->>CLIENT: Return stable response
        else Representative request selects candidate weight
            CLIENT->>INGRESS: Production request to main URL
            INGRESS->>CANDIDATE: Route request to candidate revision
            CANDIDATE-->>INGRESS: Candidate response
            INGRESS-->>CLIENT: Return candidate response
        end
        STABLE-->>OBS: Emit stable runtime telemetry
        CANDIDATE-->>OBS: Emit candidate runtime telemetry
        OBS-->>OP: Confidence window remains healthy
        OP->>CONTROL: Deactivate superseded revision
        CONTROL-->>OP: Superseded revision is inactive
    else Release gate fails
        OP->>CONTROL: Keep or restore stable traffic
        OP->>CONTROL: Deactivate failed candidate when evidence is captured
    end
```

*Figure: Label-based validation and main-URL traffic weights are separate controls. Deactivation happens only after the confidence window or after a failed candidate has been investigated.*

### Manage revision lifecycle to control cost and cognitive load

Active revisions consume resources and operational attention. Keep only what is useful.

Lifecycle policy suggestions:

- Keep at least one known-good fallback revision active during rollout.
- Deactivate superseded revisions after release confidence window.
- Regularly review inactive revision count and retention policy.
- Annotate release records with revision names for incident forensics.

List and deactivate example:

```bash
az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table

az containerapp revision deactivate \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$APP_NAME--20260328-2"
```


| Command | Purpose |
|---|---|
| `az containerapp revision list` | Lists revisions and their current operational fields. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--output` | Selects the command output format. |
| `az containerapp revision deactivate` | Deactivates the selected revision and stops its replicas. |
| `--revision` | Selects the exact revision to manage. |


### Avoid schema-coupled rollouts without compatibility windows

Multiple revisions can run concurrently against shared dependencies.

Compatibility practices:

1. Use expand-and-contract schema changes.
2. Make new code tolerate old fields and vice versa.
3. Delay destructive migrations until old revision traffic reaches zero.

### Combine revision strategy with autoscaling behavior

Traffic split affects load per revision, which affects scale events.

Operational implications:

- A small canary weight may still trigger autoscaling if request profile is bursty.
- Min replicas for canary revisions can reduce false negatives due to cold starts.
- Separate scale rule tuning may be needed for low-percentage revisions.

### Use release guardrails in automation

Codify release safety in CI/CD:

- Enforce immutable image tags.
- Require revision suffix on production deploy.
- Block traffic shift if health checks fail.
- Require explicit rollback plan per release.

Example update command in pipeline:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:$IMAGE_TAG" \
  --revision-suffix "$IMAGE_TAG"
```


| Command | Purpose |
|---|---|
| `az containerapp update` | Updates the app and creates a revision when revision-scope settings change. |
| `--name` | Selects the target container app or extension. |
| `--resource-group` | Selects the resource group that contains the app. |
| `--image` | Specifies the container image for the revision. |
| `--revision-suffix` | Sets a release-specific suffix on the new revision. |


### Operational checklist for every release

Pre-deploy:

- Stable revision identified and documented.
- Rollback command prepared.
- Alert thresholds confirmed.

Deploy:

- New revision created successfully.
- Probe health stable.
- Candidate telemetry baseline collected.

Promote:

- Traffic shifted according to chosen pattern.
- Error and latency deltas within threshold.

Post-deploy:

- Old revision retained only for defined fallback period.
- Release notes include final traffic state.
- Cleanup task scheduled.

### Verify revision state in Azure Portal

![ca-sample-d38538 | Revisions and replicas | Container App | Create new revision | Save | Refresh | Deployment mode | Send us your feedback | Active revisions | Inactive revisions | Replicas | Name | Date created | Running status | View Logs | Label | Traffic | Replicas | ca-sample-d38538--0uzoi59 | Running | View details | Show Logs | 100 % | 1 (Show replicas)](../assets/best-practices/revision-strategy-revisions-and-replicas.png)

**[Observed]** `ca-sample-d38538 | Revisions and replicas` `Container App` `Create new revision` `Save` `Refresh` `Deployment mode` `Send us your feedback` `Active revisions` `Inactive revisions` `Replicas` `Name` `Date created` `Running status` `View Logs` `Label` `Traffic` `Replicas` `ca-sample-d38538--0uzoi59` `6/3/2026, 10:34:26 PM` `Running` `View details` `Show Logs` `100 %` `1 (Show replicas)` `Overview` `Activity log` `Access control (IAM)` `Tags` `Application` `Containers` `Scale` `Volumes` `Settings` `Networking` `Ingress` `Custom domains` `CORS` `Security` `Monitoring` `Log stream` `Logs` `Console` `Alerts` `Metrics`.

**[Inferred]** The `Deployment mode` command-bar entry appears to map to the `az containerapp revision set-mode --mode multiple` operation documented in [Decide single vs multiple revision mode by release complexity](#decide-single-vs-multiple-revision-mode-by-release-complexity). The revision row `ca-sample-d38538--0uzoi59` is consistent with the `--revision-suffix` convention discussed in [Use a revision suffix convention that is machine-sortable](#use-a-revision-suffix-convention-that-is-machine-sortable). The empty `Label` column and the `100 %` value in `Traffic` are consistent with the `az containerapp revision label add` and weight-shifting flow documented in [Use labels for stable endpoints and weights for controlled migration](#use-labels-for-stable-endpoints-and-weights-for-controlled-migration). The `Active revisions` and `Inactive revisions` tabs are consistent with the `az containerapp revision list` and `az containerapp revision deactivate` operations documented in [Manage revision lifecycle to control cost and cognitive load](#manage-revision-lifecycle-to-control-cost-and-cognitive-load).

**[Not Proven]** Additional revision configuration detail, history detail, replica detail, and provisioning detail are not visible on this view.

## Advanced Topics

### Weighted promotion automation with safety windows

Automate canary progression with timed hold periods and automatic halt conditions when SLO deltas exceed thresholds.

### Revision labels for external contract testing

Use stable labels for partner validation endpoints to avoid coupling external tests to transient revision names.

### Incident forensics with revision-scoped telemetry

Correlate errors, latency spikes, and dependency failures by revision name to isolate whether issues are release-induced or platform/environmental.

### Coordinating revision rollout across multiple apps

For distributed systems, sequence rollouts by dependency direction and maintain compatibility windows so mixed-revision states remain safe.

## Common Mistakes / Anti-Patterns

- Treating sample defaults as production-ready without checking ingress, scale, identity, and monitoring requirements.
- Applying a configuration change without verifying the resulting revision, logs, and metrics.
- Leaving ownership for certificates, private DNS, secrets, or rollout decisions undocumented.

## Validation Checklist

- [ ] Required Container Apps settings are represented in infrastructure as code.
- [ ] The active revision, ingress, scale, identity, and monitoring state match the intended design.
- [ ] Rollback or cleanup commands have been tested in a non-production environment.

## See Also

- [Platform: Revisions](../platform/revisions/index.md)
- [Blue/Green Deployment](blue-green-deployment.md)
- [Canary Deployment](canary-deployment.md)
- [Platform: Scaling](../platform/scaling/index.md)
- [Operations: Revision Management](../operations/revision-management/index.md)
- [Operations: Deployment](../operations/deployment/index.md)
- [Python Guide: Revisions and Traffic](../language-guides/python/tutorial/07-revisions-traffic.md)
- [Microsoft Learn: Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment)
- [Microsoft Learn source 4](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
