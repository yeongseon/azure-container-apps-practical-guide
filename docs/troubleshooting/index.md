# Troubleshooting Azure Container Apps

This section provides a **systematic approach** to identifying and fixing common issues on Azure Container Apps. Whether your container is failing to start or your networking is misconfigured, follow these steps to find the root cause.

!!! tip "Quick Start: App not working?"
    Start with the **[First 10 Minutes](first-10-minutes/index.md)** guide to quickly triage the most common issues like health check failures and port misconfigurations.

## Troubleshooting Areas

-   **[First 10 Minutes](first-10-minutes/index.md)**: A rapid ordered checklist for immediate triage.
-   **[Playbooks](playbooks/index.md)**: Fifteen hypothesis-driven incident playbooks grouped by startup, networking, scaling, identity, and platform features.
-   **[Methodology](methodology/index.md)**: A systematic root-cause workflow for revision, replica, identity, and network analysis.
-   **[Detector Map](methodology/detector-map.md)**: Symptom-to-playbook routing tree and error-string mapping table.
-   **[KQL Queries](kql/index.md)**: Fifteen focused query pages for revision, runtime, networking, scaling, identity, Dapr/jobs, and App Insights correlation.
-   **[Lab Guides](lab-guides/index.md)**: Practice troubleshooting in a controlled environment with pre-built broken scenarios.

## Playbook Categories at a Glance

- **Startup and Provisioning**: image pull, revision provisioning, startup, probe timing
- **Ingress and Networking**: ingress reachability, DNS/private endpoint, service connectivity
- **Scaling and Runtime**: HTTP scaling, event scaler mismatch, crash loops and OOM
- **Identity and Configuration**: managed identity and secret/Key Vault references
- **Platform Features**: Dapr sidecar/components, jobs, rollout rollback

## Scope

| Included | Not Included |
| --- | --- |
| Commands, tables, snippets | Long conceptual explanations (see [Platform](../platform/index.md)) |
| Frequent incidents and fixes | End-to-end deployment tutorials (see [Language Guides](../language-guides/index.md)) |
| Runtime defaults and knobs | Day-2 operational guides (see [Operations](../operations/index.md)) |

## Triage Logic

When something goes wrong, ask these questions in order:

1.  **Is the revision provisioned?** Check `az containerapp revision list`.
2.  **Is the replica running?** Check `az containerapp replica list`.
3.  **Is the health probe failing?** Check `System logs` in Log Analytics.
4.  **Is the app crashing?** Check `Console logs` via Log Streaming or Log Analytics.

## See Also

- [Operations Guide](../operations/index.md)
- [Platform - Architecture](../platform/index.md)
- [KQL Queries](kql/index.md)
- [Troubleshooting Playbooks](playbooks/index.md)
- [Detector Map](methodology/detector-map.md)
