# Troubleshooting Azure Container Apps

This section provides a **systematic approach** to identifying and fixing common issues on Azure Container Apps. Whether your container is failing to start or your networking is misconfigured, follow these steps to find the root cause.

!!! tip "Quick Start: App not working?"
    Start with the **[First 10 Minutes](first-10-minutes/index.md)** guide to quickly triage the most common issues like health check failures and port misconfigurations.

## Troubleshooting Areas

-   **[First 10 Minutes](first-10-minutes/index.md)**: A rapid checklist for immediate triage. 
-   **[Playbooks](playbooks/index.md)**: Detailed step-by-step guides for specific error types (e.g., `Revision provisioning failed`, `503 Service Unavailable`, `Log streaming issues`).
-   **[Methodology](methodology/index.md)**: A systematic mental model for troubleshooting Container Apps — separating control-plane issues from data-plane errors.
-   **[KQL Queries](kql/index.md)**: Powerful Log Analytics queries to search system and application logs across your environment.
-   **[Lab Guides](lab-guides/index.md)**: Practice troubleshooting in a controlled environment with pre-built "broken" scenarios.

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
- [KQL Cheatsheet](kql/index.md)
