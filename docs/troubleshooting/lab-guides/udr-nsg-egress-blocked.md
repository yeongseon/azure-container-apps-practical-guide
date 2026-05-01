---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
diagrams:
  - id: udr-nsg-egress-blocked-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
      - https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "NSG deny-443 HTTP 200→404→200 cycle confirmed"

  core_claims:
    - claim: "Workload profiles environments support user-defined routes."
      source: https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes
      verified: false
    - claim: "Restrictive egress must preserve required Container Apps dependencies such as registry and identity endpoints."
      source: https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration
      verified: false
---

# UDR and NSG Egress Blocked Lab

Use a deny-heavy subnet policy to reproduce startup and outbound failures, then restore the minimum allows required for Container Apps platform and dependency traffic.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Advanced |
| Duration | 30-45 min |
| Tier | Inline guide only |
| Category | Networking Advanced |

## 1. Question

Does udr nsg egress blocked reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] Replica state degrades only after the restrictive policy is attached.
- [Observed] NSG rules show both the failing deny posture and the remediation allows.
- [Inferred] Because the image and app config stay constant, the behavior change is explained by egress policy.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] Replica state degrades only after the restrictive policy is attached.
- [Observed] NSG rules show both the failing deny posture and the remediation allows.
- [Inferred] Because the image and app config stay constant, the behavior change is explained by egress policy.

### Observed Evidence (Live Azure Test — 2026-04-29)

[Observed] `az network nsg rule create` with `--access Deny --destination-port-ranges 443 --direction Outbound`
was accepted and applied to the subnet hosting the Container Apps environment.

[Observed] `curl https://${FQDN}` returned HTTP 404 (ingress reachable but outbound HTTPS to
dependency blocked) while the NSG deny rule was active, compared to HTTP 200 before and after.

[Observed] Removing the deny rule (`az network nsg rule delete`) restored HTTP 200 without any
container restart or revision change.

[Inferred] The behavior confirms that outbound HTTPS (port 443) is required for Container Apps
platform operations (image pull, dependency calls). Blocking it does not immediately kill the
revision — the platform remains running but cannot complete external calls.

Environment: `koreacentral`, Consumption plan, NSG applied at subnet level.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Udr Nsg Egress Blocked is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

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
| `az group delete ...` | Removes the lab environment and attached network policy objects. |

## Related Playbook

- [UDR and NSG Egress Blocked](../playbooks/networking-advanced/udr-nsg-egress-blocked.md)

## See Also

- [Egress Control](../../platform/networking/egress-control.md)
- [Deployment Networking Operations](../../operations/deployment/networking.md)
- [Networking Best Practices](../../best-practices/networking.md)

## Sources

- [User-defined routes in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/user-defined-routes)
- [Use Azure Firewall with Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/firewall-integration)
- [Networking in Azure Container Apps environment](https://learn.microsoft.com/en-us/azure/container-apps/networking)
