# Troubleshooting

## Fast Triage Commands

```bash
RG="rg-myapp"
APP_NAME="ca-myapp"

az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState
az containerapp revision list --name "$APP_NAME" --resource-group "$RG"
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --follow
```

Use `APP_NAME="ca-myapp"` for the examples below. Real observed healthy outputs:

```text
$ az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState
"Succeeded"

$ az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
Name               Active    TrafficWeight    Replicas    HealthState    RunningState
-----------------  --------  ---------------  ----------  -------------  ------------
ca-myapp--0000001  True      100              1           Healthy        Running
```

## Common Errors

| Error message / symptom | Likely cause | Fix |
| --- | --- | --- |
| `ImagePullBackOff`, `unauthorized: authentication required` | ACR auth/identity not configured | Grant `AcrPull` to Container App managed identity and verify `--registry-server` |
| `CrashLoopBackOff` | App exits on startup | Check console logs, missing package/env var, verify startup command |
| `ModuleNotFoundError: <module>` | Dependency missing from image | Add package to `requirements.txt`, rebuild image, redeploy |
| `Address already in use` or bind failure | Port mismatch | Ensure container listens on `0.0.0.0:8000` and ACA `--target-port 8000` |
| Health probe failures | Probe path/port invalid or app slow to start | Align probe port/path with app endpoint; increase startup tolerance |
| 502/504 from ingress | No healthy replica, startup timeout, app not listening | Validate revision health, startup logs, and target port |
| URL not reachable | Ingress set to internal | Set `--ingress external` or test from inside VNet/environment |
| Secret value appears unchanged | Secret updates create new revision | Restart/deploy new revision after `az containerapp secret set` |

## Playbook Categories

Use the category that best matches your first confirmed symptom.

### Startup and Provisioning

- [Image Pull Failure](startup-and-provisioning/image-pull-failure.md)
- [Revision Provisioning Failure](startup-and-provisioning/revision-provisioning-failure.md)
- [Container Start Failure](startup-and-provisioning/container-start-failure.md)
- [Probe Failure and Slow Start](startup-and-provisioning/probe-failure-and-slow-start.md)

### Ingress and Networking

- [Ingress Not Reachable](ingress-and-networking/ingress-not-reachable.md)
- [Internal DNS and Private Endpoint Failure](ingress-and-networking/internal-dns-and-private-endpoint-failure.md)
- [Service-to-Service Connectivity Failure](ingress-and-networking/service-to-service-connectivity-failure.md)

### Scaling and Runtime

- [HTTP Scaling Not Triggering](scaling-and-runtime/http-scaling-not-triggering.md)
- [Event Scaler Mismatch](scaling-and-runtime/event-scaler-mismatch.md)
- [CrashLoop OOM and Resource Pressure](scaling-and-runtime/crashloop-oom-and-resource-pressure.md)

### Identity and Configuration

- [Managed Identity Auth Failure](identity-and-configuration/managed-identity-auth-failure.md)
- [Secret and Key Vault Reference Failure](identity-and-configuration/secret-and-key-vault-reference-failure.md)

### Platform Features

- [Dapr Sidecar or Component Failure](platform-features/dapr-sidecar-or-component-failure.md)
- [Container App Job Execution Failure](platform-features/container-app-job-execution-failure.md)
- [Bad Revision Rollout and Rollback](platform-features/bad-revision-rollout-and-rollback.md)

## How to Use This Hub

1. Run the fast triage commands to identify the first concrete failure signal.
2. Open the matching playbook and work through hypotheses and evidence collection.
3. Use [KQL Queries](../kql/index.md) for timeline and correlation.
4. If multiple signals conflict, use the [Detector Map](../methodology/detector-map.md).

## See Also

- [First 10 Minutes: Quick Triage Checklist](../first-10-minutes/index.md)
- [Troubleshooting Methodology](../methodology/index.md)
- [Detector Map](../methodology/detector-map.md)
