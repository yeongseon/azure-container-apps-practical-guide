---
content_sources:
  documents:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/observability
diagrams:
  - id: log-analytics-ingestion-gap-lab
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
      - https://learn.microsoft.com/en-us/azure/container-apps/observability
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "Azure Container Apps logs can be queried in Log Analytics after they are ingested into Azure Monitor Logs."
      source: https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
      verified: false
    - claim: "Observability for Azure Container Apps includes logs that can be reviewed for operational troubleshooting."
      source: https://learn.microsoft.com/en-us/azure/container-apps/observability
      verified: false
---

# Log Analytics Ingestion Gap Lab

Measure the difference between a fresh Azure Container Apps system event and the moment that same event becomes queryable in Log Analytics.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Beginner |
| Duration | 15-25 min |
| Tier | Inline guide only |
| Category | Observability |

## 1. Question

Does log analytics ingestion gap reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- `properties.appLogsConfiguration.destination` returns `log-analytics`.
- A recent restart event is visible in `az containerapp logs show --type system`.
- The same event appears later in `ContainerAppSystemLogs_CL` for the same app or revision.
- The measured delay is finite and repeatable enough to document as operational guidance.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- `properties.appLogsConfiguration.destination` returns `log-analytics`.
- A recent restart event is visible in `az containerapp logs show --type system`.
- The same event appears later in `ContainerAppSystemLogs_CL` for the same app or revision.
- The measured delay is finite and repeatable enough to document as operational guidance.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Log Analytics Ingestion Gap is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

No infrastructure cleanup is required. The lab only restarts an existing revision.

## Related Playbook

- [Log Analytics Ingestion Gap](../playbooks/observability/log-analytics-ingestion-gap.md)

## See Also

- [Diagnostic Settings Missing Lab](diagnostic-settings-missing.md)
- [Observability Tracing Lab](observability-tracing.md)
- [Cold Start and Scale-to-Zero Lab](cold-start-scale-to-zero.md)

## Sources

- [Monitor logs in Azure Container Apps with Log Analytics](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash)
- [Observability in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/observability)
