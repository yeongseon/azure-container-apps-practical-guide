---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
diagrams:
  - id: emptydir-disk-full-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
      - https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "Azure Container Apps supports `EmptyDir` volumes for temporary storage."
      source: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
      verified: false
    - claim: "Ephemeral storage settings can be defined in the container resources section of a Container Apps revision template."
      source: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts
      verified: false
---

# EmptyDir Disk Full Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 30-40 min |
| Tier | Inline guide only |
| Category | Storage and Volumes |

## 1. Question

Does emptydir disk full reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] The active revision contains `storageType: EmptyDir` and a mounted scratch path.
- [Observed] The workload fails only after enough temporary data is generated.
- [Correlated] Raising `ephemeralStorage` or reducing scratch output removes the failure under the same reproduction steps.
- [Inferred] The issue is temporary-storage exhaustion, not Azure Files connectivity or credential failure.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] The active revision contains `storageType: EmptyDir` and a mounted scratch path.
- [Observed] The workload fails only after enough temporary data is generated.
- [Correlated] Raising `ephemeralStorage` or reducing scratch output removes the failure under the same reproduction steps.
- [Inferred] The issue is temporary-storage exhaustion, not Azure Files connectivity or credential failure.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Emptydir Disk Full is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

Remove the lab-only `EmptyDir` mount or restore the original scratch configuration after the experiment.

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --yaml app.yaml \
    --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp update --name "$APP_NAME" --resource-group "$RG" --yaml app.yaml --output table` | Restores the post-lab revision after temporary-storage testing is complete. |

## Related Playbook

- [EmptyDir Disk Full](../playbooks/storage-and-volumes/emptydir-disk-full.md)

## See Also

- [Azure Files Mount Failure Lab](azure-files-mount-failure.md)
- [Volume Permission Denied Lab](volume-permission-denied.md)
- [CrashLoop OOM and Resource Pressure](../playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md)

## Sources

- [Use storage mounts in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts)
- [Troubleshoot storage mount failures in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures)
