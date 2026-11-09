---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management
  diagrams:
    - id: bicep-deployment-timeout-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
content_validation:
  status: verified
  last_reviewed: 2026-07-18
  reviewer: ai-agent
  core_claims:
    - claim: Revision-scope changes create a new revision in Azure Container Apps.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: Azure Container Apps uses revision lifecycle behavior during deployments and cutovers.
      source: https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management
      verified: true
    - claim: Troubleshooting guidance for Container Apps includes checking provisioning, configuration, and runtime signals when deployments do not complete successfully.
      source: https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
      verified: true
---
# Bicep Deployment Timeout

## Symptom

An ARM or Bicep deployment that updates a Container App takes much longer than expected or ends with a deployment timeout while the target revision remains in `Provisioning`, `Running: Processing`, or `Provisioning failed`. The control plane accepted the template, but the workload never reached a ready state quickly enough for the deployment window.

<!-- diagram-id: bicep-deployment-timeout-flow -->
```mermaid
flowchart TD
    accTitle: Diagnose a Bicep deployment waiting on a revision
    accDescr: Determine whether an accepted deployment created a revision that became healthy or stalled during image startup, configuration, or health verification.

    DEPLOY[Bicep or ARM deployment accepted]
    SCOPE{Revision-scope change?}
    APP[Application-scope configuration updates]
    APP_RESULT{Application-scope operation result}
    REVISION[New immutable revision]
    READY{Revision becomes healthy?}
    COMPLETE_APP[Application-scope operation completes]
    COMPLETE_REV[Revision deployment completes]
    WAIT_APP[Application-scope operation reports failure]
    WAIT_REV[Revision deployment waits or reports failure]
    EVIDENCE[Inspect provisioning state, system logs, console logs, and probes]

    DEPLOY --> SCOPE
    SCOPE -->|No| APP
    SCOPE -->|Yes| REVISION
    APP --> APP_RESULT
    APP_RESULT -->|Succeeded| COMPLETE_APP
    APP_RESULT -->|Failed| WAIT_APP
    REVISION --> READY
    READY -->|Yes| COMPLETE_REV
    READY -->|No| WAIT_REV
    WAIT_APP --> EVIDENCE
    WAIT_REV --> EVIDENCE

    LEGEND["Arrow key<br/>solid = deployment and diagnostic progression"]
```

*Figure: First distinguish application-scope updates from revision-scope changes, then use revision evidence to explain the wait.*

## Possible Causes

- The deployment created a new revision, but the container never became ready.
- Startup, readiness, or liveness probes are too aggressive for the application's boot time.
- Image pull, registry access, DNS, or VNet connectivity problems block provisioning.
- The template is valid syntactically, but the runtime configuration is not viable.
- Single revision mode waits for a healthy replacement revision before traffic cutover, extending deployment time.

## Diagnosis Steps

1. Check whether the deployment change was revision-scoped.
2. Inspect revision state and health instead of looking only at the deployment operation status.
3. Review system logs for probe failures, startup errors, or image pull delays.
4. Compare the failing revision with the last known good revision.

```bash
az containerapp revision list \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output table

az containerapp revision show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "<revision-name>"

az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --output json
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp revision list` | Enumerates revision records to assemble revision inventory for comparison. |
| `--name` (`az containerapp revision list`) | Lists revisions belonging to `$APP_NAME`. |
| `--resource-group` (`az containerapp revision list`) | Looks for revision history in `$RG`, where the timed-out deployment created the app. |
| `--output` (`az containerapp revision list`) | Emits the response as `table` so the decisive fields remain usable in this diagnostic step. |
| `az containerapp revision show` | Reads the selected revision's provisioning details to evaluate the Azure state that distinguishes this hypothesis. |
| `--name` (`az containerapp revision show`) | Resolves `<revision-name>` under `$APP_NAME`. |
| `--resource-group` (`az containerapp revision show`) | Resolves `<revision-name>` within `$RG` before inspecting its provisioning details. |
| `--revision` (`az containerapp revision show`) | Selects revision `<revision-name>`, whose provisioning or replica state is being tested. |
| `az containerapp show` | Reads the selected Container App so the operator can evaluate resource configuration record. |
| `--name` (`az containerapp show`) | Reads the parent app `$APP_NAME` after revision inspection. |
| `--resource-group` (`az containerapp show`) | Reads the parent app from `$RG` after the revision-level checks. |
| `--output` (`az containerapp show`) | Keeps the diagnosis steps result in the representation required by the next comparison or shell assignment. |


```bash
az containerapp logs show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --type system
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp logs show` | Reads the selected Container App log stream so the operator can evaluate runtime log stream. |
| `--name` (`az containerapp logs show`) | Retrieves timeout evidence for `$APP_NAME`. |
| `--resource-group` (`az containerapp logs show`) | Searches `$RG` for the app's system-log stream that records deployment timeout causes. |
| `--type` (`az containerapp logs show`) | Chooses the `system` log stream because it carries the expected failure signal. |


## Resolution

1. Fix the actual revision readiness issue first: probes, image startup, registry access, secret references, or network dependencies.
2. Redeploy so the platform creates a new healthy revision.
3. If the rollout is blocking production and multiple revision mode is enabled, keep traffic on the previous healthy revision until the new revision is proven healthy.
4. Reduce deployment blast radius by testing revision-scope changes separately before a full infrastructure run.

Typical focus areas:

- Increase startup probe delays for slow boot paths.
- Verify the container image and entrypoint locally before redeploying.
- Confirm ACR authentication, DNS resolution, and egress to required dependencies.
- Separate infrastructure provisioning from application revision rollout when debugging long deployments.

## Prevention

- Treat long Bicep deployments as a revision health problem first, not only a template problem.
- Keep startup paths small and predictable so readiness completes within the deployment window.
- Validate probe settings and dependent services in a pre-production environment.
- Roll out high-risk changes with multiple revisions and explicit traffic control when possible.
- Capture revision status and system logs automatically in CI/CD after each deployment.

## See Also

- [Bicep Deployment Timeout Lab](../../lab-guides/bicep-deployment-timeout.md)
- [Revision Provisioning Failure](../startup-and-provisioning/revision-provisioning-failure.md)
- [Probe Failure and Slow Start](../startup-and-provisioning/probe-failure-and-slow-start.md)

## Sources

- [Application lifecycle management in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management)
- [Revisions in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Troubleshoot Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
