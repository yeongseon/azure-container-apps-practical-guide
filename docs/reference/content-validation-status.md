---
content_sources:
  references:
    - type: self-generated
      justification: Auto-generated dashboard tracking content validation status
---

# Content Validation Status

This page tracks `content_validation` metadata for **in-scope factual-claim documents** under `docs/best-practices/`, `docs/operations/`, `docs/platform/`, `docs/troubleshooting/`. Pages outside this scope — navigation indexes (`docs/best-practices/index.md`, `docs/operations/deployment/index.md`, `docs/operations/index.md`, `docs/platform/index.md`, `docs/troubleshooting/first-10-minutes/index.md`, `docs/troubleshooting/index.md`, `docs/troubleshooting/playbooks/index.md`), reference-lookup KQL packs and lab guides (`docs/troubleshooting/kql/`, `docs/troubleshooting/lab-guides/`), tutorials, language guides, and start-here landing pages — are not counted here, even when legacy `content_validation` blocks exist on them (the cleanup tool only removes tautological placeholder claims). See `scripts/lib/content_scope.py` for the executable scope definition.

## Summary

*Generated: 2026-07-03*

| Content Type | Total | Verified | Pending | Unverified | No Metadata |
|---|---:|---:|---:|---:|---:|
| Mermaid Diagrams | 453 | 453 | 0 | 0 | 0 |
| In-Scope Factual-Claim Documents | 156 | 107 | 39 | 0 | 10 |

!!! warning "Validation In Progress"
    10 in-scope document(s) need `content_validation` metadata added.

<!-- diagram-id: content-validation-status-pie -->
```mermaid
pie title In-Scope Document Validation Status
    "Verified" : 107
    "Pending Review" : 39
    "No Metadata" : 10
```

## By Section

### Platform

| Document | Has Sources | Status | Claims | Last Reviewed |
|---|---|---|---|---|
| [Acr Network Path Selection](../platform/networking/acr-network-path-selection.md) | ✅ | ✅ Verified | 4/4 | 2026-06-05 |
| [Application Gateway Integration](../platform/networking/application-gateway-integration.md) | ✅ | ✅ Verified | 6/6 | 2026-07-03 |
| [Consumption Plan](../platform/environments/consumption-plan.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Cost Optimization](../platform/reliability/cost-optimization.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Cpu Memory Scaler](../platform/scaling/cpu-memory-scaler.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Custom Scalers](../platform/scaling/custom-scalers.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Customer Managed Keys](../platform/security/customer-managed-keys.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Dedicated Gpu Profiles](../platform/environments/dedicated-gpu-profiles.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Deployment](../platform/deployment.md) | ✅ | ✅ Verified | 4/4 | 2026-04-21 |
| [Deployment Scenarios](../platform/deployment-scenarios.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Easy Auth](../platform/identity-and-secrets/easy-auth.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Egress Control](../platform/networking/egress-control.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Event Driven Jobs](../platform/jobs/event-driven-jobs.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Event Scalers](../platform/scaling/event-scalers.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Execution Lifecycle](../platform/jobs/execution-lifecycle.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Health Recovery](../platform/reliability/health-recovery.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Http Scaler](../platform/scaling/http-scaler.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Image Security](../platform/security/image-security.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Index](../platform/security/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../platform/environments/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-26 |
| [Index](../platform/networking/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../platform/storage/index.md) | ✅ | ✅ Verified | 5/5 | 2026-05-01 |
| [Index](../platform/architecture/index.md) | ✅ | ✅ Verified | 4/4 | 2026-04-27 |
| [Index](../platform/scaling/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Index](../platform/revisions/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Index](../platform/jobs/index.md) | ✅ | ⚠️ Pending Review | 3/3 | 2026-04-26 |
| [Ingress](../platform/networking/ingress.md) | ✅ | ✅ Verified | 5/5 | 2026-04-25 |
| [Ingress Client Certificates](../platform/security/ingress-client-certificates.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Jobs Vs Apps](../platform/jobs/jobs-vs-apps.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Key Vault](../platform/identity-and-secrets/key-vault.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Lifecycle](../platform/revisions/lifecycle.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Limits And Quotas](../platform/environments/limits-and-quotas.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Managed Identity](../platform/identity-and-secrets/managed-identity.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Manual Jobs](../platform/jobs/manual-jobs.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Migration](../platform/environments/migration.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Mtls](../platform/security/mtls.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Network Isolation](../platform/security/network-isolation.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Networking And Cidr](../platform/environments/networking-and-cidr.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Plans And Workload Profiles](../platform/environments/plans-and-workload-profiles.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Private Endpoints](../platform/networking/private-endpoints.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Resource Relationships](../platform/architecture/resource-relationships.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Revision Modes](../platform/revisions/revision-modes.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Scaling Rules Reference](../platform/scaling/scaling-rules-reference.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Scheduled Jobs](../platform/jobs/scheduled-jobs.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Secrets](../platform/security/secrets.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Security Operations](../platform/identity-and-secrets/security-operations.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Service To Service](../platform/networking/service-to-service.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Traffic Split](../platform/revisions/traffic-split.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Vnet Integration](../platform/networking/vnet-integration.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Workload Profiles](../platform/environments/workload-profiles.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |

### Best Practices

| Document | Has Sources | Status | Claims | Last Reviewed |
|---|---|---|---|---|
| [Anti Patterns](../best-practices/anti-patterns.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Availability And Non Guarantees](../best-practices/availability-and-non-guarantees.md) | ✅ | ✅ Verified | 5/5 | 2026-06-12 |
| [Blue Green Deployment](../best-practices/blue-green-deployment.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Canary Deployment](../best-practices/canary-deployment.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Compliance Baseline](../best-practices/compliance-baseline.md) | ✅ | ✅ Verified | 4/4 | 2026-04-25 |
| [Container Design](../best-practices/container-design.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Cost](../best-practices/cost.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Environment Design](../best-practices/environment-design.md) | ✅ | ✅ Verified | 4/4 | 2026-04-26 |
| [Identity And Secrets](../best-practices/identity-and-secrets.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Image Security](../best-practices/image-security.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Job Design](../best-practices/job-design.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Jobs](../best-practices/jobs.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Mtls](../best-practices/mtls.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Networking](../best-practices/networking.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Reliability](../best-practices/reliability.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Revision Strategy](../best-practices/revision-strategy.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Scaling](../best-practices/scaling.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Security](../best-practices/security.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |

### Operations

| Document | Has Sources | Status | Claims | Last Reviewed |
|---|---|---|---|---|
| [Byo Certificates](../operations/custom-domains/byo-certificates.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Diagnostic Settings](../operations/logging/diagnostic-settings.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-25 |
| [Index](../operations/health-probes/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Index](../operations/custom-domains/index.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Index](../operations/recovery/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/secret-rotation/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/disaster-recovery/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Index](../operations/alerts/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/scaling/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/jobs/index.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Index](../operations/monitoring/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/image-pull-and-registry/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/revision-management/index.md) | ✅ | ❓ No Metadata | — | — |
| [Index](../operations/logging/index.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Internal Ingress On Prem Dns](../operations/deployment/internal-ingress-on-prem-dns.md) | ✅ | ✅ Verified | 5/5 | 2026-05-18 |
| [Log Analytics Queries](../operations/logging/log-analytics-queries.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Log Streaming](../operations/logging/log-streaming.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-25 |
| [Managed Certificates](../operations/custom-domains/managed-certificates.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Metric Alerts By Incident Question](../operations/alerts/metric-alerts-by-incident-question.md) | ✅ | ✅ Verified | 3/3 | 2026-06-05 |
| [Min Replica Change Impact](../operations/scaling/min-replica-change-impact.md) | ✅ | ✅ Verified | 3/3 | 2026-05-18 |
| [Multi Region Deployment](../operations/disaster-recovery/multi-region-deployment.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Networking](../operations/deployment/networking.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Probe Tuning](../operations/health-probes/probe-tuning.md) | ✅ | ✅ Verified | 2/2 | 2026-04-25 |
| [Troubleshooting](../operations/jobs/troubleshooting.md) | ✅ | ⚠️ Pending Review | 2/2 | 2026-04-26 |
| [Use Uami For Acr And Reconnect Cd](../operations/image-pull-and-registry/use-uami-for-acr-and-reconnect-cd.md) | ✅ | ✅ Verified | 3/3 | 2026-05-06 |
| [Zone Redundancy](../operations/disaster-recovery/zone-redundancy.md) | ✅ | ✅ Verified | 4/4 | 2026-06-08 |

### Troubleshooting

| Document | Has Sources | Status | Claims | Last Reviewed |
|---|---|---|---|---|
| [Appgw To Internal Aca Nsg Destination](../troubleshooting/playbooks/ingress-and-networking/appgw-to-internal-aca-nsg-destination.md) | ✅ | ✅ Verified | 4/4 | 2026-07-03 |
| [Appinsights Connection String Missing](../troubleshooting/playbooks/observability/appinsights-connection-string-missing.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Architecture Overview](../troubleshooting/architecture-overview.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Azure Files Mount Failure](../troubleshooting/playbooks/storage-and-volumes/azure-files-mount-failure.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Bad Revision Rollout And Rollback](../troubleshooting/playbooks/platform-features/bad-revision-rollout-and-rollback.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Bicep Deployment Timeout](../troubleshooting/playbooks/deployment-and-cicd/bicep-deployment-timeout.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Cd Rbac Role Assignment Conflict](../troubleshooting/playbooks/identity-and-configuration/cd-rbac-role-assignment-conflict.md) | ✅ | ✅ Verified | 3/3 | 2026-04-23 |
| [Cli Reference](../troubleshooting/first-10-minutes/cli-reference.md) | ✅ | ✅ Verified | 5/5 | 2026-04-12 |
| [Container App Job Execution Failure](../troubleshooting/playbooks/platform-features/container-app-job-execution-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Container Start Failure](../troubleshooting/playbooks/startup-and-provisioning/container-start-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Cpu Throttling](../troubleshooting/playbooks/scaling-and-runtime/cpu-throttling.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Crashloop Oom And Resource Pressure](../troubleshooting/playbooks/scaling-and-runtime/crashloop-oom-and-resource-pressure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Custom Domain Tls Renewal](../troubleshooting/playbooks/networking-advanced/custom-domain-tls-renewal.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Dapr Pubsub Failure](../troubleshooting/playbooks/platform-features/dapr-pubsub-failure.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Dapr Sidecar Or Component Failure](../troubleshooting/playbooks/platform-features/dapr-sidecar-or-component-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Dapr State Store Failure](../troubleshooting/playbooks/platform-features/dapr-state-store-failure.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Decision Tree](../troubleshooting/decision-tree.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Detector Map](../troubleshooting/methodology/detector-map.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Diagnostic Settings Missing](../troubleshooting/playbooks/observability/diagnostic-settings-missing.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-06-22 |
| [Docker Hub Rate Limit](../troubleshooting/playbooks/startup-and-provisioning/docker-hub-rate-limit.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Easyauth Entra Id Failure](../troubleshooting/playbooks/platform-features/easyauth-entra-id-failure.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Egress Ip Change](../troubleshooting/playbooks/networking-advanced/egress-ip-change.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Emptydir Disk Full](../troubleshooting/playbooks/storage-and-volumes/emptydir-disk-full.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Environment Variables](../troubleshooting/first-10-minutes/environment-variables.md) | ✅ | ✅ Verified | 3/3 | 2026-04-12 |
| [Event Job Storm](../troubleshooting/playbooks/platform-features/event-job-storm.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Event Scaler Mismatch](../troubleshooting/playbooks/scaling-and-runtime/event-scaler-mismatch.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Evidence Map](../troubleshooting/evidence-map.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Github Actions Oidc Failure](../troubleshooting/playbooks/deployment-and-cicd/github-actions-oidc-failure.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Http Scaling Not Triggering](../troubleshooting/playbooks/scaling-and-runtime/http-scaling-not-triggering.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Image Pull Failure](../troubleshooting/playbooks/startup-and-provisioning/image-pull-failure.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Image Size Startup Delay](../troubleshooting/playbooks/startup-and-provisioning/image-size-startup-delay.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Index](../troubleshooting/methodology/index.md) | ✅ | ❓ No Metadata | — | — |
| [Ingress Not Reachable](../troubleshooting/playbooks/ingress-and-networking/ingress-not-reachable.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Internal Dns And Private Endpoint Failure](../troubleshooting/playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Keda No Metrics Returned](../troubleshooting/playbooks/scaling-and-runtime/keda-no-metrics-returned.md) | ✅ | ✅ Verified | 3/3 | 2026-06-05 |
| [Log Analytics Ingestion Gap](../troubleshooting/playbooks/observability/log-analytics-ingestion-gap.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Managed Identity Auth Failure](../troubleshooting/playbooks/identity-and-configuration/managed-identity-auth-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Memory Leak Oomkilled](../troubleshooting/playbooks/scaling-and-runtime/memory-leak-oomkilled.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Memory Percentage Vs Keda Utilization](../troubleshooting/playbooks/scaling-and-runtime/memory-percentage-vs-keda-utilization.md) | ✅ | ✅ Verified | 4/4 | 2026-06-02 |
| [Mental Model](../troubleshooting/mental-model.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Min Replicas Cost Surprise](../troubleshooting/playbooks/cost-and-quota/min-replicas-cost-surprise.md) | ✅ | ✅ Verified | 3/3 | 2026-04-29 |
| [Mtls Failures](../troubleshooting/playbooks/mtls-failures.md) | ✅ | ✅ Verified | 3/3 | 2026-04-25 |
| [Multi Arch Image Mismatch](../troubleshooting/playbooks/startup-and-provisioning/multi-arch-image-mismatch.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Multi Region Failover](../troubleshooting/playbooks/platform-features/multi-region-failover.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Platform Limits](../troubleshooting/first-10-minutes/platform-limits.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Private Endpoint Dns Failure](../troubleshooting/playbooks/networking-advanced/private-endpoint-dns-failure.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Probe Failure And Slow Start](../troubleshooting/playbooks/startup-and-provisioning/probe-failure-and-slow-start.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Quick Diagnosis Cards](../troubleshooting/quick-diagnosis-cards.md) | ✅ | ✅ Verified | 4/4 | 2026-04-12 |
| [Replica Load Imbalance](../troubleshooting/playbooks/scaling-and-runtime/replica-load-imbalance.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Revision History Limit](../troubleshooting/playbooks/deployment-and-cicd/revision-history-limit.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Revision Provisioning Failure](../troubleshooting/playbooks/startup-and-provisioning/revision-provisioning-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Scheduled Job Missed](../troubleshooting/playbooks/platform-features/scheduled-job-missed.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Secret And Key Vault Reference Failure](../troubleshooting/playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Service To Service Connectivity Failure](../troubleshooting/playbooks/ingress-and-networking/service-to-service-connectivity-failure.md) | ✅ | ✅ Verified | 2/2 | 2026-04-12 |
| [Session Affinity Failure](../troubleshooting/playbooks/networking-advanced/session-affinity-failure.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Subnet Cidr Exhaustion](../troubleshooting/playbooks/networking-advanced/subnet-cidr-exhaustion.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Subscription Quota Exceeded](../troubleshooting/playbooks/cost-and-quota/subscription-quota-exceeded.md) | ✅ | ✅ Verified | 3/3 | 2026-04-29 |
| [Udr Nsg Egress Blocked](../troubleshooting/playbooks/networking-advanced/udr-nsg-egress-blocked.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Volume Permission Denied](../troubleshooting/playbooks/storage-and-volumes/volume-permission-denied.md) | ✅ | ⚠️ Pending Review | 0/3 | 2026-04-29 |
| [Websocket Grpc Ingress](../troubleshooting/playbooks/networking-advanced/websocket-grpc-ingress.md) | ✅ | ⚠️ Pending Review | 0/2 | 2026-04-29 |
| [Workload Profile Mismatch](../troubleshooting/playbooks/cost-and-quota/workload-profile-mismatch.md) | ✅ | ✅ Verified | 3/3 | 2026-04-29 |
| [Zone Redundancy Best Effort](../troubleshooting/playbooks/platform-features/zone-redundancy-best-effort.md) | ✅ | ✅ Verified | 4/4 | 2026-06-08 |

## Validation Categories

### Source Types

| Type | Description | Allowed? |
|---|---|---|
| `mslearn` | Content directly from or based on Microsoft Learn | Yes |
| `mslearn-adapted` | Microsoft Learn content adapted for this guide | Yes, with source URL |
| `self-generated` | Original content created for this guide | Requires justification |
| `community` | From community sources | Not for core content |
| `unknown` | Source not documented | Must be validated |

### Validation Status

| Status | Description |
|---|---|
| `verified` | All core claims traced to Microsoft Learn sources |
| `pending_review` | Document exists but claims need source verification |
| `unverified` | New document, no validation performed |

## How to Add Validation

Before adding metadata, confirm the page is in scope. The block is required ONLY for factual-claim pages under `docs/platform/`, `docs/best-practices/`, `docs/operations/`, and `docs/troubleshooting/` (excluding `troubleshooting/kql/`, `troubleshooting/lab-guides/`, and navigation landing pages listed in `scripts/lib/content_scope.NAVIGATION_INDEXES`).

For an in-scope page, add a `content_validation` block to its frontmatter:

```yaml
---
content_sources:
  references:
    - type: mslearn-adapted
      url: https://learn.microsoft.com/en-us/azure/container-apps/...
content_validation:
  status: verified
  last_reviewed: 2026-04-12
  reviewer: ai-agent
  core_claims:
    - claim: "Container Apps supports KEDA-based autoscaling on HTTP traffic, CPU, memory, and custom metrics."
      source: https://learn.microsoft.com/en-us/azure/container-apps/scale-app
      verified: true
---
```

Each `core_claim` MUST be a verifiable factual assertion about Azure Container Apps behavior (a documented limit, default, or feature). Meta-statements such as "this page uses Microsoft Learn as the primary source basis" are tautological and rejected — the marker text `primary source basis` triggers a fail-fast in this generator.

Then regenerate this page:

```bash
python3 scripts/generate_content_validation_status.py
```

## See Also

- [CLI Reference](cli-reference.md)
- [Platform Limits](platform-limits.md)

