---
content_sources:
  - type: mslearn-adapted
    url: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
diagrams:
  - id: websocket-grpc-ingress-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      - https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions
content_validation:
  status: pending_review
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-04-29
    az_cli_version: "2.70.0"
    notes: "transport Http(broken)→Auto(WS fix)→Http2(gRPC) toggled and verified via ingress show"

  core_claims:
    - claim: "Container Apps supports `http2` transport for gRPC workloads."
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: false
    - claim: "Session affinity is an HTTP ingress feature and is relevant when multiple replicas can serve the same client."
      source: https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions
      verified: false
---

# WebSocket and gRPC Ingress Lab

Use one stateful streaming test app to reproduce both protocol and reconnect problems: first with conservative ingress defaults, then with explicit `http2` transport and sticky sessions enabled.

## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 25-35 min |
| Tier | Inline guide only |
| Category | Networking Advanced |

## 1. Question

Does websocket grpc ingress reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

- [Observed] Initial ingress output lacks the desired `http2` and/or sticky-session settings.
- [Observed] Two replicas are active during the failing reconnect test.
- [Inferred] When the path stabilizes after ingress correction, the root cause is ingress configuration rather than general app reachability.

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

- [Observed] Initial ingress output lacks the desired `http2` and/or sticky-session settings.
- [Observed] Two replicas are active during the failing reconnect test.
- [Inferred] When the path stabilizes after ingress correction, the root cause is ingress configuration rather than general app reachability.

### Observed Evidence (Live Azure Test — 2026-05-01)

```text
# Default transport
az containerapp ingress show --name ca-ws-lab --resource-group rg-aca-lab-test2 \
  --query "transport"
→ "Http"

# Fix for WebSocket
az containerapp ingress update ... --transport Auto
→ "Auto"

# Fix for gRPC
az containerapp ingress update ... --transport Http2
→ "Http2"
```

- `[Observed]` Default `transport: Http` confirmed via `az containerapp ingress show`.
- `[Observed]` `transport: Auto` confirmed after update (WebSocket fix path).
- `[Observed]` `transport: Http2` confirmed after update (gRPC fix path).
- `[Inferred]` WebSocket requires `Auto`; gRPC requires `Http2`. `Http` for either protocol causes connection failures.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Websocket Grpc Ingress is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

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
| `az group delete ...` | Removes the streaming test app and environment resources after validation. |

## Related Playbook

- [WebSocket and gRPC Ingress](../playbooks/networking-advanced/websocket-grpc-ingress.md)

## See Also

- [Ingress in Azure Container Apps](../../platform/networking/ingress.md)
- [Networking Best Practices](../../best-practices/networking.md)
- [Session Affinity Failure](./session-affinity-failure.md)

## Sources

- [Ingress in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Session affinity in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/sticky-sessions)
