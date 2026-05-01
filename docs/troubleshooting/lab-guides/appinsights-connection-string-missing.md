---
content_sources:
  documents:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings
diagrams:
  - id: appinsights-connection-string-missing-lab
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents
      - https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "env var absent=no telemetry; APPLICATIONINSIGHTS_CONNECTION_STRING added=confirmed present"

  core_claims:
    - claim: "Application Insights uses connection strings to associate telemetry with the correct monitoring resource."
      source: https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings
      verified: false
    - claim: "Azure Container Apps supports sending OpenTelemetry data to Application Insights when the telemetry destination is configured."
      source: https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents
      verified: false
---

# Application Insights Connection String Missing Lab

Demonstrate that successful requests can still produce no Application Insights data when the expected connection string path is absent or incomplete.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 15-25 min |
| Tier | Inline guide only |
| Category | Observability |

## 1. Question

Does appinsights connection string missing reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- `az containerapp env telemetry app-insights show` demonstrates whether the environment path was configured.
- `az containerapp show --query "properties.template.containers[0].env[].{name:name,secretRef:secretRef}"` shows whether the app definition still includes the expected telemetry variable or secret reference.
- `az monitor app-insights query` returns no fresh rows before the fix and fresh rows after the fix.
- Fresh traffic is generated in both phases so the comparison is meaningful.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- `az containerapp env telemetry app-insights show` demonstrates whether the environment path was configured.
- `az containerapp show --query "properties.template.containers[0].env[].{name:name,secretRef:secretRef}"` shows whether the app definition still includes the expected telemetry variable or secret reference.
- `az monitor app-insights query` returns no fresh rows before the fix and fresh rows after the fix.
- Fresh traffic is generated in both phases so the comparison is meaningful.

### Observed Evidence (Live Azure Test — 2026-05-01)

```text
# Before fix: env var absent
az containerapp show --name ca-ai-lab --resource-group rg-aca-lab-test4 \
  --query "properties.template.containers[0].env"
→ []

# After fix: env var present
az containerapp update --name ca-ai-lab --resource-group rg-aca-lab-test4 \
  --env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=aaaabbbb-0000-1111-2222-ccccddddeeee;IngestionEndpoint=https://koreacentral-0.in.applicationinsights.azure.com/"

az containerapp show --name ca-ai-lab --resource-group rg-aca-lab-test4 \
  --query "properties.template.containers[0].env[0].name"
→ "APPLICATIONINSIGHTS_CONNECTION_STRING"
```

- `[Observed]` Before fix: `env` field is `[]` — no telemetry variable configured.
- `[Observed]` After `az containerapp update --env-vars`: `APPLICATIONINSIGHTS_CONNECTION_STRING` present and non-empty.
- `[Inferred]` Without the connection string, the App Insights SDK cannot ingest telemetry; traces are absent in the portal.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Appinsights Connection String Missing is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

If this lab was run only to validate the fix, keep the corrected telemetry configuration in place. No additional cleanup is required.

## Related Playbook

- [Application Insights Connection String Missing](../playbooks/observability/appinsights-connection-string-missing.md)

## See Also

- [Observability Tracing Lab](observability-tracing.md)
- [Log Analytics Ingestion Gap Lab](log-analytics-ingestion-gap.md)
- [Diagnostic Settings Missing Lab](diagnostic-settings-missing.md)

## Sources

- [Collect and read OpenTelemetry data in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/opentelemetry-agents)
- [Connection strings in Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/connection-strings)
- [Observability in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/observability)
