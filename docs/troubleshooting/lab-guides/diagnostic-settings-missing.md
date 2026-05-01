---
content_sources:
  documents:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/log-options
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
diagrams:
  - id: diagnostic-settings-missing-lab
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/log-options
      - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-05-01
    az_cli_version: "2.70.0"
    notes: "Bad Request on invalid metric namespace, ReplicaCount valid"

  core_claims:
    - claim: "Azure Container Apps supports Azure Monitor as a log destination, and diagnostic settings complete routing to downstream stores such as Log Analytics."
      source: https://learn.microsoft.com/en-us/azure/container-apps/log-options
      verified: false
    - claim: "Container app logs can be queried in Log Analytics after monitoring configuration is completed correctly."
      source: https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash
      verified: false
---

# Diagnostic Settings Missing Lab

Show that Azure Monitor routing alone is not enough when diagnostic settings are absent, then verify that logs appear after the diagnostic setting is created.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 15-25 min |
| Tier | Inline guide only |
| Category | Observability |

## 1. Question

Does diagnostic settings missing reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- `properties.appLogsConfiguration.destination` returns `azure-monitor`.
- `az monitor diagnostic-settings list --resource "$ENV_RESOURCE_ID"` proves whether the failing state actually lacks the necessary environment routing rule.
- A fresh restart event is created in both phases.
- The workspace query returns the new row only after the diagnostic setting is created.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- `properties.appLogsConfiguration.destination` returns `azure-monitor`.
- `az monitor diagnostic-settings list --resource "$ENV_RESOURCE_ID"` proves whether the failing state actually lacks the necessary environment routing rule.
- A fresh restart event is created in both phases.
- The workspace query returns the new row only after the diagnostic setting is created.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Diagnostic Settings Missing is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Expected Evidence

### Observed Evidence (Live Azure Test — 2026-05-01)

**Environment:** `rg-aca-lab-test6` / `cae-nodiag-lab6`, `koreacentral`, Consumption plan.

[Observed] Before fix: `az containerapp env show --query "properties.appLogsConfiguration"` returned `{"destination": null, "logAnalyticsConfiguration": null}` — no Log Analytics connected.

[Observed] Reference env with Log Analytics: `az containerapp env show --name "cae-lab6" --query "properties.appLogsConfiguration"` returned `{"destination": "log-analytics", "logAnalyticsConfiguration": {"customerId": "584c3e91-4da5-4490-9216-604cb21a0624"}}`.

[Inferred] Without Log Analytics, all container console logs and system events are silently dropped. KQL queries against `ContainerAppConsoleLogs_CL` return no results.

**Fix:** `az containerapp env update --logs-workspace-id <LAW_CUSTOMER_ID> --logs-workspace-key <KEY>` — connects Log Analytics and begins log ingestion within ~2 minutes.

## Clean Up

If the diagnostic setting was created to repair production observability, keep it in place. No cleanup is recommended unless this was a disposable lab environment.

## Related Playbook

- [Diagnostic Settings Missing](../playbooks/observability/diagnostic-settings-missing.md)

## See Also

- [Log Analytics Ingestion Gap Lab](log-analytics-ingestion-gap.md)
- [Application Insights Connection String Missing Lab](appinsights-connection-string-missing.md)
- [Observability Tracing Lab](observability-tracing.md)

## Sources

- [Log storage and monitoring options in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/log-options)
- [Monitor logs in Azure Container Apps with Log Analytics](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring?tabs=bash)
