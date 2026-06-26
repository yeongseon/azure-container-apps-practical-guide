---
content_sources:
  diagrams:
    - id: architecture
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/dapr-components
validation:
  az_cli:
    last_tested: '2026-06-26'
    cli_version: '2.71.0'
    result: pass
  bicep:
    last_tested: '2026-06-26'
    result: pass
---
# Dapr Integration Troubleshooting Lab

Diagnose and fix Dapr sidecar port misconfiguration issues in Azure Container Apps.

## Lab Metadata

| Attribute | Value |
|---|---|
| Difficulty | Intermediate |
| Estimated Duration | 25-35 minutes |
| Tier | Consumption |
| Failure Mode | Dapr sidecar cannot communicate with the app because `appPort` is misconfigured |
| Skills Practiced | Dapr configuration review, sidecar diagnostics, port alignment validation |

## 1) Background

This lab starts with a working Dapr configuration: Dapr is enabled, `appId` is set, and `appPort` matches the application listening port. The trigger changes Dapr `appPort` from 8000 to 8081, so the sidecar keeps running but can no longer forward service invocation traffic to the application process.

The key troubleshooting lesson is that ingress `targetPort` and Dapr `appPort` are separate settings. An app can still be reachable through ingress while Dapr-to-app communication is broken.

### Architecture

<!-- diagram-id: architecture -->
```mermaid
flowchart TD
    A[External Request] --> B[Ingress :8000]
    B --> C[App Container :8000]
    D[Dapr Sidecar :3500] --> E[App Container :appPort]
    F[Other Dapr Apps] --> D
    E -. correct .-> C
    D -. wrong appPort 8081 .-> G[Connection failure]
```

### Dapr App Port Configuration

| Setting | Description | Impact if Wrong |
|---|---|---|
| `appPort` | Port the Dapr sidecar uses to call the app | Service invocation fails |
| `appId` | Unique identifier for Dapr service discovery | Other apps cannot find this service |
| `appProtocol` | HTTP or gRPC | Protocol mismatch errors |

## 2) Hypothesis

**IF** Dapr is enabled but `appPort` is changed from the app's real listening port 8000 to 8081, **THEN** Dapr sidecar health and service invocation checks will fail even though the app configuration still shows Dapr enabled.

| Variable | Control State | Experimental State |
|---|---|---|
| Dapr `appPort` | 8000 | 8081 |
| Dapr sidecar to app communication | Succeeds | Connection refused or unreachable |
| `verify.sh` result | PASS | FAIL |
| Ingress behavior | Can still target the app separately | May still differ from Dapr failure mode |

!!! info "Scope status — Flask-on-8000 cohort is now `[Observed]`"
    The Phase B evidence pack replaces the old bundled `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` workload with a Flask + Gunicorn image that really binds `0.0.0.0:8000`.

    The live `2026-06-26` cohort now proves all three mechanically relevant surfaces with committed evidence:

    - `[Observed]` `03-dapr-config-pre-fix.json` shows `enabled: true` with `appPort: 8081` while ingress `targetPort` remains `8000` in `01-app-spec-pre-fix.json`.
    - `[Observed]` `04-http-response-pre-fix.json` still returns `HTTP 200` with body `OK`, so ingress reachability remains intact during the Dapr misconfiguration.
    - `[Observed]` `05-dapr-invoke-pre-fix.json` captures a failing loopback Dapr invocation path, and `09-dapr-config-post-fix.json` + `10-http-response-post-fix.json` show the restored `appPort: 8000` and post-fix `HTTP 200` state.

!!! warning "Historical limitation preserved — helloworld image, `2026-06-03`"
    The six Portal captures from `2026-06-03` are kept as additive historical evidence only. That older reproduction used `containerapps-helloworld:latest`, which listens on port 80, so the sidecar-to-app half of the hypothesis remained `[Not Proven]` in that historical cohort.

## 3) Runbook

### Deploy baseline infrastructure

Prerequisites:

- Azure CLI with the Container Apps extension
- Basic understanding of Dapr concepts such as sidecars, `appId`, and `appPort`

```bash
az extension add --name containerapp --upgrade
az login

export RG="rg-aca-lab-dapr"
export LOCATION="koreacentral"

az group create --name "$RG" --location "$LOCATION"

az deployment group create \
    --name "lab-dapr" \
    --resource-group "$RG" \
    --template-file "./labs/dapr-integration/infra/main.bicep" \
    --parameters baseName="labdapr"
```

| Command | Why it is used |
|---|---|
| `az extension add ...` | Installs or updates the Container Apps Azure CLI extension. |

Expected output:

- Resource group creation succeeds.
- Deployment completes successfully with Dapr enabled on the app.

### Capture deployment outputs

```bash
export APP_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-dapr" \
    --query "properties.outputs.containerAppName.value" \
    --output tsv)"

export ENVIRONMENT_NAME="$(az deployment group show \
    --resource-group "$RG" \
    --name "lab-dapr" \
    --query "properties.outputs.containerAppsEnvironmentName.value" \
    --output tsv)"
```

Expected output:

- Commands return no console output.
- Variables resolve to the app and environment names.

### Verify baseline Dapr configuration

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.configuration.dapr" \
    --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show ...` | Reads the Container App configuration so the documented setting can be verified. |

Expected output:

```json
{
  "appId": "dapr-labdapr-xxxxxx",
  "appPort": 8000,
  "appProtocol": "http",
  "enabled": true
}
```

### Trigger the failure

```bash
./labs/dapr-integration/trigger.sh
```

The trigger uses:

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --dapr-app-port 8081
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

!!! warning "CLI 2.71.0 workaround"
    On Azure CLI 2.71.0 the bundled `containerapp` extension rejects `--dapr-app-port` on `az containerapp update` with `unrecognized arguments`. Use the dedicated `az containerapp dapr enable` command, which accepts `--dapr-app-port` directly on this CLI version:

    ```bash
    az containerapp dapr enable \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --dapr-app-port 8081
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp dapr enable ...` | Enables (or re-applies) Dapr on the app while updating `appPort` in the same call. Works on CLI 2.71.0 where `az containerapp update --dapr-app-port` fails. |

Expected output:

- The trigger applies the new Dapr `appPort` value to the Container App.
- The active revision's Dapr `appPort` changes from 8000 to 8081 on the next configuration read.

### Observe the broken state

```bash
az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --query "properties.configuration.dapr" \
    --output json

az containerapp logs show \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --type system \
    --tail 50
```

| Command | Why it is used |
|---|---|
| `az containerapp show ...` | Reads the Container App configuration so the documented setting can be verified. |

Expected output:

```json
{
  "appId": "dapr-labdapr-xxxxxx",
  "appPort": 8081,
  "appProtocol": "http",
  "enabled": true
}
```

Look for errors such as `connection refused`, `port unreachable`, or health probe failures on port 8081.

### Verify failure and fix the configuration

```bash
./labs/dapr-integration/verify.sh
```

Before the fix, the verification script should fail with output like:

```text
FAIL: Dapr appPort is '8081'; expected 8000
```

Restore the correct port:

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --dapr-app-port 8000
```

| Command | Why it is used |
|---|---|
| `az containerapp update ...` | Updates the existing Container App configuration without recreating the app. |

!!! warning "CLI 2.71.0 workaround (restore direction)"
    On Azure CLI 2.71.0 the bundled `containerapp` extension rejects `--dapr-app-port` on `az containerapp update` in both the trigger and restore directions. Use `az containerapp dapr enable --dapr-app-port 8000` for the restore on this CLI version:

    ```bash
    az containerapp dapr enable \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --dapr-app-port 8000
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp dapr enable ...` | Re-applies Dapr on the app with `appPort` set back to 8000 in the same call. Works on CLI 2.71.0 where `az containerapp update --dapr-app-port` fails. |

Useful debugging commands:

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.dapr"
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress.targetPort"
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 100
az containerapp env dapr-component list --name "$ENVIRONMENT_NAME" --resource-group "$RG" --output table
```

Expected output:

- `appPort` returns to 8000.
- In the committed Flask-on-8000 evidence pack, restoring `appPort` to 8000 returns the Dapr config to the real listener and the post-fix capture window remains `Healthy / Running` with ingress `HTTP 200`.

### Verify recovery

```bash
./labs/dapr-integration/verify.sh
```

Expected output (the committed Phase B Flask-on-8000 cohort):

- The script emits all 17 gate verdicts and exits `0`.
- Gate 15 proves `appPort: 8081` plus failing Dapr invoke while ingress still returns `HTTP 200`.
- Gate 16 proves the restored `appPort: 8000` plus post-fix `HTTP 200` and healthy/running capture window.

!!! note "Historical limitation retained honestly"
    The old `2026-06-03` helloworld cohort is still valuable because it preserves the original Portal-only evidence trail, but only the new Flask-on-8000 cohort is used for the bounded-falsification claim.

## 4) Experiment Log

| Step | Action | Expected | Actual | Pass/Fail |
|---|---|---|---|---|
| 1 | Deploy baseline infrastructure | Dapr-enabled app deploys successfully | | |
| 2 | Check Dapr configuration | `appPort` is 8000 and Dapr is enabled | | |
| 3 | Run `trigger.sh` | `appPort` changes to 8081 | | |
| 4 | Review Dapr config and logs | Port mismatch evidence appears | | |
| 5 | Run `verify.sh` before fix | Script fails because `appPort` is wrong | | |
| 6 | Restore `--dapr-app-port 8000` | Update succeeds | | |
| 7 | Run `verify.sh` after fix | Script passes with 17/17 gates in the Flask-on-8000 cohort | | |

## Expected Evidence

### Before trigger

| Evidence Source | Expected State |
|---|---|
| `az containerapp show --query "properties.configuration.dapr"` | `appPort: 8000`, `enabled: true` |
| System logs | No Dapr connection errors |
| `./labs/dapr-integration/verify.sh` | PASS |

### During incident

| Evidence Source | Expected State |
|---|---|
| Dapr config | `appPort: 8081` |
| System logs | Health probe failure / Dapr-sidecar failure evidence while ingress still works |
| `./labs/dapr-integration/verify.sh` | FAIL |

### After fix

| Evidence Source | Expected State |
|---|---|
| Dapr config | `appPort: 8000`, `enabled: true` |
| Post-fix capture window | `appPort: 8000`, `enabled: true`, ingress `/` returns `HTTP 200`, revision surface is `Healthy / Running` |
| `./labs/dapr-integration/verify.sh` | PASS (17/17 gates) |

### Observed Evidence (Live Azure Reproduction — Flask-on-8000, 2026-06-26)

Resource group `rg-aca-lab-dapr` in `koreacentral`, Container App `ca-labdapr-5nichn`, Dapr `appId: dapr-labdapr-5nichn`, single-revision mode, Azure CLI `2.71.0`, ACR image `acrlabdapr5nichn.azurecr.io/ca-labdapr-5nichn:v1`.

- `[Observed]` `01-app-spec-pre-fix.json` records ingress `targetPort: 8000` while `03-dapr-config-pre-fix.json` records `enabled: true`, `appProtocol: http`, and `appPort: 8081`.
- `[Observed]` `04-http-response-pre-fix.json` shows `HTTP/2 200`, `server: gunicorn`, and body `OK`, so ingress remained reachable while the Dapr setting was wrong.
- `[Observed]` `05-dapr-invoke-pre-fix.json` captures the failing loopback Dapr invoke attempt through `127.0.0.1:3500`; the captured exec transcript includes `ClusterExecFailure` with container-side code `500`.
- `[Observed]` `06-system-logs-pre-fix.json` shows repeated `ProbeFailed` rows on the triggered `appPort: 8081` window.
- `[Observed]` `09-dapr-config-post-fix.json` restores `appPort: 8000` with `enabled: true`, and `10-http-response-post-fix.json` again records `HTTP/2 200` with body `OK` at a later timestamp.
- `[Observed]` `11-revision-list-post-fix.json` records the post-fix capture window as `active: true`, `healthState: Healthy`, and `runningState: Running`.
- `[Measured]` `15-h1-trigger-produces-failure-gate.json`, `16-h2-fix-restores-recovery-gate.json`, and `17-bounded-falsification-gate.json` all pass in the committed offline verifier.

### Historical reproduction (helloworld image, 2026-06-03)

Resource group `rg-aca-lab-dapr` in `koreacentral`, Container App `ca-labdapr-bh2uom`, Dapr `appId: dapr-labdapr-bh2uom`, active revision `ca-labdapr-bh2uom--xafdl2m`, single-revision mode. Azure CLI 2.71.0 with `containerapp` extension; the `az containerapp update --dapr-app-port` form rejected the flag in both the trigger and restore directions, so both mutations were applied with `az containerapp dapr enable --dapr-app-port <PORT>` (see CLI 2.71.0 workaround above).

The six PNGs below were captured in sequence during the reproduction. Each paragraph below describes only what is visible inside that single PNG, with no cross-capture comparison.

**[Observed]** Container App **Overview** blade. The **Essentials** panel shows `Status: Running`, `Location: Korea Central`, `Environment type: Workload profiles`, `Resource group: rg-aca-lab-dapr`, and a populated `Application Url` field. Dapr configuration is not surfaced on the Overview panel.

![Container App Overview blade — Status Running, Korea Central, Workload profiles environment](../../assets/troubleshooting/dapr-integration/01-overview.png)

**[Observed]** Container App **Dapr** blade. The `Dapr` radio shows `Enabled`, the `App ID` field shows `dapr-labdapr-bh2uom`, the `App port` field shows `8000`, and the `App protocol` radio shows `HTTP`.

![Dapr blade — Enabled, App ID dapr-labdapr-bh2uom, App port 8000, HTTP](../../assets/troubleshooting/dapr-integration/02-dapr-baseline-appport-8000.png)

**[Observed]** Container App **Dapr** blade. The `Dapr` radio shows `Enabled`, the `App ID` field shows `dapr-labdapr-bh2uom`, the `App port` field shows `8081`, and the `App protocol` radio shows `HTTP`.

![Dapr blade — App port 8081](../../assets/troubleshooting/dapr-integration/03-dapr-after-trigger-appport-8081.png)

**[Observed]** Container App **Revisions** blade. A row for `ca-labdapr-bh2uom--xafdl2m` shows `Date created: 6/3/2026 3:46:22 PM`, `Running status: Degraded`, `Traffic: 100%`, and `Replicas: 2`.

![Revisions blade — ca-labdapr-bh2uom--xafdl2m Running status Degraded, Traffic 100%, Replicas 2](../../assets/troubleshooting/dapr-integration/04-revisions-degraded.png)

**[Observed]** Container App **Containers** blade, **Properties** tab for the container named `app`. The fields show `Registry login server: mcr.microsoft.com`, `Image and tag: azuredocs/containerapps-helloworld:latest`, `CPU cores: 0.5`, and `Memory (Gi): 1`. Health-probe ports are not surfaced on this tab; they are on the separate **Health probes** tab and were not captured.

![Containers blade Properties tab — mcr.microsoft.com/azuredocs/containerapps-helloworld:latest, 0.5 CPU, 1 Gi](../../assets/troubleshooting/dapr-integration/05-containers-helloworld-image.png)

**[Observed]** Container App **Revisions** blade. A row for `ca-labdapr-bh2uom--xafdl2m` shows `Running status: Degraded` and `Traffic: 100%`.

![Revisions blade — ca-labdapr-bh2uom--xafdl2m still Degraded after restore](../../assets/troubleshooting/dapr-integration/06-revisions-still-degraded-after-restore.png)

**[Inferred]** Across captures #2 and #3, the only field that differs on the Dapr blade is `App port` (8000 vs 8081). This is consistent with `--dapr-app-port` mutating only `properties.configuration.dapr.appPort` on the Container App resource and leaving `App ID`, `Dapr enabled`, and `App protocol` unchanged.

**[Not Proven]** That the `Running status: Degraded` visible in captures #4 and #6 was *caused by* a Dapr `appPort` mismatch. The bundled `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` image (capture #5) listens on port 80, not 8000, so a Dapr sidecar→app health probe targeting either `appPort=8000` or `appPort=8081` would target a port the image does not bind. The revision was not observed `Healthy` at any point during this reproduction, so the captures show only *correlation* between an `appPort` value and a Degraded revision, not causation. To make causation cleanly falsifiable, swap the bicep template's image for one that binds to `0.0.0.0:8000` and re-run the trigger.

## Clean Up

```bash
az group delete --name "$RG" --yes --no-wait
```

| Command | Why it is used |
|---|---|
| `az group delete ...` | Removes the lab resource group and its contained resources. |

## Related Playbook

- [Dapr Sidecar or Component Failure](../playbooks/platform-features/dapr-sidecar-or-component-failure.md)

## See Also

- [Probe Failure and Slow Start](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md)
- [Traffic Routing and Canary Failure Lab](./traffic-routing-canary.md)

## Sources

- [Dapr integration with Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-overview)
- [Dapr components in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/dapr-components)
