---
content_sources:
  diagrams:
    - id: revision-mode-comparison
      type: flowchart
      source: self-generated
      justification: Synthesized from Microsoft Learn guidance on single and multiple revision modes.
      based_on:
        - https://learn.microsoft.com/azure/container-apps/revisions
        - https://learn.microsoft.com/azure/container-apps/revisions-manage
content_validation:
  status: verified
  last_reviewed: "2026-04-25"
  reviewer: ai-agent
  core_claims:
    - claim: "Azure Container Apps supports single and multiple revision modes, and single revision mode is the default."
      source: "https://learn.microsoft.com/azure/container-apps/revisions"
      verified: true
    - claim: "In single revision mode, Container Apps provisions and activates the new revision and diverts traffic to it after it is ready."
      source: "https://learn.microsoft.com/azure/container-apps/revisions"
      verified: true
    - claim: "In multiple revision mode, you can keep more than one revision active and split traffic between revisions."
      source: "https://learn.microsoft.com/azure/container-apps/revisions"
      verified: true
    - claim: "The container app configuration property for revision mode is activeRevisionsMode."
      source: "https://learn.microsoft.com/azure/templates/microsoft.app/2026-01-01/containerapps"
      verified: true
---

# Revision Modes in Azure Container Apps

Revision mode decides whether Azure Container Apps keeps one active revision or several active revisions at the same time. It changes how deployment promotion, rollback, and traffic management work.

## Revision Modes

Azure Container Apps exposes revision mode through the `activeRevisionsMode` property.

| Mode | Active revisions | Best fit | Operational effect |
|---|---|---|---|
| `Single` | One | Standard production updates, simple zero-downtime replacement | Platform activates the new revision and deprovisions the old one after cutover |
| `Multiple` | One or more | Canary, blue/green, A/B testing, staged rollback | You decide which revisions stay active and how ingress traffic is distributed |

<!-- diagram-id: revision-mode-comparison -->
```mermaid
flowchart TD
    A[Deploy configuration or image change] --> B{Revision mode}
    B -->|Single| C[Create new revision]
    C --> D[Wait until new revision is ready]
    D --> E[Send production traffic to new revision]
    E --> F[Deprovision prior active revision]
    B -->|Multiple| G[Create new revision]
    G --> H[Keep current revision active]
    H --> I[Choose weights or labels]
    I --> J[Promote or rollback by traffic change]
```

### Single revision mode

Use single revision mode when you want the platform to handle cutover automatically.

- It is the default mode.
- Container Apps provisions and activates the new revision before diverting traffic.
- If an update fails, traffic remains on the old revision.
- You do not manage weighted traffic between old and new revisions.

This mode is usually the safest choice for stateless services that only need straightforward zero-downtime replacement.

### Multiple revision mode

Use multiple revision mode when rollout control matters more than simplicity.

- Multiple revisions can stay active at the same time.
- You can split traffic by revision name, by label, or by routing all traffic to the latest revision.
- Rollback is usually a traffic update, not a redeploy.
- Old revisions remain your responsibility until you deactivate them.

This mode is the right platform primitive for canary and blue/green patterns.

## How activation behaves

Activation behavior is different enough that it should drive your mode choice.

### In single mode

The platform owns the promotion sequence:

1. Create the new revision.
2. Wait for the revision to become ready.
3. Move production traffic.
4. Deprovision the previous revision.

### In multiple mode

The platform creates the revision, but you own promotion decisions:

1. Create the new revision.
2. Keep the prior revision active.
3. Assign labels or weights.
4. Deactivate older revisions when the confidence window ends.

```bash
az containerapp revision set-mode \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --mode multiple
```

## Deployment, rollback, and traffic implications

| Concern | Single mode | Multiple mode |
|---|---|---|
| Deployment promotion | Automatic after readiness | Manual, usually through traffic or label changes |
| Rollback speed | Re-deploy or restore previous configuration | Immediate if a stable revision is still active |
| Weighted traffic split | Not available | Native capability |
| Label-based validation | Not applicable | Native capability |
| Operational overhead | Lower | Higher |

!!! tip "Choose the simplest mode that matches your release strategy"
    If you do not need side-by-side validation or partial production exposure, stay in single revision mode.

!!! warning "Multiple revision mode increases release flexibility and operational responsibility"
    Microsoft Learn documents how to keep several revisions active and split traffic between them, but it also means you must explicitly clean up older revisions and avoid accidental drift.

## Practical guidance

Choose **single** when:

- Production traffic should always go to one revision.
- Release automation should stay simple.
- Your rollback plan does not require pre-warmed side-by-side revisions.

Choose **multiple** when:

- You need a controlled canary window.
- You want blue/green labels for deterministic validation.
- You need instant rollback by moving traffic rather than rebuilding artifacts.

## See Also

- [Revisions Overview](index.md)
- [Traffic Split](traffic-split.md)
- [Revision Lifecycle](lifecycle.md)
- [Revision Strategy Best Practices](../../best-practices/revision-strategy.md)
- [Revision Operations](../../operations/revision-management/index.md)

## Sources

- [Revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions)
- [Manage revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions-manage)
- [Microsoft.App/containerApps template reference (Microsoft Learn)](https://learn.microsoft.com/azure/templates/microsoft.app/2026-01-01/containerapps)
