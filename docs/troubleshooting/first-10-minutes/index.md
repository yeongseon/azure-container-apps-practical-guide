---
description: A ten-step Azure Container Apps triage checklist for revisions, replicas, logs, image pulls, ingress, probes, identity, secrets, and dependencies.
content_sources:
  diagrams:
    - id: use-this-ordered-checklist-when-a
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/
---
# First 10 Minutes: Quick Triage Checklist

Use this ordered checklist when a Container App is down, unhealthy, or unreachable. Run each step in sequence and stop when you find the first confirmed failure.

<!-- diagram-id: use-this-ordered-checklist-when-a -->
```mermaid
flowchart TD
    accTitle: First ten minutes of Container Apps triage
    accDescr: Start with platform state, then inspect runtime evidence, configuration, identity, networking, and dependencies in order. Stop at the first confirmed failure.

    START["App unavailable<br/>or unhealthy"]
    R["1. Revision status"]
    REP["2. Replica status"]
    LOG["3. Console and<br/>system logs"]
    IMG["4. Image reference<br/>and pull evidence"]
    ING["5. Ingress mode<br/>and target port"]
    PROBE["6. Startup, liveness,<br/>and readiness probes"]
    REGAUTH["7. Registry identity<br/>and authorization"]
    SEC["8. Secrets and<br/>environment configuration"]
    NET["9. Environment,<br/>DNS, and network path"]
    DEP["10. Dependency<br/>reachability"]
    ESCALATE["Escalate with revision,<br/>error, and path evidence"]

    START --> R
    R --> REP
    REP --> LOG
    LOG --> IMG
    IMG --> ING
    ING --> PROBE
    PROBE --> REGAUTH
    REGAUTH --> SEC
    SEC --> NET
    NET --> DEP
    DEP --> ESCALATE
```

The ordering moves from Azure-managed state to workload and dependency evidence. Stop when a step confirms a failure and follow its linked playbook instead of continuing with assumptions.

!!! tip "Run from a clean shell session"
    Export variables once to avoid command mistakes:

    ```bash
    RG="rg-myapp"
    APP_NAME="ca-myapp"
    ACA_ENV_NAME="cae-myapp"
    ACR_NAME="acrmyapp"
    ```

## 1) Revision Status

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.provisioningState" --output tsv
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the app resource to check its provisioning state. |
| `--name` | Identifies the unavailable app whose provisioning state starts the triage. |
| `--resource-group` | Locates that app resource for the initial provisioning-state check. |
| `--query` | Extracts `properties.provisioningState` from the resource. |
| `--output` | Returns the state as plain TSV for quick triage. |

Expected baseline from a healthy deployment:

```text
Succeeded
```

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,active:properties.active,health:properties.healthState,running:properties.runningState,created:properties.createdTime}" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list` | Lists revisions so rollout and health states can be compared. |
| `--name` | Identifies the app whose revision rollout and health history are inspected. |
| `--resource-group` | Scopes the revision inventory to the resource group of the affected app. |
| `--query` | Projects revision name, activation, health, running state, and creation time. |
| `--output` | Formats the projected revision records as a table. |

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

`[Observed]` The **Active revisions** tab lists the revision `ca-ops-cgedjv--dkckziz` with **Running status: Running**, **Traffic: 100%**, and **Replicas: 1**.

`[Inferred]` A single active revision serving 100% of traffic with a Running replica is the expected steady state for this app, so this snapshot is consistent with a healthy deployment. If the latest revision is missing, shows `Provisioning failed`, or is split into multiple competing revisions, jump to the playbook linked above.

`[Not Proven]` This blade does not confirm that the replica is **handling requests successfully** — only that the platform considers it Running. End-to-end health requires a probe response or a request-log entry (see Step 6 and Step 3).

## 2) Replica Status

```bash
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --query "[].{replica:name,runningState:properties.runningState,created:properties.createdTime}" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp replica list` | Lists current replicas to identify absent or repeatedly replaced instances. |
| `--name` | Identifies the app whose live replica population is being examined. |
| `--resource-group` | Locates the app for the replica-state and replacement-time inspection. |
| `--query` | Projects replica name, running state, and creation time. |
| `--output` | Formats the replica records as a table. |

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

`[Observed]` The **Replicas** tab lists a single replica `ca-ops-cgedjv--dkckziz-5f495449d5-vpjzs` in **Running** state, tied to the active revision.

`[Inferred]` If you refresh the blade every 30 seconds and see the replica name change repeatedly (different pod-hash suffix), the container is crash-looping even though the revision shows healthy. That symptom maps to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

`[Not Proven]` A single observation of one Running replica does not prove the replica is long-lived; only repeated refreshes (or `kubectl`-style restart counters, which this blade does not expose) can confirm stability over time.

## 3) Container Logs

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --tail 50
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show` | Retrieves recent application stdout and stderr for startup diagnosis. |
| `--name` | Identifies the app whose recent startup output is being retrieved. |
| `--resource-group` | Locates the app that emitted the console messages used for startup diagnosis. |
| `--type` | Chooses the console-log channel. |
| `--tail` | Limits the initial result to the newest 50 messages. |

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

`[Observed]` The **Log stream** blade exposes **Replica** and **Container** dropdowns above a console area that renders incoming stdout/stderr from the selected target.

`[Inferred]` This surface is the right tool when a replica has just started and you need output immediately — it subscribes to the live log channel rather than querying ingested data, so it avoids whatever ingestion delay the workspace currently has.

`[Not Proven]` The blade does not show **historical** logs — only what arrives after you open it — and the exact ingestion lag for the same lines to appear in `ContainerAppConsoleLogs_CL` is not visible here. For past failures, query the workspace through the **Logs** blade.

## 4) Image Pull

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az acr repository show-tags --name "$ACR_NAME" --repository "$APP_NAME" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show` | Retrieves platform events for image-pull and authorization evidence. |
| `az acr repository show-tags` | Confirms that the expected repository tag exists in ACR. |
| `--name` | Selects the Container App for logs or the ACR instance for tag lookup. |
| `--resource-group` | Locates the app for `az containerapp logs show` when checking image-pull failures. |
| `--type` | Chooses the system-log channel for `az containerapp logs show`. |
| `--repository` | Selects the image repository for `az acr repository show-tags`. |
| `--output` | Formats the tags returned by `az acr repository show-tags` as a table. |

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

`[Observed]` The **Properties** tab under **Containers** shows the **Registry login server** (`mcr.microsoft.com`) and **Image and tag** (`k8se/quickstart:latest`) currently configured on the active revision, along with the CPU/memory allocation for the container.

`[Inferred]` If the values here do not match what your last CI/CD run pushed, the most recent revision was created from a stale template — re-check the `az containerapp update --image` step (or equivalent IaC) in the pipeline.

`[Not Proven]` This blade only shows the **configured** image reference; it does not prove the pull actually succeeded. Pull success must still be verified through system logs (the CLI command above) or the Activity log.

## 5) Ingress Configuration

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the ingress configuration used by the active app. |
| `--name` | Identifies the app whose ingress exposure and target port are under review. |
| `--resource-group` | Locates the app for the ingress-mode and backend-port inspection. |
| `--query` | Extracts only `properties.configuration.ingress`. |
| `--output` | Preserves the ingress object as JSON for field inspection. |

- Confirm `external` setting matches your access model and `targetPort` matches app listening port.
- Failure patterns: ingress disabled, wrong `targetPort`, internal app tested from public internet.
- If failed → go to [Ingress Not Reachable](../playbooks/ingress-and-networking/ingress-not-reachable.md).

### Portal view: Ingress

Navigate: **Container App → Networking → Ingress**.

![Ingress blade showing Ingress enabled, traffic accepting from Anywhere, target port 80, and transport Auto](../../assets/troubleshooting/first-10-minutes/05-ingress.png)

`[Observed]` The **Ingress** blade shows **Ingress: enabled**, **Accepting traffic from: Anywhere**, **Target port: 80**, **Transport: Auto**, and an **Endpoint(s)** field that lists the app's URL.

`[Inferred]` Because **Accepting traffic from** is set to **Anywhere**, the URL listed under **Endpoint(s)** should be reachable from the public internet — this is the externally exposed FQDN for the app. Three common misconfigurations are visible here at a glance: (1) toggle off → no FQDN issued, (2) **Accepting traffic from** set to **VNet** while you are testing from the public internet → DNS resolves but connection times out, (3) **Target port** does not match the port your app listens on (e.g. app binds `8000` but ingress points at `80`) → connections reset with no app logs.

`[Not Proven]` This blade does not prove the FQDN actually resolves in public DNS or that an HTTP request reaches the container — confirm with `curl -v https://<fqdn>/` from outside the VNet.

## 6) Health Probes

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].probes" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads probe definitions from the first container in the revision template. |
| `--name` | Identifies the app whose startup, liveness, and readiness probes are inspected. |
| `--resource-group` | Locates the app template that contains the failing probe definitions. |
| `--query` | Extracts `properties.template.containers[0].probes`. |
| `--output` | Preserves the probe array as JSON for field inspection. |

- Confirm liveness/readiness probe paths and ports are valid; startup probe timeout fits app boot time.
- Failure patterns: probe path returns 404/500, startup timeout too short, wrong probe port.
- If failed → go to [Probe Failure and Slow Start](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md).

!!! warning "Probe defaults can still fail"
    Apps with migrations, cold dependency checks, or large model loads often need a longer startup probe window.

### Portal view: Health probes

Navigate: **Container App → Application → Containers → Health probes**.

![Containers Health probes tab showing Startup, Liveness, and Readiness probe configuration](../../assets/troubleshooting/first-10-minutes/06-health-probes.png)

`[Observed]` The **Health probes** tab under **Containers** lists the configured probes — the visible portion of the blade shows **Liveness** and **Readiness** sections with their transport (HTTP/TCP/gRPC), path, port, and timing fields exposed as editable form fields rather than raw JSON. **Startup** probe (the third type Container Apps supports) is rendered in the same scrollable list.

`[Inferred]` This view is the fastest way to catch the three classic probe mistakes: (1) path returns 404 in the app's router → readiness flaps, (2) **Startup probe** timeout shorter than actual boot time (e.g. 30 s for an app that needs 60 s to warm a model) → revision never goes Ready, (3) probe **Port** does not match the container's listening port → TCP probe succeeds (port open) but HTTP probe fails.

`[Not Proven]` The Portal does not show **historical** probe results; for that, query `ContainerAppSystemLogs_CL | where Reason_s in ("LivenessProbeFailed","ReadinessProbeFailed","StartupProbeFailed")` in Log Analytics.

## 7) Registry Authentication

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json
az acr show --name "$ACR_NAME" --query roleAssignmentMode --output tsv
az role assignment list --scope "$(az acr show --name "$ACR_NAME" --query id --output tsv)" --assignee "$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query identity.principalId --output tsv)" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the app identity and, in the nested call, its principal ID. |
| `az acr show` | Reads the registry role-assignment mode to select the expected pull role and resolves the registry resource ID used as the authorization scope. |
| `az role assignment list` | Lists role assignments for the app principal at the registry scope. |
| `--name` | Selects the ACR instance for `az acr show` and the Container App for `az containerapp show`. |
| `--resource-group` | Locates the app used by `az containerapp show` to resolve its managed-identity principal. |
| `--query` | Extracts `roleAssignmentMode` and the registry ID with `az acr show`, and extracts identity values with `az containerapp show`. |
| `--output` | Returns nested IDs as TSV and formats final assignments as a table. |
| `--scope` | Restricts `az role assignment list` to the registry resolved by the nested `az acr show`. |
| `--assignee` | Restricts `az role assignment list` to the principal resolved by the nested `az containerapp show`. |

- Inspect `roleAssignmentMode` before evaluating the assignment. For **RBAC Registry Permissions**, confirm the managed identity has `AcrPull` on the registry scope. For **RBAC Registry + ABAC Repository Permissions** (`AbacRepositoryPermissions`), confirm it has `Container Registry Repository Reader`; if that assignment has an ABAC condition, verify the condition includes the image repository. ABAC-enabled registries do not honor `AcrPull`.
- Failure patterns: no principal ID, missing or mode-inappropriate pull role, an ABAC condition that excludes the image repository, or an ACR firewall that blocks environment egress.
- If failed → go to [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md) and [Image Pull Failure](../playbooks/startup-and-provisioning/image-pull-failure.md).

### Portal view: Identity

Navigate: **Container App → Settings → Identity**.

![Identity blade System assigned tab showing Status On, Object principal ID, and an Azure role assignments button](../../assets/troubleshooting/first-10-minutes/07-identity.png)

`[Observed]` The **System assigned** tab shows **Status: On**, an **Object (principal) ID** value, a **User assigned** sibling tab, and an **Azure role assignments** button under **Permissions**. A notice at the bottom of the blade confirms the resource is **registered with Microsoft Entra ID**.

`[Inferred]` If **Status** is **Off**, the app cannot use a system-assigned managed identity at all — registry pulls fall back to admin credentials (which may be disabled on hardened ACRs) and any Key Vault references fail at revision-provisioning time. After inspecting the registry's **Role assignment permissions mode**, use **Azure role assignments** to verify that this Object ID holds `AcrPull` for **RBAC Registry Permissions**, or `Container Registry Repository Reader` for **RBAC Registry + ABAC Repository Permissions**. For an ABAC-conditioned assignment, also verify that the condition includes the image repository.

`[Not Proven]` This blade does not show which **revisions** are currently using the identity, nor whether a recent role assignment has propagated through Entra ID — propagation can lag image-pull attempts by minutes.

## 8) Secrets and Config

```bash
az containerapp secret list --name "$APP_NAME" --resource-group "$RG"
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].env" --output json
```

| Command | Why it is used |
|---|---|
| `az containerapp secret list` | Lists secret names and references without returning secret values. |
| `az containerapp show` | Reads environment-variable mappings from the revision template. |
| `--name` | Identifies the app whose secret references and environment mappings are compared. |
| `--resource-group` | Locates the app that owns the secret metadata and revision environment array. |
| `--query` | Makes `az containerapp show` extract the first container's environment-variable array. |
| `--output` | Makes `az containerapp show` preserve that array as JSON for mapping inspection. |

- Confirm secret references exist and expected environment variables are present.
- Failure patterns: `secretRef` points to missing secret, null env var values, stale revision after secret update.
- If failed → go to [Secret and Key Vault Reference Failure](../playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) and [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md).

!!! note "Portal capture intentionally omitted for this step"
    The Portal **Secrets** blade is intentionally not captured for this step. The CLI commands above are authoritative because they print secret **references** (env-var name → secret name → Key Vault URI) in a single output, which the Portal splits across multiple blades. Use the CLI as the source of truth for triage; open the Portal **Secrets** blade only when you need the inline edit/version UI.

## 9) Environment and Network

```bash
az containerapp env show --name "$ACA_ENV_NAME" --resource-group "$RG" --output json
az network private-endpoint list --resource-group "$RG" --output table
```

| Command | Why it is used |
|---|---|
| `az containerapp env show` | Reads the selected managed environment's health and network settings. |
| `az network private-endpoint list` | Lists private endpoints in the resource group for dependency-path checks. |
| `--name` | Selects the Container Apps environment for `az containerapp env show`. |
| `--resource-group` | Selects the resource group searched by both commands. |
| `--output` | Keeps environment details as JSON and formats private endpoints as a table. |

- Confirm environment is healthy and network dependencies (private DNS/private endpoints) are correctly configured.
- Failure patterns: DNS resolution failures, blocked NSG outbound rules, missing private DNS link.
- If failed → go to [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

### Portal view: Container Apps Environment overview

Navigate: **Container Apps Environment → Overview**.

![Container Apps Environment overview blade with status, location, subscription, and links to Log Analytics and apps](../../assets/troubleshooting/first-10-minutes/09-environment-overview.png)

`[Observed]` The **Environment** Overview blade shows **Status: Succeeded**, the linked **Log Analytics workspace**, the **Environment type** (Workload profiles or Consumption only), and the list of Container Apps deployed inside the environment.

`[Inferred]` If the environment is in a custom VNet, the Overview also exposes the **Infrastructure subnet** — use that as the starting point for verifying outbound NSG rules and route tables. If the environment status is anything other than **Succeeded** (`Failed`, `Updating`, `Canceled`), every app inside is affected; fix the environment before debugging individual apps.

`[Not Proven]` The Overview does not show DNS resolution success or NSG flow logs — use **Network Watcher → Connection Troubleshoot** from the environment's subnet to test specific dependency endpoints.

## 10) Dependencies

```bash
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "python -c 'import socket; print(socket.gethostbyname(\"example.database.windows.net\"))'"
```

| Command | Why it is used |
|---|---|
| `az containerapp exec` | Runs a DNS lookup from the workload's own replica context. |
| `--name` | Identifies the app whose running replica performs the dependency DNS probe. |
| `--resource-group` | Locates the app that provides the in-workload dependency-test context. |
| `--command` | Executes the Python socket lookup inside the running container. |

- Confirm the app can resolve and reach critical services (database, storage, API endpoints).
- Failure patterns: DNS timeout, TLS handshake errors, outbound firewall denials.
- If failed → go to [Service-to-Service Connectivity Failure](../playbooks/ingress-and-networking/service-to-service-connectivity-failure.md), [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md), or [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

### Portal view: Console (exec into a replica)

Navigate: **Container App → Monitoring → Console**.

![Console blade with replica and container selectors and a Choose start up command dialog offering /bin/sh, /bin/bash, or Custom](../../assets/troubleshooting/first-10-minutes/10-console.png)

`[Observed]` The **Console** blade exposes **Replica** and **Container** dropdowns and opens a **Choose start up command** dialog offering `/bin/sh`, `/bin/bash`, or a custom command before attaching an in-browser shell.

`[Inferred]` Once attached, you can run dependency probes interactively (`nslookup`, `curl -v`, `nc -zv`) without needing `az containerapp exec` from your laptop, which is useful when corporate egress blocks the CLI control plane. If **Reconnect** loops or the shell exits immediately, the container image likely lacks a shell (distroless / scratch base) — verify dependencies from a sidecar or rebuild with a debug image.

`[Not Proven]` The Console runs **inside one replica**; a single successful probe does not prove every replica can reach the same dependency. Repeat against multiple replicas if you suspect intermittent network issues.

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

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Container Registry permissions and role assignments overview (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-built-in-roles-overview)
- [Azure ABAC repository permissions in Azure Container Registry (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)
