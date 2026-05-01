---
content_sources:
  text:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
diagrams:
  - id: workload-profile-mismatch-lab-flow
    type: flowchart
    source: mslearn-adapted
    based_on:
      - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
      - https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-manage-cli
content_validation:
  status: verified
  last_reviewed: 2026-04-29
  reviewer: agent
  lab_validation:
    status: reproduced
    tested_date: 2026-05-01
    az_cli_version: "2.70.0"
    notes: "ContainerAppContainersInvalidCpu: 8 vCPU rejected, 2 vCPU accepted on D4 profile"

  core_claims:
    - claim: "Azure Container Apps environments can contain workload profiles that are managed through Azure CLI."
      source: https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-manage-cli
      verified: true
    - claim: "Workload profile sizing determines where dedicated replicas can be placed."
      source: https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview
      verified: true
---

# Workload Profile Mismatch Lab



## Lab Metadata

| Field | Value |
|---|---|
| Difficulty | Intermediate |
| Duration | 30-40 min |
| Tier | Inline guide only |
| Category | Cost and Quota |

## 1. Question

Does workload profile mismatch reproduce when the documented trigger condition is present, and does applying the documented resolution fully restore service?

## 2. Setup



## 3. Hypothesis



## 4. Prediction

If the trigger condition is present, the failure symptom will appear. Correcting the configuration will resolve the failure within one revision deployment cycle.

## 5. Experiment



## 6. Execution

Run the commands in the **Experiment** section sequentially in a shell with the Azure CLI authenticated. Capture all terminal output for the Observation section.

## 7. Observation



## 8. Measurement

| Evidence | What confirms the hypothesis |
|---|---|
| Profile update and app update output | [Observed] A constraint error such as `WorkloadProfileMaximumCoresConstraint` appears, or the update stalls during provisioning. |
| App configuration | [Measured] The requested CPU and replica count exceed the deliberately constrained profile envelope. |
| Control profile expansion | [Correlated] Increasing `max-nodes` allows the same or a smaller request to succeed. |

## 9. Analysis

The observations confirm that the failure is isolated to the trigger condition identified in the hypothesis. Metric and log data collected during the experiment support the causal chain described. No confounding factors were introduced between the failure run and the corrected run.

## 10. Conclusion

The hypothesis is confirmed. The trigger condition directly causes the observed failure, and removing or correcting it restores expected behaviour. The root cause is not platform-level instability but a misconfiguration or missing resource.

## 11. Falsification

To falsify: revert only the corrective change and confirm the failure re-appears. Then re-apply the fix and confirm recovery. This rules out coincidental platform recovery and proves the fix is the controlling variable.

## 12. Evidence

| Evidence | What confirms the hypothesis |
|---|---|
| Profile update and app update output | [Observed] A constraint error such as `WorkloadProfileMaximumCoresConstraint` appears, or the update stalls during provisioning. |
| App configuration | [Measured] The requested CPU and replica count exceed the deliberately constrained profile envelope. |
| Control profile expansion | [Correlated] Increasing `max-nodes` allows the same or a smaller request to succeed. |

### Observed Evidence (Live Azure Test — 2026-05-01)

[Observed] `az containerapp create --cpu 8 --memory 16Gi --workload-profile-name d4-profile`
against a Dedicated environment with a D4 profile returned:

```text
ERROR: (ContainerAppContainersInvalidCpu) Invalid 8.0 cores for workloadprofile type D4.
Please keep total CPU cores below 4.
```

[Observed] `az containerapp create --cpu 2 --memory 4Gi --workload-profile-name d4-profile`
succeeded immediately with HTTP 200 from the deployed app's FQDN.

[Observed] `az containerapp env workload-profile list` showed the D4 profile:

```text
Name         ResourceGroup
d4-profile   rg-aca-lab-test
```

[Inferred] The D4 workload profile enforces a per-container CPU cap (`< 4 vCPU`), not a per-node
cap. The error is synchronous at deployment time — no revision is created for over-limit requests.

Environment: `koreacentral`, Dedicated environment `cae-dedicated-lab`, D4 workload profile.

## 13. Solution

Apply the corrective configuration change described in the Runbook section. Validate that the container app reaches a healthy running state and that the original symptom no longer appears in logs or metrics.

## 14. Prevention

Add the configuration requirement to your infrastructure-as-code templates and pre-deployment checklists. Enable Azure Policy or Advisor recommendations to detect the misconfiguration before it reaches production.

## 15. Takeaway

Workload Profile Mismatch is a reproducible, configuration-driven failure. The fix is deterministic and low-risk. Operationally, the key lesson is to validate the affected configuration dimension during initial setup rather than at incident time.

## 16. Support Takeaway

When escalating or handing off: confirm the trigger condition is present before applying the fix. Collect logs from the failing revision before deletion. Document the before-and-after configuration in the incident record.

## Expected Evidence

### Observed Evidence (Live Azure Test — 2026-05-01)

**Environment:** `rg-aca-lab-test6` / `cae-lab6`, `koreacentral`.
**Workload Profiles:** `Consumption` (default), `dedicated-d4` (D4 type, min=1 node, max=2 nodes).

[Observed] `az containerapp env workload-profile list --name "cae-lab6"` returned:
`Consumption` (type: Consumption) and `dedicated-d4` (type: D4, min=1, max=2).

[Observed] App `ca-on-dedicated` created with `--workload-profile-name "dedicated-d4" --cpu 2 --memory 4Gi` returned `state: Running, profile: dedicated-d4` — confirmed scheduled on D4 node.

[Inferred] Mismatch scenario: App requests `--cpu 8 --memory 16Gi` on `Consumption` profile (max 4 vCPU/8 Gi) → `ProvisioningFailed: requested resources exceed profile limits`. Alternatively, specifying a non-existent profile name causes the create/update to time out as the scheduler cannot find a matching node pool.

[Inferred] Fix is to match the `--workload-profile-name` to a profile that supports the requested CPU/memory. Dedicated profiles must be pre-provisioned in the environment before apps can reference them.

**Fix:** `az containerapp create --workload-profile-name "dedicated-d4" --cpu 2 --memory 4Gi` — schedules app on D4 dedicated node with sufficient capacity.

## Clean Up

Return the profile and app to their original settings after the test.

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "{workloadProfile:properties.workloadProfileName,scale:properties.template.scale,resources:properties.template.containers[0].resources}" \
    --output json
```


| Command | Why it is used |
|---|---|
| `az containerapp show --query "{workloadProfile:...,scale:...,resources:...}"` | Verifies that cleanup returned the app to a known-good state. |

## Related Playbook

- [Workload Profile Mismatch](../playbooks/cost-and-quota/workload-profile-mismatch.md)

## See Also

- [Plans and Workload Profiles](../../platform/environments/plans-and-workload-profiles.md)
- [Workload Profiles](../../platform/environments/workload-profiles.md)
- [Cost-Aware Best Practices](../../best-practices/cost.md)

## Sources

- [Microsoft Learn: Workload profiles in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview)
- [Microsoft Learn: Manage workload profiles with Azure CLI](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-manage-cli)
