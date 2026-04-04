# Troubleshooting

## Fast Triage Commands

```bash
RG="rg-myapp"
APP_NAME="my-python-app"

az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState
az containerapp revision list --name "$APP_NAME" --resource-group "$RG"
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --follow
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

## Checks by Failure Type

### 1) Revision fails to provision

```bash
az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[].{name:name,active:properties.active,health:properties.healthState,created:properties.createdTime}"

az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system
```

### 2) App starts but crashes

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type console --follow
```

Look for Python traceback, missing modules, and env-var parsing errors.

### 3) App running but unreachable

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress"
```

Verify:
- `external: true` for public access
- `targetPort: 8000` for this reference app

### 4) Performance / timeout issues

| Check | Command |
| --- | --- |
| Scale boundaries | `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale"` |
| Traffic/load test | `curl https://<fqdn>/api/requests/log-levels` |
| Error trend | Use queries in [KQL Queries](../kql/index.md) |

## Exec for In-Container Validation

```bash
az containerapp exec \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --command "/bin/bash"

# Inside container
python --version
env | sort
```

## Decision Path

| First signal | Next step |
| --- | --- |
| Revision health = Failed | System logs -> image/probe/startup checks |
| Health = Healthy, still errors | Console logs -> app exception analysis |
| Works locally, fails in ACA | Compare env vars/secrets/port/start command |
| Intermittent latency | Check scale settings and request/error trend |

## References
- [Azure Container Apps troubleshooting (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/troubleshooting)
- [Diagnose and solve problems in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/diagnose-solve-problems)

## Image Pull Failure

### Symptoms

- Revision stays in failed state and replicas never become healthy.
- System logs include `ImagePullBackOff`, `manifest unknown`, `unauthorized`, or `denied`.

### Root Cause

- Image tag does not exist.
- ACR authentication is invalid (missing identity or missing role assignment).
- Private registry connectivity blocked by firewall/network configuration.

### Diagnosis Steps

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].image" --output tsv
az acr repository show-tags --name "$ACR_NAME" --repository "$APP_NAME" --output table
```

```kql
let AppName = "ca-myapp-api";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("pull", "manifest", "unauthorized", "denied")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

### Resolution

1. Correct image path/tag and redeploy.
2. Ensure managed identity is assigned and has `AcrPull` on ACR scope.
3. If ACR is private, validate DNS/private endpoint/NSG path from the environment.

### Prevention

- Use immutable tags per deployment (for example, build SHA).
- Add CI validation for image existence before deployment.
- Keep registry auth path documented with least-privilege RBAC.

## Revision Provisioning Failure

### Symptoms

- New revision never becomes active.
- `healthState` is `Failed` immediately after deployment.

### Root Cause

- Invalid template configuration (env vars, secrets, resource requests/limits).
- Referenced secret does not exist.
- Unsupported combination of ingress/probe/container settings.

### Diagnosis Steps

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template" --output json
```

### Resolution

1. Fix invalid settings (resource limits, probe path/port, container command).
2. Recreate missing secrets and ensure `secretRef` names match exactly.
3. Deploy a new revision and verify provisioning and health state.

### Prevention

- Validate templates in CI before apply.
- Keep a baseline known-good revision for fast rollback.

## Container Start Failure

### Symptoms

- Replica restarts repeatedly.
- Console logs show traceback, bind errors, or startup timeout.

### Root Cause

- App crash at startup (dependency import, bad config parsing).
- Port mismatch between app listener and ingress target.
- Dependency calls at startup fail or take too long.

### Diagnosis Steps

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --follow
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.targetPort" --output tsv
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].probes" --output json
```

### Resolution

1. Fix startup exception and rebuild image.
2. Align app bind port and ingress target port.
3. Increase startup probe tolerance for slow initialization.

### Prevention

- Add startup integration checks in CI.
- Keep `/health` lightweight and dependency-safe.

## Ingress Not Reachable

### Symptoms

- Public URL returns timeout, 502, or cannot resolve.
- App appears healthy internally but not externally accessible.

### Root Cause

- Ingress disabled or configured as internal-only.
- Target port mismatch or no healthy backend replicas.
- DNS propagation delay or perimeter firewall restrictions.

### Diagnosis Steps

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress" --output json
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,health:properties.healthState,active:properties.active}" --output table
```

### Resolution

1. Set ingress mode to match intended exposure.
2. Correct target port to app listening port.
3. Verify DNS resolution and network path from caller.

### Prevention

- Include ingress checks in post-deploy smoke tests.
- Track expected FQDN and access type in runbooks.

## Internal DNS Failure

### Symptoms

- Service-to-service calls fail with hostname resolution errors.
- Dependency hostname cannot resolve from container runtime.

### Root Cause

- Environment DNS or VNet DNS forwarding misconfiguration.
- Missing private DNS zone links for private endpoints.
- NSG/UDR blocks DNS egress path.

### Diagnosis Steps

```bash
az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RG" --query "properties.vnetConfiguration" --output json
az network private-dns link vnet list --resource-group "$RG" --zone-name "privatelink.azurecr.io" --output table
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "python -c 'import socket; print(socket.gethostbyname(\"myregistry.azurecr.io\"))'"
```

### Resolution

1. Add/repair private DNS zone links for required services.
2. Ensure DNS forwarders route Azure private zones correctly.
3. Allow DNS traffic in NSG and route tables.

### Prevention

- Keep a documented DNS dependency map per environment.
- Add synthetic DNS checks to operational health probes.

## Managed Identity Auth Failure

### Symptoms

- Calls to Azure resources fail with 401/403.
- Logs show token acquisition or authorization errors.

### Root Cause

- Managed identity not assigned to Container App.
- RBAC missing or scoped incorrectly.
- Token request uses wrong audience/scope for target service.

### Diagnosis Steps

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json
az role assignment list --assignee "$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query identity.principalId --output tsv)" --output table
```

```kql
let AppName = "ca-myapp-api";
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("ManagedIdentityCredential", "token", "403", "401")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

### Resolution

1. Assign system- or user-managed identity.
2. Grant required role at correct resource scope.
3. Request token for correct audience and retest.

### Prevention

- Use IaC to define identity and RBAC consistently.
- Include permission verification in deployment checks.

## Scaling Unexpected Behavior

### Symptoms

- Replicas never scale up under load, or remain over-provisioned.
- Scale-to-zero happens slower than expected.

### Root Cause

- Min/max replica bounds conflict with expected scaling.
- KEDA rule metric/threshold is misconfigured.
- Trigger source emits metrics slower than expected.

### Diagnosis Steps

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.scale" --output json
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --output table
```

```kql
let AppName = "ca-myapp-api";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where Log_s has_any ("scale", "keda", "replica")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
```

### Resolution

1. Correct min/max boundaries.
2. Align trigger metadata (metric name, threshold, polling interval) with workload behavior.
3. Re-run load test and observe replica transitions.

### Prevention

- Validate scale rules with controlled load before production rollout.
- Keep separate baseline rules for HTTP and queue/event workloads.

## Job Execution Failure

### Symptoms

- Container Apps Job does not start, times out, or exhausts retries.
- Job executions show failed status without expected output.

### Root Cause

- Trigger metadata incorrect for schedule/event/manual model.
- Execution timeout lower than actual job runtime.
- Missing secrets/environment variables required by job logic.

### Diagnosis Steps

```bash
az containerapp job execution list --name "$APP_NAME" --resource-group "$RG" --output table
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console
```

### Resolution

1. Correct trigger configuration and retry policy.
2. Increase timeout for known long-running tasks.
3. Restore missing secrets/env vars and re-run execution.

### Prevention

- Add pre-flight validation for job trigger inputs and secret references.
- Use idempotent job design to tolerate retries safely.
