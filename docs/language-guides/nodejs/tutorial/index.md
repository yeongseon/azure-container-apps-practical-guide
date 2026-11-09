---
description: Follow the seven-step Node.js path from local Express container development through Azure deployment, automation, and revision traffic management.
content_sources:
  diagrams:
    - id: tutorial-progression
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud
        - https://learn.microsoft.com/en-us/azure/container-apps/containers#configuration
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# Node.js Tutorial Index

This tutorial path walks you from local development to safe traffic shifting for Node.js apps on Azure Container Apps.

## Prerequisites

Before starting, install and verify:

- Node.js 20+
- Docker
- Azure CLI

## Tutorial Progression

<!-- diagram-id: tutorial-progression -->
```mermaid
flowchart TD
    accTitle: Node.js tutorial progression
    accDescr: Seven modules progress from building an Express container locally through deployment, configuration, observability, infrastructure as code, CI/CD, and revision traffic management.
    S01["01 Local development<br/>build and test Node.js image"]
    S02["02 First deploy<br/>publish and verify"]
    S03["03 Configuration<br/>environment and secrets"]
    S04["04 Logging and monitoring<br/>logs, metrics, and traces"]
    S05["05 Infrastructure as code<br/>Bicep lifecycle"]
    S06["06 CI/CD<br/>automated image delivery"]
    S07["07 Revisions and traffic<br/>safe production rollout"]
    S01 -->|"Local image is healthy"| S02
    S02 -->|"Running revision"| S03
    S03 -->|"Runtime settings applied"| S04
    S04 -->|"Deployment is observable"| S05
    S05 -->|"Infrastructure is repeatable"| S06
    S06 -->|"Delivery is automated"| S07
```

*Figure: Complete each Node.js module in order; every step establishes the prerequisite used by the next production-readiness activity.*

## Steps

| Step | Title | Purpose |
|---|---|---|
| [01-local-development](./01-local-development.md) | Local Development | Build and run the app locally with Docker. |
| [02-first-deploy](./02-first-deploy.md) | First Deploy | Publish the container image and create the first Container App. |
| [03-configuration](./03-configuration.md) | Configuration | Set environment variables and secrets safely. |
| [04-logging-monitoring](./04-logging-monitoring.md) | Logging & Monitoring | Collect logs, metrics, and traces for the app. |
| [05-infrastructure-as-code](./05-infrastructure-as-code.md) | Infrastructure as Code | Provision the environment with Bicep. |
| [06-ci-cd](./06-ci-cd.md) | CI/CD | Automate build and deployment with GitHub Actions. |
| [07-revisions-traffic](./07-revisions-traffic.md) | Revisions & Traffic | Use revisions and traffic splitting for safe releases. |

### Verify in Azure Portal

![Resource group|rg-aca-basics-d38538|Status|Succeeded|Location|Korea Central|Subscription|Visual Studio Enterprise Subscription|Subscription ID|00000000-0000-0000-0000-000000000000|Environment type|Workload profiles|Static IP|4.230.156.3|Applications|7|KEDA version|2.18.1|Dapr version|1.16.4-msft.7](../../../assets/language-guides/nodejs/tutorial/index-environment-overview-blade.png)

**[Observed]** `Microsoft Azure (Preview)`. `Report a bug`. `Search resources, services, and docs (G+/)`. `Copilot`. `Home`. `Search`. `cae-basics-d38538`. `Container Apps Environment`. `Refresh`. `Delete`. `Essentials`. `Resource group (move)`. `rg-aca-basics-d38538`. `Status`. `Succeeded`. `Location (move)`. `Korea Central`. `Subscription (move)`. `Visual Studio Enterprise Subscription`. `Subscription ID`. `00000000-0000-0000-0000-000000000000`. `Aspire Dashboard`. `Not yet active (set up)`. `Tags (edit)`. `Add tags`. `Environment type`. `Workload profiles`. `Static IP`. `4.230.156.3`. `Applications`. `7`. `KEDA version`. `2.18.1`. `Dapr version`. `1.16.4-msft.7`. `View Cost`. `JSON View`. `Applications`. `Monitoring`. `Tutorials`. `Name`. `App Type`. `Resource Group`. `ca-sample-d38538`. `Container App`. `cj-event-d38538`. `Container App Job`. `ca-nodejs-d38538`. `ca-dotnet-d38538`. `ca-java-d38538`. `cj-scheduled-d38538`. `cj-sample-d38538`. `Overview`. `Activity log`. `Access control (IAM)`. `Tags`. `Diagnose and solve problems`. `Resource visualizer`. `Settings`. `Dapr components`. `Certificates`. `Quota`. `Workload profiles`. `Networking`. `Volume mounts`. `Identity`. `Planned Maintenance`. `Locks`. `Apps`. `Services`. `Monitoring`. `Automation`. `Help`.

**[Inferred]** The `Container App` row `ca-nodejs-d38538` in the `Applications` tab appears consistent with the Container App created by [Steps](#steps) Step `02-first-deploy`, whose Purpose column states "Publish the container image and create the first Container App". The `Environment type` value `Workload profiles` appears consistent with the environment that [Steps](#steps) Step `05-infrastructure-as-code` provisions, whose Purpose column states "Provision the environment with Bicep". The `Resource group` value `rg-aca-basics-d38538` appears consistent with the resource group that hosts the environment provisioned in [Steps](#steps) Step `05-infrastructure-as-code`, whose Purpose column states "Provision the environment with Bicep". The `Status` value `Succeeded` appears consistent with the healthy provisioning end-state targeted by the Bicep run in [Steps](#steps) Step `05-infrastructure-as-code`.

**[Not Proven]** Additional tutorial step output and CLI command output from earlier steps are not visible on this view.

## Related Guides

- [Node.js guide overview](../index.md)
- [Node.js runtime reference](../nodejs-runtime.md)
- [Node.js recipes index](../recipes/index.md)

## See Also

- [Tutorial index](index.md)
- [Language guides](../../index.md)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/quickstart-code-to-cloud)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/containers#configuration)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
