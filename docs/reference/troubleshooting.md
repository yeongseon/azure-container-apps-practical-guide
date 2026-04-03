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
| Error trend | Use queries in [KQL Queries](kql-queries.md) |

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

## See Also

- [Azure Container Apps troubleshooting (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/troubleshooting)
- [Diagnose and solve problems in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/diagnose-solve-problems)
