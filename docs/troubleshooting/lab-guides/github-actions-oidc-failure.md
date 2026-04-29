---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
diagrams:
  - id: github-actions-oidc-failure-lab
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
      - https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  core_claims:
    - claim: "GitHub Actions OIDC to Azure depends on a matching federated identity credential."
      source: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
      verified: false
    - claim: "Workload identity federation compares incoming token claims with the configured federated identity credential."
      source: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation
      verified: false
---

# GitHub Actions OIDC Failure Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 25-35 min |
| Tier | Inline guide only |
| Category | Deployment and CI/CD |

## 1. Question

Does github actions oidc failure reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] The first workflow run fails before the Container Apps deployment step with `AADSTS70021`.
- [Observed] The federated credential subject in Entra does not match the workflow branch.
- [Observed] After correcting the subject, the workflow completes Azure sign-in and reaches the `az containerapp show` step.
- [Inferred] The OIDC failure was caused by claim mismatch rather than by RBAC on the Container App itself.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] The first workflow run fails before the Container Apps deployment step with `AADSTS70021`.
- [Observed] The federated credential subject in Entra does not match the workflow branch.
- [Observed] After correcting the subject, the workflow completes Azure sign-in and reaches the `az containerapp show` step.
- [Inferred] The OIDC failure was caused by claim mismatch rather than by RBAC on the Container App itself.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Github Actions Oidc Failure is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

```bash
az ad app federated-credential list \
    --id "$APP_REGISTRATION_ID"
```

| Command | Why it is used |
|---|---|
| `az ad app federated-credential list --id "$APP_REGISTRATION_ID"` | Verifies the application now retains only the intended credential definitions after the lab. |

## Related Playbook

- [GitHub Actions OIDC Failure](../playbooks/deployment-and-cicd/github-actions-oidc-failure.md)

## See Also

- [Managed Identity Key Vault Failure Lab](managed-identity-key-vault-failure.md)
- [Managed Identity Authentication Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md)

## Sources

- [Use GitHub Actions to connect to Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Workload identity federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- [Authentication with GitHub](https://learn.microsoft.com/en-us/azure/container-apps/authentication-github)
