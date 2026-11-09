---
description: Symptom-first Azure Container Apps troubleshooting playbooks for provisioning, ingress, scaling, identity, configuration, and platform features.
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/overview
  diagrams:
    - id: ca-myapp-0000001-true-100-1-healthy-running
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting
        - https://learn.microsoft.com/en-us/azure/container-apps/overview
content_validation:
  status: verified
  last_reviewed: '2026-07-18'
  reviewer: ai-agent
  core_claims:
    - claim: Azure Container Apps provides built-in observability features including log streaming and container console access.
      source: https://learn.microsoft.com/en-us/azure/container-apps/observability
      verified: true
    - claim: Container Apps revisions are immutable snapshots that enable traffic splitting and rollback.
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
---
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

| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the app provisioning state for the first split between control-plane deployment failure and a later runtime problem. |
| `--name` (`az containerapp show`) | Targets `ca-myapp`, the sample app being triaged. |
| `--resource-group` (`az containerapp show`) | Scopes the initial provisioning-state check to `rg-myapp`, the deployment boundary under triage. |
| `--query` (`az containerapp show`) | Pulls the app provisioning state for the first triage split between deployment failure and runtime failure. |
| `az containerapp revision list` | Shows whether `ca-myapp` has an active, healthy revision before deeper log analysis. |
| `--name` (`az containerapp revision list`) | Requests revisions owned by `ca-myapp`. |
| `--resource-group` (`az containerapp revision list`) | Searches `rg-myapp` for the app's revision records. |
| `az containerapp logs show` | Retrieves both platform events and application output to separate provisioning failures from container errors. |
| `--name` (`az containerapp logs show`) | Reads logs emitted for `ca-myapp`. |
| `--resource-group` (`az containerapp logs show`) | Restricts both log requests to the app deployed in `rg-myapp`. |
| `--type` (`az containerapp logs show`) | Requests `system` events first and `console` output second, covering both platform and application evidence. |
| `--follow` (`az containerapp logs show`) | Streams new console lines while the failure is reproduced. |


| Example output command | Purpose |
|---|---|
| `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState` | Shows the healthy app provisioning state used as the triage baseline below. |
| `az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table` | Shows the healthy active revision, traffic weight, replica count, health state, and running state used as the baseline below. |
| `--name` | Identifies the Container App represented by the example output. |
| `--resource-group` | Scopes the example lookup to the resource group that contains the app. |
| `--query` | Selects the app provisioning state displayed in the example. |
| `--output` | Formats the revision baseline as the displayed table. |

Use `APP_NAME="ca-myapp"` for the examples below. Real observed healthy outputs:

```text
$ az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState
"Succeeded"

$ az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table
Name               Active    TrafficWeight    Replicas    HealthState    RunningState
-----------------  --------  ---------------  ----------  -------------  ------------
ca-myapp--0000001  True      100              1           Healthy        Running
```

| Example output command | Purpose |
|---|---|
| `az containerapp show --name "$APP_NAME" --resource-group "$RG" --query properties.provisioningState` | Shows the healthy app provisioning state represented by the captured output. |
| `az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table` | Shows the healthy active revision represented by the captured output. |
| `--name` | Identifies the Container App represented by the captured output. |
| `--resource-group` | Scopes the captured output to the resource group that contains the app. |
| `--query` | Selects the app provisioning state represented by the captured output. |
| `--output` | Formats the captured revision evidence as a table. |

<!-- diagram-id: ca-myapp-0000001-true-100-1-healthy-running -->
```mermaid
flowchart TD
    accTitle: Route the first confirmed Container Apps symptom
    accDescr: Fast triage collects provisioning, revision, and log evidence before routing the incident to one primary playbook category.

    TRIAGE[Fast triage evidence<br/>provisioning state, revisions, system logs, console logs]
    SYM{Provisioning or startup evidence?}
    REQUEST{Request or dependency path evidence?}
    REPLICAS{Replica, scaler, or runtime evidence?}
    AUTH{Authentication or secret evidence?}
    FEATURE{Feature-specific evidence?}
    STARTUP[Startup and provisioning<br/>image, revision, container, or probe]
    INGRESS[Ingress and networking<br/>reachability, DNS, or service path]
    SCALING[Scaling and runtime<br/>replicas, scaler, restart, or resource pressure]
    IDENTITY[Identity and configuration<br/>token, RBAC, or secret]
    FEATURES[Platform features<br/>Dapr, jobs, rollout, or failover]
    RECLASSIFY[Collect another distinguishing signal and reclassify]

    TRIAGE --> SYM
    SYM -->|Yes| STARTUP
    SYM -->|No| REQUEST
    REQUEST -->|Yes| INGRESS
    REQUEST -->|No| REPLICAS
    REPLICAS -->|Yes| SCALING
    REPLICAS -->|No| AUTH
    AUTH -->|Yes| IDENTITY
    AUTH -->|No| FEATURE
    FEATURE -->|Yes| FEATURES
    FEATURE -->|No| RECLASSIFY
    RECLASSIFY --> TRIAGE

    LEGEND["Arrow key<br/>solid = symptom routing"]
```

*Figure: Route by the first evidence-backed symptom; if no category fits, collect a different signal instead of forcing a diagnosis.*

## Common Errors

| Error message / symptom | Likely cause | Fix |
| --- | --- | --- |
| `ImagePullBackOff`, `unauthorized: authentication required` | ACR auth/identity not configured | Inspect the registry's `roleAssignmentMode`; grant `AcrPull` in RBAC-only mode or `Container Registry Repository Reader` in RBAC Registry + ABAC Repository Permissions mode, optionally restricted with a repository condition, then verify `--registry-server` |
| `CrashLoopBackOff` | App exits on startup | Check console logs, missing package/env var, verify startup command |
| `ModuleNotFoundError: <module>` | Dependency missing from image | Add package to `requirements.txt`, rebuild image, redeploy |
| `Address already in use` or bind failure | Port mismatch | Ensure container listens on `0.0.0.0:8000` and Azure Container Apps `--target-port 8000` |
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

- [mTLS Failures](mtls-failures.md)
- [Ingress Not Reachable](ingress-and-networking/ingress-not-reachable.md)
- [Internal DNS and Private Endpoint Failure](ingress-and-networking/internal-dns-and-private-endpoint-failure.md)
- [Service-to-Service Connectivity Failure](ingress-and-networking/service-to-service-connectivity-failure.md)

### Scaling and Runtime

- [HTTP Scaling Not Triggering](scaling-and-runtime/http-scaling-not-triggering.md)
- [Event Scaler Mismatch](scaling-and-runtime/event-scaler-mismatch.md)
- [CrashLoop OOM and Resource Pressure](scaling-and-runtime/crashloop-oom-and-resource-pressure.md)
- [Memory Percentage vs KEDA Utilization](scaling-and-runtime/memory-percentage-vs-keda-utilization.md)

### Identity and Configuration

- [Managed Identity Auth Failure](identity-and-configuration/managed-identity-auth-failure.md)
- [Secret and Key Vault Reference Failure](identity-and-configuration/secret-and-key-vault-reference-failure.md)
- [Continuous Deployment RBAC Role Assignment Conflict](identity-and-configuration/cd-rbac-role-assignment-conflict.md)

### Platform Features

- [Dapr Sidecar or Component Failure](platform-features/dapr-sidecar-or-component-failure.md)
- [Container App Job Execution Failure](platform-features/container-app-job-execution-failure.md)
- [Bad Revision Rollout and Rollback](platform-features/bad-revision-rollout-and-rollback.md)
- [Scheduled Job Missed Execution](platform-features/scheduled-job-missed.md)
- [Event-Triggered Job Storm](platform-features/event-job-storm.md)
- [Dapr State Store Config Failure](platform-features/dapr-state-store-failure.md)
- [Dapr Pub/Sub Config Failure](platform-features/dapr-pubsub-failure.md)
- [EasyAuth Entra ID Config Failure](platform-features/easyauth-entra-id-failure.md)
- [Multi-Region Failover Failure](platform-features/multi-region-failover.md)

### Networking Advanced

- [Subnet CIDR Exhaustion](networking-advanced/subnet-cidr-exhaustion.md)
- [UDR and NSG Egress Blocked](networking-advanced/udr-nsg-egress-blocked.md)
- [Private Endpoint DNS Failure](networking-advanced/private-endpoint-dns-failure.md)
- [Egress IP Change](networking-advanced/egress-ip-change.md)
- [Custom Domain TLS Renewal](networking-advanced/custom-domain-tls-renewal.md)
- [WebSocket and gRPC Ingress](networking-advanced/websocket-grpc-ingress.md)
- [Session Affinity Failure](networking-advanced/session-affinity-failure.md)

### Storage and Volumes

- [Azure Files Mount Failure](storage-and-volumes/azure-files-mount-failure.md)
- [EmptyDir Disk Full](storage-and-volumes/emptydir-disk-full.md)
- [Volume Permission Denied](storage-and-volumes/volume-permission-denied.md)

### Observability

- [Log Analytics Ingestion Gap](observability/log-analytics-ingestion-gap.md)
- [App Insights Connection String Missing](observability/appinsights-connection-string-missing.md)
- [Diagnostic Settings Missing](observability/diagnostic-settings-missing.md)

### Deployment and CI/CD

- [GitHub Actions OIDC Failure](deployment-and-cicd/github-actions-oidc-failure.md)
- [Bicep Deployment Timeout](deployment-and-cicd/bicep-deployment-timeout.md)
- [Revision History Limit](deployment-and-cicd/revision-history-limit.md)

### Cost and Quota

- [Subscription Quota Exceeded](cost-and-quota/subscription-quota-exceeded.md)
- [Workload Profile Mismatch](cost-and-quota/workload-profile-mismatch.md)
- [Min Replicas Cost Surprise](cost-and-quota/min-replicas-cost-surprise.md)

### Startup and Provisioning (extended)

- [Docker Hub Rate Limit](startup-and-provisioning/docker-hub-rate-limit.md)
- [Image Size Startup Delay](startup-and-provisioning/image-size-startup-delay.md)
- [Multi-Arch Image Mismatch](startup-and-provisioning/multi-arch-image-mismatch.md)

### Scaling and Runtime (extended)

- [CPU Throttling](scaling-and-runtime/cpu-throttling.md)
- [Memory Leak OOMKilled](scaling-and-runtime/memory-leak-oomkilled.md)
- [Replica Load Imbalance](scaling-and-runtime/replica-load-imbalance.md)

## How to Use This Hub

1. Run the fast triage commands to identify the first concrete failure signal.
2. Open the matching playbook and work through hypotheses and evidence collection.
3. Use [KQL Queries](../kql/index.md) for timeline and correlation.
4. If multiple signals conflict, use the [Detector Map](../methodology/detector-map.md).

## Contributing a New Playbook

Start from the [playbook template](../../contributing/playbook-template.md). Copy the file, rename it, and fill in each section. The template includes all required frontmatter fields, section headings, and CI-compliance markers (diagram-id comments, command explanation tables).

## See Also

- [First 10 Minutes: Quick Triage Checklist](../first-10-minutes/index.md)
- [Troubleshooting Methodology](../methodology/index.md)
- [Detector Map](../methodology/detector-map.md)

## Sources

- [Azure Container Apps troubleshooting overview](https://learn.microsoft.com/en-us/azure/container-apps/troubleshooting)
- [Azure Container Apps overview](https://learn.microsoft.com/en-us/azure/container-apps/overview)
- [Azure Container Apps revisions](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Azure Container Registry roles and permission modes](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-built-in-roles-overview)
- [Azure Container Registry repository permissions with ABAC](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-rbac-abac-repository-permissions)
