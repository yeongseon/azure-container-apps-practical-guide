---
content_sources:
  diagrams:
  - id: use-this-ordered-checklist-when-a
    type: flowchart
    source: mslearn-adapted
    based_on:
    - https://learn.microsoft.com/azure/container-apps/
content_validation:
  status: verified
  last_reviewed: '2026-05-23'
  reviewer: agent
  core_claims:
  - claim: This page uses Microsoft Learn as the primary source basis for its Azure-specific
      guidance.
    source: https://learn.microsoft.com/azure/container-apps/
    verified: true
---
# First 10 Minutes: Quick Triage Checklist

Use this ordered checklist when a Container App is down, unhealthy, or unreachable. Run each step in sequence and stop when you find the first confirmed failure.

<!-- diagram-id: use-this-ordered-checklist-when-a -->
```mermaid
flowchart TD
    START["App Down / Unhealthy"] --> R["1) Revision Status"]
    R --> REP["2) Replica Status"]
    REP --> LOG["3) Container Logs"]
    LOG --> IMG["4) Image Pull"]
    IMG --> ING["5) Ingress Config"]
    ING --> PROBE["6) Health Probes"]
    PROBE --> REGAUTH["7) Registry Auth"]
    REGAUTH --> SEC["8) Secrets and Config"]
    SEC --> NET["9) Environment and Network"]
    NET --> DEP["10) Dependencies"]
```

!!! tip "Run from a clean shell session"
    Export variables once to avoid command mistakes:

    ```bash
    RG="rg-myapp"
    APP_NAME="ca-myapp"
    ENVIRONMENT_NAME="cae-myapp"
    ACR_NAME="acrmyapp"
    ```

## 1) Revision Status

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.provisioningState" --output tsv
```

| Command | Why it is used |
|---|---|
| `az containerapp show --name ...` | Reads the Container App configuration so the documented setting can be verified. |

Expected baseline from a healthy deployment:

```text
Succeeded
```

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,active:properties.active,health:properties.healthState,running:properties.runningState,created:properties.createdTime}" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list ...` | Lists revisions so rollout state, traffic, and health can be verified. |

Observed output pattern:

```text
Name               Active    Health    Running    Created
-----------------  --------  --------  ---------  -------------------------
ca-myapp--0000001  True      Healthy   Running    2026-04-04T11:30:41+00:00
```

- Look for the latest revision with `health=Healthy` and `running=Running`.
- Failure patterns: `Provisioning failed`, `Failed`, `Degraded`, inactive latest revision.
- If failed → go to [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md).

### Portal view: Revisions and replicas

Navigate: **Container App → Application → Revisions and replicas → Active revisions**.

![Revisions and replicas blade showing one active revision in Running state with 100% traffic and 1 replica](../../assets/troubleshooting/first-10-minutes/01-revisions-and-replicas.png)

`[Observed]` The **Active revisions** tab lists the revision `ca-ops-cgedjv--dkckziz` with **Running status: Running**, **Traffic: 100%**, and **Replicas: 1**. This is the healthy baseline — a single active revision serving all traffic with at least one healthy replica. If the latest revision is missing, shows `Provisioning failed`, or is split into multiple competing revisions, jump to the playbook linked above.

## 2) Replica Status

```bash
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --query "[].{replica:name,runningState:properties.runningState,created:properties.createdTime}" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp replica list ...` | Runs the Azure CLI operation required by the documented step. |

Observed output pattern:

```text
Replica                                RunningState    Created
-------------------------------------  --------------  -------------------------
ca-myapp--0000001-646779b4c5-bhc2v     Running         2026-04-04T11:30:52+00:00
```

- Look for replicas that remain in `Running` state.
- Failure patterns: repeated short-lived replicas, no replicas created, restart loops.
- If failed → go to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

### Portal view: Replicas tab

Navigate: **Container App → Application → Revisions and replicas → Replicas**.

![Replicas tab showing one running replica with revision and creation timestamp](../../assets/troubleshooting/first-10-minutes/02-replicas-tab.png)

`[Observed]` The **Replicas** tab lists a single replica `ca-ops-cgedjv--dkckziz-5f495449d5-vpjzs` in **Running** state. Use this view to confirm replicas are long-lived. `[Inferred]` If you refresh the blade every 30 seconds and see the replica name change repeatedly (different pod-hash suffix), the container is crash-looping even though the revision shows healthy. That symptom maps to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

## 3) Container Logs

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --tail 50
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show ...` | Runs the Azure CLI operation required by the documented step. |

For continuous streaming, add `--follow` and press Ctrl+C to exit.

Observed healthy startup console sequence (Gunicorn):

```text
Starting application...
PORT=8000
Workers=auto
[2026-04-04 11:30:53 +0000] [7] [INFO] Starting gunicorn 25.3.0
[2026-04-04 11:30:53 +0000] [7] [INFO] Listening at: http://0.0.0.0:8000 (7)
[2026-04-04 11:30:53 +0000] [7] [INFO] Using worker: sync
[2026-04-04 11:30:54 +0000] [8] [INFO] Booting worker with pid: 8
```

- Look for Python traceback, startup command failures, bind errors, missing configuration.
- Failure patterns: `ModuleNotFoundError`, `Address already in use`, `connection refused`, crash loops.
- If failed → go to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

### Portal view: Log stream

Navigate: **Container App → Monitoring → Log stream**.

![Log stream blade with replica/container selectors and live stdout/stderr output area](../../assets/troubleshooting/first-10-minutes/03-log-stream.png)

`[Observed]` The **Log stream** blade lets you pick **Replica** and **Container** from drop-downs, then streams stdout/stderr in real time without waiting for Log Analytics ingestion. Use this when a replica has just started and Log Analytics has not yet received the first records (typical lag: 1-3 minutes). `[Not Proven]` Log stream does not show **historical** logs — only what arrives after you open the blade. For root-cause analysis of a past failure, switch to the **Logs** blade and query `ContainerAppConsoleLogs_CL`.

## 4) Image Pull

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az acr repository show-tags --name "$ACR_NAME" --repository "$APP_NAME" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show ...` | Runs the Azure CLI operation required by the documented step. |

Observed pull success pattern:

```text
TimeGenerated              Reason_s      Log_s
-------------------------  ------------  ---------------------------------------------------------------
2026-04-04T12:54:11.477Z   PullingImage  Pulling image '<acr-name>.azurecr.io/myapp:v1.0.0'
2026-04-04T12:54:11.477Z   PulledImage   Successfully pulled image in 2.42s. Image size: 58720256 bytes.
```

- Confirm image tag exists and system logs do not show pull/auth errors.
- Failure patterns: `ImagePullBackOff`, `manifest unknown`, `unauthorized`, `denied`.
- If failed → go to [Image Pull Failure](../playbooks/startup-and-provisioning/image-pull-failure.md).

### Portal view: Container image configuration

Navigate: **Container App → Application → Containers → Properties**.

![Containers Properties tab showing Registry login server, Image and tag fields, and resource allocation](../../assets/troubleshooting/first-10-minutes/04-containers-image-config.png)

`[Observed]` The **Properties** tab under **Containers** shows the **Registry login server** (`mcr.microsoft.com`) and **Image and tag** (`k8se/quickstart:latest`) the platform is attempting to pull. `[Inferred]` If the value here does not match what you pushed, the most recent revision was created from a stale template — check your CI/CD pipeline or `az containerapp update --image` step. `[Not Proven]` This blade only shows the **configured** image reference; whether the pull succeeded must still be verified through system logs (the CLI command above) or the Activity log.

## 5) Ingress Configuration

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show --name ...` | Reads the Container App configuration so the documented setting can be verified. |

- Confirm `external` setting matches your access model and `targetPort` matches app listening port.
- Failure patterns: ingress disabled, wrong `targetPort`, internal app tested from public internet.
- If failed → go to [Ingress Not Reachable](../playbooks/ingress-and-networking/ingress-not-reachable.md).

### Portal view: Ingress

Navigate: **Container App → Networking → Ingress**.

![Ingress blade showing Ingress enabled, traffic accepting from Anywhere, target port 80, and transport Auto](../../assets/troubleshooting/first-10-minutes/05-ingress.png)

`[Observed]` The **Ingress** blade shows the binary toggle (**Ingress**: enabled), the traffic-source dropdown (**Accepting traffic from**: Anywhere = external), and the **Target port** field (`80`). The **Application Url** at the top of the blade is the externally resolvable FQDN. `[Inferred]` Three common misconfigurations are visible here at a glance: (1) toggle off → no FQDN issued, (2) **Accepting traffic from** set to **VNet** while you are testing from the public internet → DNS resolves but connection times out, (3) **Target port** does not match the port your app listens on (e.g. app binds `8000` but ingress points at `80`) → connections reset with no app logs.

## 6) Health Probes

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].probes" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show --name ...` | Reads the Container App configuration so the documented setting can be verified. |

- Confirm liveness/readiness probe paths and ports are valid; startup probe timeout fits app boot time.
- Failure patterns: probe path returns 404/500, startup timeout too short, wrong probe port.
- If failed → go to [Probe Failure and Slow Start](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md).

!!! warning "Probe defaults can still fail"
    Apps with migrations, cold dependency checks, or large model loads often need a longer startup probe window.

### Portal view: Health probes

Navigate: **Container App → Application → Containers → Health probes**.

![Containers Health probes tab showing Startup, Liveness, and Readiness probe configuration](../../assets/troubleshooting/first-10-minutes/06-health-probes.png)

`[Observed]` The **Health probes** tab exposes the three probe types (**Startup**, **Liveness**, **Readiness**) and lets you inspect each one's transport (HTTP/TCP/gRPC), path, port, and timing fields without parsing JSON. `[Inferred]` This is the fastest way to spot the three classic probe mistakes: (1) path returns 404 in the app's router → readiness flaps, (2) **Startup probe** timeout shorter than actual boot time (e.g. 30 s for an app that needs 60 s to warm a model) → revision never goes Ready, (3) probe **Port** does not match the container's listening port → TCP probe succeeds (port open) but HTTP probe fails. `[Not Proven]` The Portal does not show **historical** probe results; for that, query `ContainerAppSystemLogs_CL | where Reason_s in ("LivenessProbeFailed","ReadinessProbeFailed","StartupProbeFailed")` in Log Analytics.

## 7) Registry Authentication

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json
az role assignment list --scope "$(az acr show --name "$ACR_NAME" --query id --output tsv)" --assignee "$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query identity.principalId --output tsv)" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp show --name ...` | Reads the Container App configuration so the documented setting can be verified. |

- Confirm managed identity exists and has `AcrPull` role on the registry scope.
- Failure patterns: no principal ID, missing `AcrPull`, ACR firewall blocks environment egress.
- If failed → go to [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md) and [Image Pull Failure](../playbooks/startup-and-provisioning/image-pull-failure.md).

### Portal view: Identity

Navigate: **Container App → Settings → Identity**.

![Identity blade showing system-assigned managed identity enabled with Object ID and Permissions Azure role assignments link](../../assets/troubleshooting/first-10-minutes/07-identity.png)

`[Observed]` The **System assigned** tab shows **Status: On** and exposes the **Object (principal) ID** the platform uses for token requests, plus a **Permissions / Azure role assignments** link that pivots to the IAM blade scoped to this identity. The **User assigned** tab (separate) lists any user-assigned identities attached to the app. `[Inferred]` If **Status: Off**, the app cannot use managed identity at all — registry pulls fall back to admin credentials (which may be disabled on hardened ACRs) and any Key Vault references fail at revision-provisioning time. `[Not Proven]` This blade does not show **which** revisions are using the identity — that detail lives in the revision's Containers configuration.

## 8) Secrets and Config

```bash
az containerapp secret list --name "$APP_NAME" --resource-group "$RG"
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].env" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp secret list ...` | Manages Container Apps secrets without exposing secret values in plain configuration. |

- Confirm secret references exist and expected environment variables are present.
- Failure patterns: `secretRef` points to missing secret, null env var values, stale revision after secret update.
- If failed → go to [Secret and Key Vault Reference Failure](../playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) and [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md).

## 9) Environment and Network

```bash
az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RG" --output json
az network private-endpoint list --resource-group "$RG" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp env show ...` | Reads managed environment settings for networking, logging, or workload profile verification. |

- Confirm environment is healthy and network dependencies (private DNS/private endpoints) are correctly configured.
- Failure patterns: DNS resolution failures, blocked NSG outbound rules, missing private DNS link.
- If failed → go to [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

### Portal view: Container Apps Environment overview

Navigate: **Container Apps Environment → Overview**.

![Container Apps Environment overview blade with status, location, subscription, and links to Log Analytics and apps](../../assets/troubleshooting/first-10-minutes/09-environment-overview.png)

`[Observed]` The **Environment** Overview shows **Status: Succeeded**, the linked **Log Analytics workspace**, the **Environment type** (Workload profiles or Consumption only), and the list of Container Apps deployed inside. `[Inferred]` If the environment is in a custom VNet, the Overview also exposes the **Infrastructure subnet** — verify outbound rules on its NSG and route table here. If the environment status is anything other than **Succeeded** (`Failed`, `Updating`, `Canceled`), every app inside is affected; fix the environment before debugging individual apps. `[Not Proven]` The Overview does not show DNS resolution success or NSG flow logs — use **Network Watcher → Connection Troubleshoot** from the environment's subnet to test specific dependency endpoints.

## 10) Dependencies

```bash
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "python -c 'import socket; print(socket.gethostbyname(\"example.database.windows.net\"))'"
```

| Command | Why it is used |
|---|---|
| `az containerapp exec --name ...` | Runs the Azure CLI operation required by the documented step. |

- Confirm the app can resolve and reach critical services (database, storage, API endpoints).
- Failure patterns: DNS timeout, TLS handshake errors, outbound firewall denials.
- If failed → go to [Service-to-Service Connectivity Failure](../playbooks/ingress-and-networking/service-to-service-connectivity-failure.md), [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md), or [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

### Portal view: Console (exec into a replica)

Navigate: **Container App → Monitoring → Console**.

![Console blade with replica and container selectors and a Choose start up command dialog offering /bin/sh, /bin/bash, or Custom](../../assets/troubleshooting/first-10-minutes/10-console.png)

`[Observed]` The **Console** blade lets you select a **Replica** and **Container**, then opens an in-browser shell prompted by the **Choose start up command** dialog (`/bin/sh`, `/bin/bash`, or a custom command). Once attached, run dependency probes interactively (`nslookup`, `curl -v`, `nc -zv`) without needing `az containerapp exec` from your laptop. `[Inferred]` If **Reconnect** loops or the shell exits immediately, the container image lacks a shell (distroless / scratch base) — verify dependencies from a sidecar or rebuild with a debug image. `[Not Proven]` The Console runs **inside one replica**; a single successful probe does not prove every replica can reach the same dependency. Repeat against multiple replicas if you suspect intermittent network issues.

## Escalate with Context

Observed healthy system lifecycle sequence for reference:

```text
ContainerAppUpdate    → Updating containerApp: ca-myapp
RevisionCreation      → Creating new revision
PullingImage          → Pulling image '<acr-name>.azurecr.io/myapp:v1.0.0'
PulledImage           → Successfully pulled image in 2.42s (58720256 bytes)
ContainerCreated      → Created container 'ca-myapp'
ContainerStarted      → Started container 'ca-myapp'
ProbeFailed (Warning) → Probe of StartUp failed (multiple times during startup)
RevisionReady         → Revision ready
ContainerAppReady     → Running state reached
```

If the checklist does not isolate root cause, continue with [Troubleshooting Methodology](../methodology/index.md) and include:

- failing revision name
- exact error text from system/console logs
- ingress mode and target port
- dependency endpoint(s) that failed

## See Also

- [Troubleshooting Methodology](../methodology/index.md)
- [Troubleshooting Playbooks](../playbooks/index.md)
- [KQL Query Library](../kql/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
