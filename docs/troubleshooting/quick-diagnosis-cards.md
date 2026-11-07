---
description: Rapid Azure Container Apps diagnosis cards that connect symptoms to evidence, platform segments, and focused troubleshooting playbooks.
content_sources:
  diagrams:
    - id: card-1-image-pull-failure
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-image-pull-failures
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
content_validation:
  status: verified
  last_reviewed: 2026-11-08
  reviewer: agent
  core_claims:
    - claim: Azure Container Apps provides system logs and console logs for diagnosis and troubleshooting.
      source: https://learn.microsoft.com/en-us/azure/container-apps/observability
      verified: true
    - claim: Azure Container Apps health probes include startup, liveness, and readiness probes.
      source: https://learn.microsoft.com/en-us/azure/container-apps/health-probes
      verified: true
    - claim: Azure Container Apps supports automatic scaling based on HTTP traffic and events.
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
    - claim: Managed identities can be used by Azure Container Apps to access Azure services.
      source: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity
      verified: true
---
# Quick Diagnosis Cards

One-page reference cards for rapid incident triage. Each card maps: **Symptom → First Query → Platform Segment → Playbook**.

Use these when you have 60 seconds to identify the failure category.

!!! note "Choose the table schema for the logging destination"
    The card queries use the legacy direct Log Analytics destination: `ContainerAppSystemLogs_CL`, `ContainerAppConsoleLogs_CL`, and suffixed columns such as `Log_s` and `RevisionName_s`. Environments that route logs through Azure Monitor diagnostic settings use `ContainerAppSystemLogs`, `ContainerAppConsoleLogs`, and unsuffixed columns such as `Log` and `RevisionName`. `ContainerAppHTTPLogs` never uses an `_CL` suffix.

---

## Card 1: Image Pull Failure

<!-- diagram-id: card-1-image-pull-failure -->
```mermaid
flowchart TD
    SYMPTOM[Revision fails to provision]
    SYSTEM[System-log image-pull evidence]
    REASON[Classify the failure reason]
    AUTH[Authentication or authorization]
    IMAGE[Image, tag, or manifest]
    NETWORK[Registry DNS or network reachability]
    FIX[Apply one matching correction]
    VERIFY[Verify a fresh revision pulls the image<br/>and reaches healthy state]
    RETURN[Return to competing hypotheses]
    CLOSE[Record image-pull evidence<br/>and recovery]

    SYMPTOM --> SYSTEM
    SYSTEM --> REASON
    REASON -->|Unauthorized or denied| AUTH
    REASON -->|Not found or manifest unknown| IMAGE
    REASON -->|Timeout or DNS failure| NETWORK
    AUTH --> FIX
    IMAGE --> FIX
    NETWORK --> FIX
    FIX --> VERIFY
    VERIFY -->|Still failing| RETURN
    VERIFY -->|Healthy| CLOSE
```

The card distinguishes registry authorization, image reference, and network failures before applying a fix, then requires a fresh healthy revision as falsification evidence.

| Step | Action |
|---|---|
| **Symptom** | New revision stuck in "Provisioning" state, never becomes "Running" |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(15m) \| where Log_s has_any ("pull", "image", "auth", "401", "403", "manifest") \| take 50` |
| **What to Look For** | `unauthorized`, `manifest unknown`, `connection refused`. Check ACR name and credentials. |
| **Platform Segment** | Startup / Provisioning |
| **Playbook** | [Image Pull Failure](playbooks/startup-and-provisioning/image-pull-failure.md) |

**Quick CLI Check:**

```bash
az containerapp revision list --resource-group $RG --name $APP_NAME --query "[].{name:name, status:properties.runningState}" --output table
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp revision list` | Lists revision running states to identify the revision blocked by an image-pull failure. |
| `--name` | Selects the container app whose revision rollout is stuck. |
| `--output` | Formats the revision names and running states as a table. |
| `--query` | Projects only each revision name and running state for rapid diagnosis. |
| `--resource-group` | Selects the resource group containing the app. |

---

## Card 2: Container Start Failure (CrashLoopBackOff)

| Step | Action |
|---|---|
| **Symptom** | Container starts but crashes repeatedly, revision never healthy |
| **First Query** | `ContainerAppConsoleLogs_CL \| where TimeGenerated > ago(30m) \| where Log_s has_any ("error", "exception", "traceback", "failed", "exit") \| take 100` |
| **What to Look For** | Application exceptions, missing environment variables, port binding issues (`EADDRINUSE`). |
| **Platform Segment** | Startup / Provisioning |
| **Playbook** | [Container Start Failure](playbooks/startup-and-provisioning/container-start-failure.md) |

**Quick CLI Check:**

```bash
az containerapp logs show --resource-group $RG --name $APP_NAME --type console --tail 100
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp logs show` | Retrieves application output that exposes the exception causing repeated starts. |
| `--name` | Selects the container app with the suspected start failure. |
| `--resource-group` | Selects the resource group containing the app. |
| `--tail` | Limits the check to the 100 most recent console-log lines. |
| `--type` | Selects application console output rather than platform system events. |


---

## Card 3: Health Probe Failure / Slow Start

| Step | Action |
|---|---|
| **Symptom** | Container starts but probe times out, revision marked unhealthy |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(30m) \| where Log_s has_any ("probe", "health", "liveness", "readiness", "unhealthy") \| take 50` |
| **What to Look For** | Probe timeout, wrong port, path returning non-2xx. Check `targetPort` vs actual listening port. |
| **Platform Segment** | Startup / Provisioning |
| **Playbook** | [Probe Failure and Slow Start](playbooks/startup-and-provisioning/probe-failure-and-slow-start.md) |

**Quick CLI Check:**

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query "properties.template.containers[0].probes"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads configured probes for comparison with the container's actual port and startup behavior. |
| `--name` | Selects the container app with the failing or slow probe. |
| `--query` | Returns only the first container's probe configuration. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Card 4: Ingress Not Reachable (502/503)

| Step | Action |
|---|---|
| **Symptom** | External requests return 502/503, app appears running |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(1h) \| where Log_s has_any ("ingress", "upstream", "502", "503", "connection refused") \| take 50` |
| **What to Look For** | No healthy replicas, ingress disabled, port mismatch between ingress and container. |
| **Platform Segment** | Ingress / Networking |
| **Playbook** | [Ingress Not Reachable](playbooks/ingress-and-networking/ingress-not-reachable.md) |

**Quick CLI Check:**

```bash
az containerapp ingress show --resource-group $RG --name $APP_NAME
az containerapp replica list --resource-group $RG --name $APP_NAME --query "[].{name:name, status:properties.runningState}"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp ingress show` | Reads the app's exposure and target-port settings for the 502/503 path. |
| `--name` | Selects the container app whose ingress and replicas are being checked. |
| `--resource-group` | Selects the resource group containing the app. |
| `az containerapp replica list` | Lists current replicas to determine whether ingress has a running backend. |
| `--query` | Projects only replica names and running states for rapid comparison. |

---

## Card 5: DNS / Private Endpoint Resolution Failure

| Step | Action |
|---|---|
| **Symptom** | App cannot reach private resources, DNS errors in logs |
| **First Query** | `ContainerAppConsoleLogs_CL \| where TimeGenerated > ago(1h) \| where Log_s has_any ("getaddrinfo", "Name or service not known", "NXDOMAIN", "DNS", "resolve") \| take 50` |
| **What to Look For** | Private DNS zone not linked to VNet, incorrect custom DNS server, missing Private Endpoint. |
| **Platform Segment** | Ingress / Networking |
| **Playbook** | [Internal DNS and Private Endpoint Failure](playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md) |

**Quick CLI Check:**

```bash
# Check environment VNet configuration
az containerapp env show --resource-group $RG --name $ACA_ENV_NAME --query "properties.vnetConfiguration"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp env show` | Reads the environment VNet configuration used by private DNS and private endpoint traffic. |
| `--name` | Selects the Container Apps environment with the DNS failure. |
| `--query` | Returns only `properties.vnetConfiguration` for network-path inspection. |
| `--resource-group` | Selects the resource group containing the environment. |


---

## Card 6: HTTP Scaling Not Triggering

| Step | Action |
|---|---|
| **Symptom** | Traffic increases but replica count stays at minimum |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(2h) \| where Log_s has_any ("scale", "replica", "KEDA", "concurrency") \| summarize count() by bin(TimeGenerated, 5m)` |
| **What to Look For** | Scale rule misconfiguration, concurrency threshold too high, minReplicas = maxReplicas. |
| **Platform Segment** | Scaling / Runtime |
| **Playbook** | [HTTP Scaling Not Triggering](playbooks/scaling-and-runtime/http-scaling-not-triggering.md) |

**Quick CLI Check:**

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query "properties.template.scale"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads replica limits and HTTP scale settings that may prevent scale-out. |
| `--name` | Selects the container app that is not scaling with HTTP traffic. |
| `--query` | Returns only the app's scale configuration. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Card 7: Event Scaler Mismatch (Queue/Kafka/etc.)

| Step | Action |
|---|---|
| **Symptom** | Event-driven scaling not responding to queue depth or event rate |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(2h) \| where Log_s has_any ("scaler", "queue", "kafka", "servicebus", "trigger", "metric") \| take 50` |
| **What to Look For** | Wrong connection string, permission denied, scaler metadata mismatch. |
| **Platform Segment** | Scaling / Runtime |
| **Playbook** | [Event Scaler Mismatch](playbooks/scaling-and-runtime/event-scaler-mismatch.md) |

**Quick CLI Check:**

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query "properties.template.scale.rules"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads event-driven scale rules for metadata and authentication comparison. |
| `--name` | Selects the container app whose event scaler is not activating. |
| `--query` | Returns only `properties.template.scale.rules` for scaler inspection. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Card 8: OOM / CrashLoop / Resource Pressure

| Step | Action |
|---|---|
| **Symptom** | Container restarts repeatedly, often under load |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(6h) \| where Log_s has_any ("OOM", "killed", "memory", "evicted", "resource") \| take 50` |
| **What to Look For** | Memory limit too low, memory leak in application, CPU throttling. |
| **Platform Segment** | Scaling / Runtime |
| **Playbook** | [CrashLoop OOM and Resource Pressure](playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md) |

**Quick CLI Check:**

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query "properties.template.containers[0].resources"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads configured CPU and memory values for comparison with OOM or throttling evidence. |
| `--name` | Selects the container app experiencing resource pressure. |
| `--query` | Returns only the first container's resource configuration. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Card 9: Managed Identity Auth Failure

| Step | Action |
|---|---|
| **Symptom** | App cannot authenticate to Azure services (Key Vault, Storage, SQL) |
| **First Query** | `ContainerAppConsoleLogs_CL \| where TimeGenerated > ago(1h) \| where Log_s has_any ("401", "403", "Unauthorized", "AADSTS", "ManagedIdentity", "DefaultAzureCredential") \| take 50` |
| **What to Look For** | Identity not assigned, missing RBAC role, wrong resource scope. |
| **Platform Segment** | Identity / Configuration |
| **Playbook** | [Managed Identity Auth Failure](playbooks/identity-and-configuration/managed-identity-auth-failure.md) |

**Quick CLI Check:**

```bash
az containerapp identity show --resource-group $RG --name $APP_NAME
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp identity show` | Displays assigned identities so a missing or incorrect managed identity can be detected. |
| `--name` | Selects the container app with the authentication failure. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Card 10: Secret / Key Vault Reference Failure

| Step | Action |
|---|---|
| **Symptom** | Revision fails to provision, secrets not populated |
| **First Query** | `ContainerAppSystemLogs_CL \| where TimeGenerated > ago(1h) \| where Log_s has_any ("secret", "keyvault", "reference", "403", "not found") \| take 50` |
| **What to Look For** | Key Vault access policy missing, secret name typo, managed identity not authorized. |
| **Platform Segment** | Identity / Configuration |
| **Playbook** | [Secret and Key Vault Reference Failure](playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) |

**Quick CLI Check:**

```bash
az containerapp show --resource-group $RG --name $APP_NAME --query "properties.configuration.secrets"
```


| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads configured secret references for comparison with the provisioning error. |
| `--name` | Selects the container app whose secret or Key Vault reference failed. |
| `--query` | Returns only `properties.configuration.secrets` for reference inspection. |
| `--resource-group` | Selects the resource group containing the app. |


---

## Universal First 3 Queries

When you don't know where to start, run these three queries to establish baseline:

### Query 1: System Events (Provisioning, Scaling, Health)

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(2h)
| where Log_s has_any ("provision", "scale", "replica", "health", "probe", "ingress", "pull")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
| take 100
```

### Query 2: Application Errors

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(2h)
| where Log_s has_any ("error", "exception", "failed", "timeout", "refused", "denied")
| project TimeGenerated, RevisionName_s, Log_s
| order by TimeGenerated desc
| take 100
```

### Query 3: Revision Status Timeline

```kusto
ContainerAppSystemLogs_CL
| where TimeGenerated > ago(24h)
| where Log_s has_any ("revision", "running", "failed", "degraded", "provisioning")
| summarize count() by bin(TimeGenerated, 15m), tostring(extract("revision[^\\s]*", 0, Log_s))
| order by TimeGenerated desc
```

---

## Decision Matrix

| Observation | Most Likely Card | Confidence |
|---|---|---|
| Revision stuck "Provisioning" | Card 1 (Image Pull) | High |
| Container crashes on start | Card 2 (Start Failure) | High |
| Probe timeout, unhealthy | Card 3 (Probe) | High |
| 502/503 from ingress | Card 4 (Ingress) | Medium-High |
| DNS/resolve errors | Card 5 (DNS) | High |
| No scaling despite traffic | Card 6 (HTTP Scale) | High |
| Queue not draining | Card 7 (Event Scaler) | High |
| Repeated OOM restarts | Card 8 (Resource) | High |
| 401/403 to Azure services | Card 9 (Identity) | High |
| Secret not found errors | Card 10 (Key Vault) | High |

## See Also

- [Decision Tree](decision-tree.md)
- [Evidence Map](evidence-map.md)
- [First 10 Minutes Checklists](first-10-minutes/index.md)
- [KQL Query Library](kql/index.md)

## Sources

- [Azure Container Apps monitoring overview](https://learn.microsoft.com/en-us/azure/container-apps/observability)
- [Azure Container Apps troubleshooting](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
- [Troubleshoot image pull failures](https://learn.microsoft.com/en-us/azure/container-apps/troubleshoot-image-pull-failures)
- [Monitor logs with Log Analytics](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
- [Azure Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
