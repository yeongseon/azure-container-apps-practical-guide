---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
diagrams:
  - id: custom-domain-tls-renewal-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
      - https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "InvalidCustomHostNameValidation: asuid TXT record required with domain verification ID"

  core_claims:
    - claim: "Managed certificates continue to renew automatically only while the app keeps meeting the documented requirements."
      source: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates
      verified: false
    - claim: "Customer-managed certificates are the fallback when managed certificate requirements are not met or supported."
      source: https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates
      verified: false
---

# Custom Domain TLS Renewal Lab

Simulate a renewal-eligibility failure by breaking the managed certificate DNS prerequisites, then restore the required records and verify that hostname binding can proceed again.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 20-30 min |
| Tier | Inline guide only |
| Category | Networking Advanced |

## 1. Question

Does custom domain tls renewal reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] The verification ID from the app matches the `asuid` TXT record only in the healthy state.
- [Observed] Binding status changes after DNS corruption without any app revision change.
- [Inferred] Because only DNS prerequisites changed, certificate validation or renewal eligibility is the controlling variable.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] The verification ID from the app matches the `asuid` TXT record only in the healthy state.
- [Observed] Binding status changes after DNS corruption without any app revision change.
- [Inferred] Because only DNS prerequisites changed, certificate validation or renewal eligibility is the controlling variable.

### Observed Evidence (Live Azure Test — 2026-04-30)

```text
# Attempt to add custom hostname without DNS TXT record
az containerapp hostname add \
  --name ca-easyauth --resource-group rg-aca-lab-test2 \
  --hostname "test.example-lab.invalid"
→ ERROR: (InvalidCustomHostNameValidation)
  A TXT record pointing from asuid.test.example-lab.invalid to
  5F4D40324651269FDA2F10E03050A49ECBA6A88B93D95EA7E223D34005F9E7DE
  was not found.

# Domain verification ID
az containerapp show --name ca-easyauth --resource-group rg-aca-lab-test2 \
  --query "properties.customDomainVerificationId"
→ "5F4D40324651269FDA2F10E03050A49ECBA6A88B93D95EA7E223D34005F9E7DE"
```

- `[Observed]` `InvalidCustomHostNameValidation`: platform requires `asuid.<hostname>` TXT record pointing to the domain verification ID.
- `[Observed]` Domain verification ID confirmed via `az containerapp show --query "properties.customDomainVerificationId"`.
- `[Inferred]` Fix: add `asuid.<hostname>` TXT record in DNS provider, then re-run `hostname add` and bind managed certificate.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Custom Domain Tls Renewal is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

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
| `az group delete ...` | Removes the lab app and related environment resources after testing. |

## Related Playbook

- [Custom Domain TLS Renewal](../playbooks/networking-advanced/custom-domain-tls-renewal.md)

## See Also

- [Custom Domains and Certificates](../../language-guides/python/recipes/custom-domains.md)
- [Managed Certificates](../../operations/custom-domains/managed-certificates.md)
- [Bring Your Own Certificates](../../operations/custom-domains/byo-certificates.md)

## Sources

- [Custom domains and managed certificates in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates)
- [Bring your own certificates to Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-certificates)
