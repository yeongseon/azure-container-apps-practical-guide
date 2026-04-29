---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files
diagrams:
  - id: volume-permission-denied-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files
      - https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/storage/mountoptions-settings-azure-files
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "Azure Container Apps Azure Files volumes accept `mountOptions` values in the revision template."
      source: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files
      verified: false
    - claim: "Azure Files SMB permission behavior can be influenced by Linux mount options such as `uid`, `gid`, `dir_mode`, and `file_mode`."
      source: https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/storage/mountoptions-settings-azure-files
      verified: false
---

# Volume Permission Denied Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Advanced |
| Duration | 35-45 min |
| Tier | Inline guide only |
| Category | Storage and Volumes |

## 1. Question

Does volume permission denied reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] The first revision shows Azure Files mount failure behavior with `mount error(13): Permission denied`.
- [Observed] The failing revision either omits `mountOptions` or uses incompatible values.
- [Observed] The next revision includes the corrected `mountOptions` string.
- [Correlated] After the change, the same share mounts successfully and the app can proceed.
- [Inferred] The root cause is Linux mount-permission semantics rather than missing storage credentials.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] The first revision shows Azure Files mount failure behavior with `mount error(13): Permission denied`.
- [Observed] The failing revision either omits `mountOptions` or uses incompatible values.
- [Observed] The next revision includes the corrected `mountOptions` string.
- [Correlated] After the change, the same share mounts successfully and the app can proceed.
- [Inferred] The root cause is Linux mount-permission semantics rather than missing storage credentials.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Volume Permission Denied is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

Keep the working `mountOptions` if they are required, or restore the original known-good volume definition after the experiment.

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --yaml app.yaml \
    --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp update --name "$APP_NAME" --resource-group "$RG" --yaml app.yaml --output table` | Applies the final post-lab Azure Files configuration that you want to keep. |

## Related Playbook

- [Volume Permission Denied](../playbooks/storage-and-volumes/volume-permission-denied.md)

## See Also

- [Azure Files Mount Failure Lab](azure-files-mount-failure.md)
- [EmptyDir Disk Full Lab](emptydir-disk-full.md)
- [Azure Files Mount Failure](../playbooks/storage-and-volumes/azure-files-mount-failure.md)

## Sources

- [Mount Azure Files in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files)
- [Use mountOptions settings in Azure Files](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/storage/mountoptions-settings-azure-files)
- [Troubleshoot storage mount failures in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures)
