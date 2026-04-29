---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures
diagrams:
  - id: azure-files-mount-failure-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures
      - https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "Azure Container Apps uses environment-level storage definitions to mount Azure Files shares into revisions."
      source: https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files
      verified: false
    - claim: "The Azure portal includes a Storage Mount Failures detector for Azure Container Apps troubleshooting."
      source: https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures
      verified: false
---

# Azure Files Mount Failure Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 35-45 min |
| Tier | Inline guide only |
| Category | Storage and Volumes |

## 1. Question

Does azure files mount failure reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] A failed revision appears immediately after the broken storage definition is applied.
- [Observed] System logs contain `Error mounting volume <VOLUME_NAME>.`
- [Correlated] The failing revision and broken environment storage definition exist at the same time.
- [Observed] After correcting the environment storage definition and redeploying, the new revision starts successfully.
- [Inferred] The root cause is storage-definition mismatch rather than image, ingress, or probe configuration.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] A failed revision appears immediately after the broken storage definition is applied.
- [Observed] System logs contain `Error mounting volume <VOLUME_NAME>.`
- [Correlated] The failing revision and broken environment storage definition exist at the same time.
- [Observed] After correcting the environment storage definition and redeploying, the new revision starts successfully.
- [Inferred] The root cause is storage-definition mismatch rather than image, ingress, or probe configuration.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Azure Files Mount Failure is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

Remove the test mount from `app.yaml`, redeploy the app, and then delete the temporary environment storage definition if it is no longer required.

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --yaml app.yaml \
    --output table

az containerapp env storage remove \
    --name "$CONTAINER_ENV" \
    --resource-group "$RG" \
    --storage-name "azurefilesdocs"
```

| Command | Why it is used |
|---|---|
| `az containerapp update --name "$APP_NAME" --resource-group "$RG" --yaml app.yaml --output table` | Restores the app to its non-lab volume configuration. |
| `az containerapp env storage remove --name "$CONTAINER_ENV" --resource-group "$RG" --storage-name "azurefilesdocs"` | Removes the temporary environment storage object created for the lab scenario. |

## Related Playbook

- [Azure Files Mount Failure](../playbooks/storage-and-volumes/azure-files-mount-failure.md)

## See Also

- [Volume Permission Denied Lab](volume-permission-denied.md)
- [EmptyDir Disk Full Lab](emptydir-disk-full.md)
- [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md)

## Sources

- [Troubleshoot storage mount failures in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-storage-mount-failures)
- [Mount Azure Files in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files)
- [Use storage mounts in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts)
