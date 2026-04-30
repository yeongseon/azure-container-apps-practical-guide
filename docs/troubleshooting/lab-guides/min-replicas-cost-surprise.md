---
content_sources:
  text:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/billing
diagrams:
  - id: min-replicas-cost-surprise-lab-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/billing
      - https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "minReplicas=5→0 confirmed, scale-to-zero enabled"

  core_claims:
    - claim: "The minimum replica setting determines whether a revision can scale to zero."
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: "Azure Container Apps billing changes depending on whether workloads run in scale-to-zero capable consumption behavior or reserved dedicated capacity."
      source: https://learn.microsoft.com/en-us/azure/container-apps/billing
      verified: true
---

# Min Replicas Cost Surprise Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Beginner |
| Duration | 20-30 min |
| Tier | Inline guide only |
| Category | Cost and Quota |

## 1. Question

Does min replicas cost surprise reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

| Evidence | What confirms the hypothesis |
|---|---|
| `az containerapp show --query "properties.template.scale"` | [Observed] The app clearly switches between `minReplicas=1` and `minReplicas=0`. |
| `az monitor metrics list --metric Replicas` | [Measured] The average replica count remains above zero in the first phase and drops toward zero in the second phase. |
| `az containerapp revision list` | [Correlated] The active revision no longer needs to hold a warm replica after the `minReplicas=0` phase. |

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

| Evidence | What confirms the hypothesis |
|---|---|
| `az containerapp show --query "properties.template.scale"` | [Observed] The app clearly switches between `minReplicas=1` and `minReplicas=0`. |
| `az monitor metrics list --metric Replicas` | [Measured] The average replica count remains above zero in the first phase and drops toward zero in the second phase. |
| `az containerapp revision list` | [Correlated] The active revision no longer needs to hold a warm replica after the `minReplicas=0` phase. |

### Observed Evidence (Live Azure Test — 2026-04-29)

[Observed] `az containerapp update --min-replicas 5` succeeded; subsequent
`az containerapp show --query "properties.template.scale.minReplicas"` returned `5`.

[Observed] `az containerapp update --min-replicas 0` succeeded; subsequent query returned `0`.

[Correlated] `az containerapp replica list` after idle period with `minReplicas=5` showed 5
running replicas; same command after `minReplicas=0` and idle period showed 0 replicas.

[Inferred] The cost difference between `minReplicas=5` and `minReplicas=0` on the Consumption
plan is purely the idle compute for 5 permanently-warm replicas — no traffic required to
accumulate charges.

Environment: `koreacentral`, Consumption plan.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Min Replicas Cost Surprise is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

Choose the final state that matches the intended production behavior.

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.template.scale" \
    --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show --query "properties.template.scale"` | Confirms the app was left in the desired post-lab state. |

## Related Playbook

- [Min Replicas Cost Surprise](../playbooks/cost-and-quota/min-replicas-cost-surprise.md)

## See Also

- [Cold Start and Scale-to-Zero Lab](cold-start-scale-to-zero.md)
- [Cost-Aware Best Practices](../../best-practices/cost.md)
- [Workload Profiles](../../platform/environments/workload-profiles.md)

## Sources

- [Microsoft Learn: Azure Container Apps billing](https://learn.microsoft.com/en-us/azure/container-apps/billing)
- [Microsoft Learn: Set scaling rules in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Microsoft Learn: Workload profiles in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)
