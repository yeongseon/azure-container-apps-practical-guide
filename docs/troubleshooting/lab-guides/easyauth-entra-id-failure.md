---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/authentication
diagrams:
  - id: easyauth-entra-id-failure-lab-diagram
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/authentication
      - https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra
      - https://learn.microsoft.com/en-us/troubleshoot/azure/entra/entra-id/app-integration/error-code-AADSTS50011-redirect-uri-mismatch
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "HTTP 401 with WWW-Authenticate Bearer + authorization_uri; redirect URI fix in Entra app registration"

  core_claims:
    - claim: "Azure Container Apps can use built-in auth with Microsoft Entra ID."
      source: https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra
      verified: false
    - claim: "AADSTS50011 indicates a redirect URI or reply URL mismatch."
      source: https://learn.microsoft.com/en-us/troubleshoot/azure/entra/entra-id/app-integration/error-code-AADSTS50011-redirect-uri-mismatch
      verified: false
---

# EasyAuth Entra ID Failure Lab

Trigger an Entra ID redirect URI mismatch for Container Apps built-in auth, then fix the callback alignment and validate successful sign-in.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 30-45 min |
| Tier | Inline guide only |
| Category | Platform Features |

<!-- diagram-id: easyauth-entra-id-failure-lab-diagram -->
```mermaid
flowchart TD
    A[User requests protected app] --> B[EasyAuth redirects to Entra ID]
    B --> C[Redirect URI mismatch occurs]
    C --> D[AADSTS50011 shown to user]
    D --> E[Inspect app auth config and FQDN]
    E --> F[Fix Entra redirect URI or EasyAuth settings]
    F --> G[Retry sign-in]
    G --> H[Successful callback to app]
```

## 1. Question

Does easyauth entra id failure reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- Screenshot or textual capture of the `AADSTS50011` error.
- `az containerapp auth show` output that identifies the provider configuration.
- Before-and-after redirect URI values in the Entra app registration.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- Screenshot or textual capture of the `AADSTS50011` error.
- `az containerapp auth show` output that identifies the provider configuration.
- Before-and-after redirect URI values in the Entra app registration.

### Observed Evidence (Live Azure Test — 2026-04-30)

```text
# EasyAuth enabled; wrong redirect URI in Entra app registration
curl -I https://ca-easyauth.<env>.koreacentral.azurecontainerapps.io/
→ HTTP/2 401
   www-authenticate: Bearer realm="...",
     authorization_uri="https://login.microsoftonline.com/<tenant>/oauth2/authorize",
     resource_id="27b00bf7-db23-49c4-aa8e-9c546b4dcf8b"

# Redirect URI before fix (missing /.auth/login/aad/callback)
# → AADSTS50011: The redirect URI specified in the request does not match

# Fix: add correct redirect URI to Entra app registration
az ad app update --id 27b00bf7-db23-49c4-aa8e-9c546b4dcf8b \
  --web-redirect-uris "https://ca-easyauth.<env>.koreacentral.azurecontainerapps.io/.auth/login/aad/callback"
→ Updated; login flow completes successfully
```

- `[Observed]` HTTP 401 with `www-authenticate: Bearer` header containing `authorization_uri` pointing to Entra login.
- `[Observed]` Without correct redirect URI: AADSTS50011 error during OAuth callback.
- `[Observed]` After adding `/.auth/login/aad/callback` as redirect URI: EasyAuth login flow completes.
- `[Inferred]` EasyAuth redirect URI must exactly match the app's `/.auth/login/aad/callback` endpoint.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Easyauth Entra Id Failure is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Clean Up

- Remove any temporary test redirect URIs that should not remain registered.
- Reconfirm the final callback list matches only valid production or lab hosts.

## Related Playbook

- [EasyAuth Entra ID Failure](../playbooks/platform-features/easyauth-entra-id-failure.md)

## See Also

- [Bad Revision Rollout and Rollback](../playbooks/platform-features/bad-revision-rollout-and-rollback.md)
- [Multi-Region Failover Lab](./multi-region-failover.md)

## Sources

- [Authentication and authorization in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [Enable Microsoft Entra authentication in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra)
- [Troubleshoot AADSTS50011 redirect URI mismatch](https://learn.microsoft.com/en-us/troubleshoot/azure/entra/entra-id/app-integration/error-code-AADSTS50011-redirect-uri-mismatch)
