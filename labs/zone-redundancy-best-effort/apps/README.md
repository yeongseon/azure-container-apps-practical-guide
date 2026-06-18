# Custom subject-app image (Python Flask + Azure Monitor OpenTelemetry)

Use this image as a drop-in replacement for the default `helloworld` subject app to populate `AppRequests` with app-handled request telemetry for the KQL pack Q5 query and Capture C9 in the [zone-redundancy best-effort lab guide](../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md). It serves a minimal Flask workload and emits structured Azure Monitor telemetry when an Application Insights connection string is injected.

**Scope note**: this image populates telemetry only for requests that reach the Flask process (handled requests plus app-emitted exceptions). Ingress-side 503s returned by ACA during clustered churn never reach Flask and therefore never appear in `AppRequests`. This image is a telemetry plumbing validator — it is **not** a replacement for the lab's H0b verdict, which continues to use `trigger.sh` stdout totals (`LoadEnd.fail / LoadEnd.total`) for client-visible failure detection (including ingress 503s).

## What this image emits

- **AppRequests** — one request telemetry item per HTTP request **that reaches the Flask process**, including `/error` with `ResultCode=500`. Ingress-side 503s returned before the request reaches the app do not appear here.
- **AppDependencies** — none intentionally emitted by this app
- **AppExceptions** — expected exception telemetry from the explicitly recorded `/error` exception path
- **Traces** — structured JSON application logs written to stdout with replica, revision, and request ID fields

## Prerequisites

- Azure CLI
- Azure Container Registry push permission

The documented build path uses `az acr build` (cloud build), so Docker is not required locally. If you prefer to build locally, install Docker as well.

## Build & push

Current pinned dependency versions (all verified to exist on PyPI as of June 2026):

- `flask==3.1.3` (latest stable)
- `gunicorn==23.0.0` (latest stable)
- `azure-monitor-opentelemetry==1.8.8` (latest stable Azure Monitor OpenTelemetry distro)
- `opentelemetry-instrumentation-flask==0.61b0` (pinned to match the instrumentation line that `azure-monitor-opentelemetry==1.8.8` resolves against; the newer standalone `0.62b1` release conflicts with the distro pin)

The build uses `az acr build` (cloud build, no local Docker required) to match the convention used by the lab's audit image in [`../README.md`](../README.md). Run from `labs/zone-redundancy-best-effort/`:

```bash
ACR="<your-acr>.azurecr.io"
az acr build --registry "$(basename "$ACR" .azurecr.io)" \
  --image "zr-lab/app:latest" \
  ./apps
```

## Deploy with this image

```bash
ACR="<your-acr>.azurecr.io"
az deployment group create \
  --resource-group "$RG" \
  --template-file ./infra/main.bicep \
  --parameters ./infra/main.parameters.json \
  --parameters appImage="${ACR}/zr-lab/app:latest" \
  --parameters appAcrName="$(basename "$ACR" .azurecr.io)"
```

`appAcrName` is required when `appImage` points to a private ACR image so the
Bicep grants the subject apps `AcrPull` and emits the `registries` block.
Without it, the subject-app revisions cannot authenticate to the registry and
the first image pull fails with `401 Unauthorized`. The Bicep looks up the
ACR as an `existing` resource in the same resource group, so the ACR must
live in `$RG` (or you must adapt the Bicep to scope to a different RG).

## Environment variable contract

| Variable | Purpose | Required |
| --- | --- | --- |
| APPLICATIONINSIGHTS_CONNECTION_STRING | Routes telemetry to App Insights | No (graceful degrade) |
| CONTAINER_APP_NAME | Sets AppRoleName for KQL grouping | Auto-injected by ACA |
| CONTAINER_APP_REVISION | Logged with each request | Auto-injected by ACA |

## Verify telemetry arrival

```kusto
AppRequests
| where AppRoleName startswith "app-min"
| take 10
```

## Routes

| Route | Purpose | Expected status |
| --- | --- | --- |
| `/` | Returns app status, replica hostname, and revision | `200` |
| `/health` | Readiness and liveness endpoint | `200` |
| `/load?ms=N` | Busy-waits for `N` milliseconds (default `100`, max `5000`) | `200` |
| `/error` | Returns an intentional error payload for Q5 validation | `500` |

## See Also

- [`../infra/main.bicep`](../infra/main.bicep)
- [`../../../docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md`](../../../docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)
- [`../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md`](../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md)

## Sources

- [Enable Azure Monitor OpenTelemetry for Python applications](https://learn.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable?tabs=python)
- [Azure Monitor OpenTelemetry Python package overview](https://learn.microsoft.com/en-us/python/api/overview/azure/monitor-opentelemetry-readme)
- [Manage environment variables in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/environment-variables)
- [Container settings in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/containers#configuration)
- [Workspace-based Application Insights resources](https://learn.microsoft.com/en-us/azure/azure-monitor/app/create-workspace-resource)
