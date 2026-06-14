---
content_sources:
  diagrams:
    - id: tutorial-validation-status-pie
      type: pie
      source: self-generated
      justification: Auto-generated from tutorial and lab validation frontmatter in this repository.
content_validation:
  status: verified
  last_reviewed: "2026-06-13"
  reviewer: ai-agent
  core_claims:
    - claim: "The dashboard is generated from validation frontmatter in repository Markdown files."
      source: scripts/generate_validation_status.py
      verified: true
---

# Tutorial Validation Status

This page tracks which tutorials have been validated against real Azure deployments. It scans language tutorial pages and troubleshooting lab guides. Each page can be tested via **az-cli** (manual CLI commands) or **Bicep** (infrastructure as code). Tutorials not tested within 90 days are marked as stale.

## Summary

*Generated: 2026-06-13*

| Metric | Count |
|---|---:|
| Total tutorials | 80 |
| ✅ Validated | 8 |
| ⚠️ Stale (>90 days) | 0 |
| ❌ Failed | 0 |
| ➖ Not tested | 72 |

<!-- diagram-id: tutorial-validation-status-pie -->
```mermaid
pie title Tutorial Validation Status
    "Validated" : 8
    "Not Tested" : 72
```

## Validation Matrix

### .NET

| Page | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/dotnet/tutorial/01-local-development.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/dotnet/tutorial/02-first-deploy.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [03 Configuration](../language-guides/dotnet/tutorial/03-configuration.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/dotnet/tutorial/04-logging-monitoring.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/dotnet/tutorial/05-infrastructure-as-code.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/dotnet/tutorial/06-ci-cd.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/dotnet/tutorial/07-revisions-traffic.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |

### Java

| Page | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/java/tutorial/01-local-development.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/java/tutorial/02-first-deploy.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [03 Configuration](../language-guides/java/tutorial/03-configuration.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/java/tutorial/04-logging-monitoring.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/java/tutorial/05-infrastructure-as-code.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/java/tutorial/06-ci-cd.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/java/tutorial/07-revisions-traffic.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |

### Node.js

| Page | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/nodejs/tutorial/01-local-development.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/nodejs/tutorial/02-first-deploy.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [03 Configuration](../language-guides/nodejs/tutorial/03-configuration.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/nodejs/tutorial/04-logging-monitoring.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/nodejs/tutorial/05-infrastructure-as-code.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/nodejs/tutorial/06-ci-cd.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/nodejs/tutorial/07-revisions-traffic.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |

### Python

| Page | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [01 Local Development](../language-guides/python/tutorial/01-local-development.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [02 First Deploy](../language-guides/python/tutorial/02-first-deploy.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [03 Configuration](../language-guides/python/tutorial/03-configuration.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [04 Logging Monitoring](../language-guides/python/tutorial/04-logging-monitoring.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [05 Infrastructure As Code](../language-guides/python/tutorial/05-infrastructure-as-code.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [06 Ci Cd](../language-guides/python/tutorial/06-ci-cd.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [07 Revisions Traffic](../language-guides/python/tutorial/07-revisions-traffic.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |

### Troubleshooting Labs

| Page | az-cli | Bicep | Last Tested | Status |
|---|---|---|---|---|
| [Acr Network Path Dns Forwarder Bypass](../troubleshooting/lab-guides/acr-network-path-dns-forwarder-bypass.md) | ✅ Pass | ✅ Pass | 2026-06-05 | ✅ Pass |
| [Acr Network Path Firewall Allowlist](../troubleshooting/lab-guides/acr-network-path-firewall-allowlist.md) | ✅ Pass | ✅ Pass | 2026-06-06 | ✅ Pass |
| [Acr Network Path Pe Direct](../troubleshooting/lab-guides/acr-network-path-pe-direct.md) | ✅ Pass | ✅ Pass | 2026-06-05 | ✅ Pass |
| [Acr Network Path Pe Forced Inspection](../troubleshooting/lab-guides/acr-network-path-pe-forced-inspection.md) | ✅ Pass | ✅ Pass | 2026-06-06 | ✅ Pass |
| [Acr Network Path Record Split Brain](../troubleshooting/lab-guides/acr-network-path-record-split-brain.md) | ✅ Pass | ✅ Pass | 2026-06-06 | ✅ Pass |
| [Acr Pull Failure](../troubleshooting/lab-guides/acr-pull-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Appinsights Connection String Missing](../troubleshooting/lab-guides/appinsights-connection-string-missing.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Azure Files Mount Failure](../troubleshooting/lab-guides/azure-files-mount-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Bicep Deployment Timeout](../troubleshooting/lab-guides/bicep-deployment-timeout.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Cd Reconnect Rbac Conflict](../troubleshooting/lab-guides/cd-reconnect-rbac-conflict.md) | ✅ Pass | ✅ Pass | 2026-04-21 | ✅ Pass |
| [Cold Start Scale To Zero](../troubleshooting/lab-guides/cold-start-scale-to-zero.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Cpu Throttling](../troubleshooting/lab-guides/cpu-throttling.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Custom Domain Tls Renewal](../troubleshooting/lab-guides/custom-domain-tls-renewal.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Dapr Integration](../troubleshooting/lab-guides/dapr-integration.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Dapr Pubsub Failure](../troubleshooting/lab-guides/dapr-pubsub-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Dapr State Store Failure](../troubleshooting/lab-guides/dapr-state-store-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Diagnostic Settings Missing](../troubleshooting/lab-guides/diagnostic-settings-missing.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Docker Hub Rate Limit](../troubleshooting/lab-guides/docker-hub-rate-limit.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Easyauth Entra Id Failure](../troubleshooting/lab-guides/easyauth-entra-id-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Egress Ip Change](../troubleshooting/lab-guides/egress-ip-change.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Emptydir Disk Full](../troubleshooting/lab-guides/emptydir-disk-full.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Event Job Storm](../troubleshooting/lab-guides/event-job-storm.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Github Actions Oidc Failure](../troubleshooting/lab-guides/github-actions-oidc-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Image Size Startup Delay](../troubleshooting/lab-guides/image-size-startup-delay.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Ingress Target Port Mismatch](../troubleshooting/lab-guides/ingress-target-port-mismatch.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Keda No Metrics Returned](../troubleshooting/lab-guides/keda-no-metrics-returned.md) | ➖ No Data | ➖ No Data | — | ➖ Not Tested |
| [Log Analytics Ingestion Gap](../troubleshooting/lab-guides/log-analytics-ingestion-gap.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Managed Identity Key Vault Failure](../troubleshooting/lab-guides/managed-identity-key-vault-failure.md) | ✅ Pass | ✅ Pass | 2026-06-03 | ✅ Pass |
| [Memory Leak Oomkilled](../troubleshooting/lab-guides/memory-leak-oomkilled.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Memory Percentage Vs Keda Utilization](../troubleshooting/lab-guides/memory-percentage-vs-keda-utilization.md) | ✅ Pass | ✅ Pass | 2026-06-02 | ✅ Pass |
| [Min Replicas Cost Surprise](../troubleshooting/lab-guides/min-replicas-cost-surprise.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Multi Arch Image Mismatch](../troubleshooting/lab-guides/multi-arch-image-mismatch.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Multi Region Failover](../troubleshooting/lab-guides/multi-region-failover.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Observability Tracing](../troubleshooting/lab-guides/observability-tracing.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Private Endpoint Dns Failure](../troubleshooting/lab-guides/private-endpoint-dns-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Probe And Port Mismatch](../troubleshooting/lab-guides/probe-and-port-mismatch.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Replica Load Imbalance](../troubleshooting/lab-guides/replica-load-imbalance.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Revision Failover](../troubleshooting/lab-guides/revision-failover.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Revision History Limit](../troubleshooting/lab-guides/revision-history-limit.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Revision Provisioning Failure](../troubleshooting/lab-guides/revision-provisioning-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Scale Rule Mismatch](../troubleshooting/lab-guides/scale-rule-mismatch.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Scheduled Job Missed](../troubleshooting/lab-guides/scheduled-job-missed.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Session Affinity Failure](../troubleshooting/lab-guides/session-affinity-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Startup Degraded Transient Failure](../troubleshooting/lab-guides/startup-degraded-transient-failure.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Subnet Cidr Exhaustion](../troubleshooting/lab-guides/subnet-cidr-exhaustion.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Subscription Quota Exceeded](../troubleshooting/lab-guides/subscription-quota-exceeded.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Traffic Routing Canary](../troubleshooting/lab-guides/traffic-routing-canary.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Udr Nsg Egress Blocked](../troubleshooting/lab-guides/udr-nsg-egress-blocked.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Volume Permission Denied](../troubleshooting/lab-guides/volume-permission-denied.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Websocket Grpc Ingress](../troubleshooting/lab-guides/websocket-grpc-ingress.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Workload Profile Mismatch](../troubleshooting/lab-guides/workload-profile-mismatch.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |
| [Zone Redundancy Best Effort](../troubleshooting/lab-guides/zone-redundancy-best-effort.md) | ➖ Not Tested | ➖ Not Tested | — | ➖ Not Tested |

## How to Update

To mark a tutorial as validated, add a `validation` block to its YAML frontmatter:

```yaml
---
hide:
  - toc
validation:
  az_cli:
    last_tested: 2026-04-09
    cli_version: "2.83.0"
    result: pass
  bicep:
    last_tested: null
    result: not_tested
---
```

Then regenerate this page:

```bash
python3 scripts/generate_validation_status.py
```

!!! info "Validation fields"
    - `result`: `pass`, `fail`, or `not_tested`
    - `last_tested`: ISO date (YYYY-MM-DD) or `null`
    - `cli_version`: Azure CLI version used
    - Tutorials older than 90 days are flagged as **stale**

## See Also

- [Language Guides](../language-guides/index.md)
- [CLI Reference](cli-reference.md)
- [Environment Variables](environment-variables.md)
- [Platform Limits](platform-limits.md)

