---
description: Azure Container Apps deployment workflows for source, artifact, image, and infrastructure-as-code releases with revision-aware guardrails.
hide:
  - toc
content_sources:
  diagrams:
    - id: deployment-methods
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/containerapp-up
        - https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
    - id: deployment-workflow-and-release-guardrails
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/
        - https://learn.microsoft.com/en-us/azure/container-apps/tutorial-deploy-first-app-cli
        - https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: "az containerapp up supports --source for cloud build from source code"
      source: https://learn.microsoft.com/en-us/azure/container-apps/tutorial-deploy-first-app-cli
      verified: true
    - claim: "az containerapp up supports --artifact for JAR/WAR deployment without Dockerfile"
      source: https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact
      verified: true
    - claim: "Revision-scope changes create new revisions; application-scope changes do not"
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: "Deployment labels allow routing traffic to specific revisions by name"
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
---
# Deployment Workflows

This guide summarizes practical deployment workflows for Azure Container Apps across CLI, Infrastructure as Code, and CI/CD pipelines.

## Prerequisites

- Azure CLI with `containerapp` extension installed
- An existing Container Apps environment (`$ACA_ENV_NAME`)
- An Azure Container Registry (`$ACR_NAME`) for image-based deployments

## When to Use

| Scenario | Recommended Method |
|---|---|
| Fast iteration in dev/test | `az containerapp up --source` or `--artifact` |
| Production baseline with governance | Bicep / ARM templates |
| Team-wide standard releases | CI/CD pipeline (GitHub Actions) |
| Emergency hotfix | Direct CLI `az containerapp update --image` |

## Deployment Methods

This guide compares four deployment entry paths. CI/CD can orchestrate any of them rather than forming a fifth platform deployment primitive.

<!-- diagram-id: deployment-methods -->
```mermaid
flowchart TD
    accTitle: Deployment entry paths into an Azure Container App
    accDescr: An operator or CI pipeline selects source, Java artifact, prebuilt image, or infrastructure as code. Source and artifact paths build an image before deployment, while image and infrastructure paths reference an image directly. A revision-scope template change creates a new revision.
    ACTOR["Operator or CI/CD pipeline"]
    SOURCE["Local source<br/>az containerapp up --source"]
    ARTIFACT["Java artifact<br/>az containerapp up --artifact"]
    IMAGE["Prebuilt image<br/>create or update --image"]
    IAC["Bicep or ARM<br/>declarative deployment"]
    BUILD["Build image<br/>and publish to registry"]
    APPLY["Apply Container App<br/>configuration and image reference"]
    APP["Container app"]
    REVISION["New revision only when<br/>revision-scope template changes"]
    ACTOR --> SOURCE
    ACTOR --> ARTIFACT
    ACTOR --> IMAGE
    ACTOR --> IAC
    SOURCE --> BUILD
    ARTIFACT --> BUILD
    BUILD --> APPLY
    IMAGE --> APPLY
    IAC --> APPLY
    APPLY --> APP
    APP -.->|"Revision-scope change"| REVISION
```

*Figure: The paths differ in where image build and configuration control occur. Deploying does not always create a revision; only revision-scope changes do.*

### Source Code Deployment

Deploy directly from source code without building a container image locally. Azure builds the image in the cloud using Oryx or a Buildpack.

```bash
az containerapp up \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --environment "$ACA_ENV_NAME" \
  --source "./apps/python"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp up` | Builds or selects an image and deploys a Container App. |
| `--environment` | Selects the Container Apps environment. |
| `--location` | Selects the Azure region. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--source` | Selects the local source directory to build and deploy. |

!!! tip "When to use source deploy"
    Best for rapid prototyping and development. The platform auto-detects the language runtime and builds the image for you.

### Artifact Deployment (JAR / WAR)

Deploy Java artifacts directly without writing a Dockerfile. The platform builds a container image from the artifact automatically.

```bash
az containerapp up \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --environment "$ACA_ENV_NAME" \
  --artifact "./target/myapp.jar"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp up` | Builds or selects an image and deploys a Container App. |
| `--artifact` | Selects the local Java artifact to deploy. |
| `--environment` | Selects the Container Apps environment. |
| `--location` | Selects the Azure region. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |

Supported artifact types:

| Artifact | Extension | Runtime |
|---|---|---|
| JAR | `.jar` | Java (Spring Boot, Quarkus, etc.) |
| WAR | `.war` | Java (Servlet-based) |

!!! warning "Artifact deploy limitations"
    Artifact deployment is for Java applications only. For other languages, use `--source` or build a container image.

### Container Image Deployment

The standard production deployment method. Build and push an image to a registry, then deploy.

```bash
# Build and push to ACR with an immutable tag
IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
az acr build \
  --registry "$ACR_NAME" \
  --image "$APP_NAME:$IMAGE_TAG" \
  --file "apps/python/Dockerfile" \
  "apps/python"

# Deploy or update with the new image
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:$IMAGE_TAG"
```

| Command / Parameter | Purpose |
|---|---|
| `az acr build` | Builds an image in Azure Container Registry and pushes the tagged result. |
| `--file` | Selects the Dockerfile used for the build. |
| `--image` | Selects the container image or output image tag. |
| `--registry` | Selects the Azure Container Registry. |
| `az containerapp update` | Updates the existing Container App. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |

Prefer immutable tags for release traceability, and maintain a stable alias tag only for non-production testing.

### Bicep / ARM Deployment

IaC deployments keep environment, identity, and app configuration consistent.

```bash
az deployment group create \
  --resource-group "$RG" \
  --template-file "infra/main.bicep" \
  --parameters "baseName=myapp" "location=$LOCATION"
```

| Command / Parameter | Purpose |
|---|---|
| `az deployment group create` | Deploys a Bicep or ARM template to a resource group. |
| `--parameters` | Supplies template parameter values. |
| `--resource-group` | Selects the resource group. |
| `--template-file` | Selects the Bicep or ARM template file. |

Use `what-if` before production applies:

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file "infra/main.bicep" \
  --parameters "baseName=myapp" "location=$LOCATION"
```

| Command / Parameter | Purpose |
|---|---|
| `az deployment group what-if` | Previews resource-group deployment changes. |
| `--parameters` | Supplies template parameter values. |
| `--resource-group` | Selects the resource group. |
| `--template-file` | Selects the Bicep or ARM template file. |

!!! warning "Run what-if before production IaC applies"
    `az deployment group what-if` should be mandatory for production environments to prevent accidental networking, identity, or ingress drift.

## CI/CD with GitHub Actions

Use GitHub Actions to build images, push to ACR, and deploy to Container Apps in one pipeline.

Typical stages:

1. Lint and test application code.
2. Build container image.
3. Push image to ACR.
4. Deploy or update Container App / Job.
5. Verify health endpoint and revision state.

Use workload identity federation where possible to avoid long-lived service principal secrets.

## Revision Behavior and Zero-Downtime Deployments

Every deployment that changes revision-scope properties creates a **new revision**. In single-revision mode, the platform automatically performs a zero-downtime cutover to the new revision. In multiple-revision mode, you must explicitly manage traffic routing between revisions.

### Revision-Scope vs Application-Scope Changes

| Scope | Creates New Revision? | Examples |
|---|---|---|
| Revision-scope | Yes | Container image, environment variables, resources (CPU/memory), scale rules, probes |
| Application-scope | No | Traffic splitting, custom domains, authentication, managed identity |

### Traffic Splitting for Progressive Rollout

```bash
# Send 20% traffic to new revision for canary testing
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$APP_NAME--new-rev=20" "$APP_NAME--stable-rev=80"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Sets revision or label traffic weights. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--revision-weight` | Assigns traffic percentages by revision name. |

### Deployment Labels (Preview)

Deployment labels allow you to route traffic to a specific revision by a stable label name, independent of revision name.

```bash
# Assign a label to a specific revision
az containerapp revision label add \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --label "canary" \
  --revision "$APP_NAME--new-rev"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp revision label add` | Assigns a revision label to a specific revision. |
| `--label` | Sets the revision label name. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--revision` | Selects a specific revision. |

The labeled revision becomes accessible at `<label>.<app-fqdn>` for testing before promoting traffic.

## Rollback Procedures

### Quick Rollback via Traffic Shift

Route 100% traffic back to the previous stable revision:

```bash
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$APP_NAME--stable-rev=100"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp ingress traffic set` | Sets revision or label traffic weights. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--revision-weight` | Assigns traffic percentages by revision name. |

### Reactivate a Deactivated Revision

If the previous revision has been deactivated, reactivate it first:

```bash
az containerapp revision activate \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$APP_NAME--stable-rev"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp revision activate` | Activates a specific revision. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--revision` | Selects a specific revision. |

### Redeploy a Known-Good Image

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:last-known-good"
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the existing Container App. |
| `--image` | Selects the container image or output image tag. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |

## Inactive Revision Cleanup

Old revisions consume no compute but remain listed. Limit inactive revisions to reduce clutter:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --max-inactive-revisions 5
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp update` | Updates the existing Container App. |
| `--max-inactive-revisions` | Sets the maximum retained inactive revisions. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |

!!! tip "Revision cleanup"
    Setting `--max-inactive-revisions` automatically purges the oldest inactive revisions when the count exceeds the limit. This does not affect active revisions receiving traffic.

## Deployment Workflow and Release Guardrails

The gated workflow below requires **multiple revision mode** with ingress traffic pinned to the stable revision. Single revision mode automatically moves traffic after platform readiness succeeds, so it cannot hold the candidate behind the later smoke-test and SLO gate.

<!-- diagram-id: deployment-workflow-and-release-guardrails -->
```mermaid
flowchart TD
    accTitle: Gate a revision release before traffic promotion
    accDescr: In multiple revision mode with traffic pinned to stable, a merged change is tested and published as an immutable image, then deployed as a zero-traffic revision candidate. Startup and readiness must succeed before release checks. Failed readiness leaves the stable route in place; failed release checks keep or restore stable traffic; passed checks permit controlled promotion.
    MODE["Multiple revision mode<br/>stable traffic pinned"] --> COMMIT["Merge reviewed change"]
    COMMIT --> BUILD["Build, test, scan,<br/>and publish immutable image"]
    BUILD --> DEPLOY["Deploy revision candidate<br/>with stable route retained"]
    DEPLOY --> READY{"Startup and readiness<br/>checks succeed?"}
    READY -->|"No"| BLOCK["Keep existing route<br/>inspect failed candidate"]
    READY -->|"Yes"| VALIDATE["Run smoke tests and<br/>revision-specific SLO checks"]
    VALIDATE --> GATE{"Release gates pass?"}
    GATE -->|"No"| ROLLBACK["Restore stable traffic<br/>open incident and fix"]
    GATE -->|"Yes"| PROMOTE["Promote traffic<br/>in controlled steps"]
    PROMOTE --> CONFIDENCE["Observe confidence window<br/>retain rollback path"]
```

*Figure: Platform readiness and operator-defined release gates are separate decisions in multiple revision mode. Do not configure this flow with `latestRevision: true`; keep ingress traffic pinned to the stable revision until the later gate approves promotion.*

| Deployment Method | Strength | Tradeoff | Best Operational Use |
|---|---|---|---|
| Source deploy (`--source`) | No Dockerfile needed | Less control over build | Prototyping and dev environments |
| Artifact deploy (`--artifact`) | No Dockerfile for Java | Java-only | Java apps without container expertise |
| Direct CLI (`az containerapp update --image`) | Fastest change path | Higher drift risk | Hotfixes and smoke deployments |
| Bicep (`az deployment group create`) | Deterministic infra state | Requires template discipline | Production baseline and governance |
| CI/CD pipeline | Approval + traceability + repeatability | More setup overhead | Team-wide standard release workflow |

!!! tip "Prefer immutable image tags per deployment"
    Use tags like `git-<sha>` or date-based release tags to guarantee revision traceability and safe rollback.

## Deployment Checklist

- Container image built from pinned base image and scanned.
- Revision mode and traffic strategy validated.
- Health probes configured and verified.
- Managed identity and secret references resolved.
- Post-deploy smoke test completed.
- Rollback path documented and tested.

### Progressive Rollout Example

```bash
export IMAGE_TAG="git-$(git rev-parse --short HEAD)"
export IMAGE_NAME="$ACR_NAME.azurecr.io/$APP_NAME:$IMAGE_TAG"

az acr build \
  --registry "$ACR_NAME" \
  --image "$APP_NAME:$IMAGE_TAG" \
  --file "apps/python/Dockerfile" \
  "apps/python"

az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$IMAGE_NAME"

az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command / Parameter | Purpose |
|---|---|
| `az acr build` | Builds an image in Azure Container Registry and pushes the tagged result. |
| `--file` | Selects the Dockerfile used for the build. |
| `--image` | Selects the container image or output image tag. |
| `--registry` | Selects the Azure Container Registry. |
| `az containerapp update` | Updates the existing Container App. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `az containerapp revision list` | Lists revisions for the selected Container App. |
| `--output` | Selects the command output format. |

### Post-Deployment Acceptance Checks

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type console \
  --follow false

az containerapp ingress traffic show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

| Command / Parameter | Purpose |
|---|---|
| `az containerapp logs show` | Reads Container App logs. |
| `--follow` | Controls whether log output continues streaming. |
| `--name` | Selects the named Azure resource. |
| `--resource-group` | Selects the resource group. |
| `--type` | Selects the log type. |
| `az containerapp ingress traffic show` | Shows the current ingress traffic allocation. |
| `--output` | Selects the command output format. |

## See Also

- [Deploy with the Azure Developer CLI (azd)](azd.md)
- [Deployment (Platform)](../../platform/deployment.md)
- [Revision Strategy (Best Practices)](../../best-practices/revision-strategy.md)
- [Revisions (Platform)](../../platform/revisions/index.md)
- [Language Guides](../../language-guides/index.md)
- [Revision Management](../revision-management/index.md)
- [Recovery and Incident Readiness](../recovery/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Deploy to Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/tutorial-deploy-first-app-cli)
- [Template deployment what-if - Azure Resource Manager](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-what-if)
- [Deploy from an artifact (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact)
- [Revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
