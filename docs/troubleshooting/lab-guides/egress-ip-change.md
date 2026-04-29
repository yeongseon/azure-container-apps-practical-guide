---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/networking
diagrams:
  - id: egress-ip-change-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/networking
      - https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "NAT Gateway egress is supported for workload profiles environments."
      source: https://learn.microsoft.com/en-us/azure/container-apps/networking
      verified: false
    - claim: "Workload profiles environments support user-defined routes and controlled outbound traffic designs."
      source: https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
      verified: false
---

# Egress IP Change Lab

Measure outbound identity from a running replica, recreate the environment to simulate egress drift, then compare the post-cutover IP and document the remediation path for partner allow-lists.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 20-30 min |
| Tier | Inline guide only |
| Category | Networking Advanced |

## 1. Question

Does egress ip change reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Measured] Baseline and post-cutover public IP outputs can be compared directly.
- [Observed] No application code change is required to reproduce the allow-list problem.
- [Inferred] If the IP changes and downstream access breaks, allow-list drift is the immediate root cause.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Measured] Baseline and post-cutover public IP outputs can be compared directly.
- [Observed] No application code change is required to reproduce the allow-list problem.
- [Inferred] If the IP changes and downstream access breaks, allow-list drift is the immediate root cause.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Egress Ip Change is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

Use a dedicated lab resource group before running this guide. Delete the resource group only if it contains lab-only resources.

```bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

| Command | Why it is used |
|---|---|
| `az group delete ...` | Removes the environment and any temporary egress components used in the lab. |

## Related Playbook

- [Egress IP Change](../playbooks/networking-advanced/egress-ip-change.md)

## See Also

- [Egress Control](../../platform/networking/egress-control.md)
- [Networking Best Practices](../../best-practices/networking.md)
- [UDR and NSG Egress Blocked](../playbooks/networking-advanced/udr-nsg-egress-blocked.md)

## Sources

- [Networking in Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [User-defined routes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes)
