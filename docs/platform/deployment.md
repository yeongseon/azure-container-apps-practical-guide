---
description: Azure Container Apps deployment technologies, source-to-revision paths, configuration scopes, and revision behavior.
hide:
  - toc
content_sources:
  diagrams:
    - id: deployment-methods-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact
        - https://learn.microsoft.com/en-us/azure/container-apps/tutorial-deploy-first-app-cli
        - https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec
        - https://learn.microsoft.com/en-us/azure/container-apps/github-actions
        - https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/container-apps-workflows
    - id: change-scope-decision
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: agent
  core_claims:
    - claim: "Revision-scope changes trigger a new revision; application-scope changes apply globally without creating a revision"
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: "In single revision mode, old revision stays active until new revision is ready (zero-downtime)"
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
    - claim: "Artifact deployment supports JAR/WAR files without requiring a Dockerfile"
      source: https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact
      verified: true
    - claim: "Deployment labels allow URL-based routing to specific revisions"
      source: https://learn.microsoft.com/en-us/azure/container-apps/revisions
      verified: true
---

# Deployment Technologies

Azure Container Apps uses a revision-based deployment model where initial creation and revision-scope changes create immutable snapshots of the application template, while application-scope changes update the app without creating a revision. This page explains the available deployment methods, what triggers new revisions, and how deployments behave at the platform level.

## Deployment Methods

Container Apps supports interactive, declarative, and pipeline deployment paths. These tools submit desired app configuration through the Azure management plane. An initial deployment creates the app's first revision; a later update creates a new revision only when it changes revision-scope configuration.

<!-- diagram-id: deployment-methods-flow -->
```mermaid
flowchart TD
    accTitle: Deployment inputs and tools converge on Container Apps desired state
    accDescr: Source code, Java artifacts, container images and declarative definitions enter through Azure CLI, Azure Developer CLI, Bicep or ARM templates, or GitHub Actions. These management paths update a container app. Initial creation produces the first revision; later revision-scope changes produce a new immutable revision, while application-scope changes update the app without a new revision.

    SOURCE["Source code"]
    ARTIFACT["Java artifact<br/>JAR or WAR"]
    IMAGE["Versioned container image"]
    DECLARATION["Declarative desired state<br/>Bicep or ARM template"]

    CLI["Azure CLI<br/>az containerapp up/create/update"]
    AZD["Azure Developer CLI<br/>azd provision and deploy"]
    IAC["Azure Resource Manager<br/>Bicep or ARM deployment"]
    GHA["GitHub Actions<br/>build and deployment workflow"]

    APP["Container app resource<br/>desired configuration"]
    SCOPE{"Initial deployment or<br/>which update scope?"}
    REVISION["First or new revision<br/>immutable template snapshot"]
    GLOBAL["Application configuration updated<br/>no new revision"]

    SOURCE --> CLI
    SOURCE --> AZD
    SOURCE --> GHA
    ARTIFACT --> CLI
    IMAGE --> CLI
    IMAGE --> GHA
    DECLARATION --> IAC

    CLI -->|"Management operation"| APP
    AZD -->|"Provision and deploy"| APP
    IAC -->|"Declarative deployment"| APP
    GHA -->|"Workflow deployment"| APP
    APP --> SCOPE
    SCOPE -->|"Initial or revision-scope"| REVISION
    SCOPE -->|"Application-scope update"| GLOBAL
```

*Figure: Deployment inputs and tools converge on the same Container Apps resource model. Thin arrows are build or management relationships, not runtime request traffic. Tool choice does not determine revision creation; the initial-create versus update scope decision does.*

### Method Comparison

| Method | Image Build | Revision Control | Rollback | Best For |
|---|---|---|---|---|
| `az containerapp up --source` | Platform builds from source | Automatic | Deploy previous source | Quick prototyping |
| `az containerapp up --artifact` | Platform builds from JAR/WAR | Automatic | Deploy previous artifact | Java apps without Dockerfile |
| `az containerapp update --image` | External (you build) | Automatic | Update to previous tag | Standard CI/CD |
| `az containerapp create` | External | Manual | Traffic re-routing | Initial provisioning |
| Bicep / ARM template | External | Declarative | Redeploy previous template | Infrastructure-as-code |
| Azure Developer CLI (`azd`) | Project or pipeline-defined | Declarative project workflow | Redeploy a previous project state | Application plus infrastructure lifecycle |
| GitHub Actions | Pipeline | Pipeline-controlled | Re-run previous workflow | Team-wide CI/CD |
| Azure DevOps | Pipeline | Pipeline-controlled | Re-run previous pipeline | Enterprise CI/CD |

## Source Code Deployment

Deploy directly from application source code without pre-building a container image. The platform uses Buildpacks to create the image automatically.

```bash
az containerapp up \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --environment "$ACA_ENV_NAME" \
    --source "./apps/python"
```

| Command | Why it is used |
|---|---|
| `az containerapp up` | Creates or updates the app from source code. |
| `--name` | Selects the container app name. |
| `--resource-group` | Selects the resource group. |
| `--environment` | Selects the Container Apps environment. |
| `--source` | Supplies the source directory for build and deployment. |

The platform:

1. Detects the language runtime from project files
2. Builds a container image using cloud buildpacks
3. Pushes the image to a managed or specified ACR
4. Creates a new revision with the built image

!!! info "Best for development and prototyping"
    Source deployment is convenient but provides less control over the build process. For production, prefer pre-built images with immutable tags.

## Artifact Deployment

Deploy Java applications (JAR or WAR) without writing a Dockerfile. The platform generates a container image from the artifact.

```bash
az containerapp up \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --environment "$ACA_ENV_NAME" \
    --artifact ./target/app.jar \
    --ingress external \
    --target-port 8080
```

| Command | Why it is used |
|---|---|
| `az containerapp up` | Creates or updates the app from a Java artifact. |
| `--name` | Selects the container app name. |
| `--resource-group` | Selects the resource group. |
| `--environment` | Selects the Container Apps environment. |
| `--artifact` | Supplies the JAR or WAR file without requiring a Dockerfile. |
| `--ingress` | Enables external app ingress. |
| `--target-port` | Sets the port on which the generated container listens. |

This command:

- Creates an ACR if none exists
- Builds a container image from the artifact
- Pushes the image to the registry
- Creates or updates the Container App with a new revision

## Container Image Deployment

The standard production deployment method. Build your image externally, push to a registry, and update the app.

```bash
# Build and push to ACR
az acr build \
    --registry "$ACR_NAME" \
    --image "$APP_NAME:git-$(git rev-parse --short HEAD)" \
    --file "apps/python/Dockerfile" \
    "apps/python"

# Update app to create new revision
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --image "$ACR_NAME.azurecr.io/$APP_NAME:git-$(git rev-parse --short HEAD)"
```

| Command | Why it is used |
|---|---|
| `az acr build` | Builds and pushes the container image to Azure Container Registry. |
| `--registry` | Selects the registry. |
| `--image` | Assigns the image repository and tag. |
| `--file` | Selects the Dockerfile. |
| `git rev-parse` | Resolves the current commit identifier for the immutable image tag. |
| `--short` | Uses the abbreviated commit identifier in the image tag. |
| `az containerapp update` | Updates the existing container app. |
| `--name` | Selects the container app name. |
| `--resource-group` | Selects the resource group. |
| `--image` | Changes the revision template's image and therefore creates a revision. |

## Change Types

Changes to a Container App fall into two categories that determine whether a new revision is created.

<!-- diagram-id: change-scope-decision -->
```mermaid
flowchart TD
    accTitle: Decide whether a Container Apps change creates a revision
    accDescr: First determine whether this is initial app creation. Initial creation produces the first revision. For an update, changes under properties.template are revision-scope and create an immutable revision. Changes under properties.configuration are application-scope, apply to the app without creating a revision, and may still require an operational action such as restarting revisions after a secret value update.

    CHANGE["Create or change a container app"]
    INITIAL{"Initial app creation?"}
    SCOPE{"For an update, which ARM scope changes?"}
    FIRST["Create first revision"]
    TEMPLATE["properties.template<br/>image, containers, scale rules,<br/>probes, revision suffix"]
    CONFIG["properties.configuration<br/>ingress, secrets, registries,<br/>revision mode, traffic"]
    NEWREV["Create new immutable revision"]
    GLOBAL["Update application configuration<br/>no new revision"]
    FOLLOWUP["Apply required operational follow-up<br/>for example restart after secret update"]

    CHANGE --> INITIAL
    INITIAL -->|"Yes"| FIRST
    INITIAL -->|"No"| SCOPE
    SCOPE -->|"Revision scope"| TEMPLATE
    SCOPE -->|"Application scope"| CONFIG
    TEMPLATE --> NEWREV
    CONFIG --> GLOBAL
    GLOBAL --> FOLLOWUP
```

*Figure: Revision creation depends on initial creation or ARM configuration scope, not on whether the caller used CLI, IaC, or a pipeline. The follow-up branch does not mean every application-scope update requires a restart; secret value changes are the example that does.*

### Revision-Scope Changes

These changes create a new revision. They are defined in the `properties.template` section of the resource.

| Parameter | Example |
|---|---|
| Container image | Updating from `myapp:v1` to `myapp:v2` |
| Container configuration | CPU, memory, environment variables in template |
| Scale rules | Min/max replicas, HTTP concurrency, KEDA triggers |
| Revision suffix | Custom revision name suffix |
| Probes | Liveness, readiness, startup probe configuration |
| Init containers | Sidecar and init container changes |

### Application-Scope Changes

These changes apply globally to all revisions without creating a new one. They are defined in the `properties.configuration` section.

| Parameter | Notes |
|---|---|
| Secret values | Revisions must be restarted to pick up new values |
| Revision mode | Single ↔ Multiple |
| Ingress configuration | Turning ingress on/off, traffic splitting rules, labels |
| Registry credentials | Container registry authentication |
| Dapr settings | Dapr component configuration |

!!! warning "Secret changes require restart"
    Updating a secret value is an application-scope change (no new revision), but running replicas will not see the new value until they are restarted.

## Zero-Downtime Deployment

Container Apps ensures zero-downtime in **single revision mode** through a controlled cutover process.

**How it works:**

1. New revision is provisioned and starts health checks
2. New revision scales up to match the previous revision's replica count (respecting min/max)
3. All replicas pass startup and readiness probes
4. Traffic shifts from old revision to new revision
5. Old revision is automatically deactivated

The existing revision continues to receive 100% of traffic until the new revision is fully ready.

In **multiple revision mode** with `latestRevision` set to `true` in traffic splitting rules, traffic also waits for the new revision to become ready before shifting.

## Deployment Labels (Preview)

Labels assign meaningful names to specific revisions, providing dedicated URLs for routing.

| Feature | Description |
|---|---|
| Dedicated URL | Each label gets a unique URL independent of traffic splitting |
| Portable | Move a label between revisions; URL stays the same |
| Independent of traffic split | Label URLs route to their assigned revision regardless of percentage-based routing |
| Exclusive | A label can be assigned to only one revision at a time |

```bash
# Assign a label to a revision
az containerapp revision label add \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --revision "$APP_NAME--v2" \
    --label staging
```

| Command | Why it is used |
|---|---|
| `az containerapp revision label add` | Assigns a named label to a specific revision for dedicated URL routing. |
| `--name` | Selects the container app. |
| `--resource-group` | Selects the resource group. |
| `--revision` | Selects the revision that receives the label. |
| `--label` | Defines the stable label name. |

Common label patterns:

- `staging` — Route QA traffic to a candidate revision
- `canary` — Small percentage of real traffic for validation
- `previous` — Quick access to the last known-good revision

A label name must consist of lowercase alphanumeric characters or dashes, start with an alphabetic character, end with an alphanumeric character, and be at most 64 characters.

## Inactive Revision Management

By default, Container Apps retains up to 100 inactive revisions. You can adjust this limit:

```bash
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --max-inactive-revisions 50
```

| Command | Why it is used |
|---|---|
| `az containerapp update` | Updates application-level configuration. |
| `--name` | Selects the container app. |
| `--resource-group` | Selects the resource group. |
| `--max-inactive-revisions` | Sets the maximum number of inactive revisions to retain. |

Inactive revisions:

- Have no running replicas and incur no compute cost
- Can be reactivated at any time
- Are automatically purged when the inactive count exceeds the limit (oldest first)

## See Also

- [Platform - Revisions Overview](revisions/index.md)
- [Operations - Deployment Workflows](../operations/deployment/index.md)
- [Operations - Deploy with the Azure Developer CLI (azd)](../operations/deployment/azd.md)
- [Best Practices - Revision Strategy](../best-practices/revision-strategy.md)
- [Platform - Scaling](scaling/index.md)

## Sources

- [Update and deploy changes in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Deploy an artifact file to Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/deploy-artifact)
- [Deploy your first container app (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/tutorial-deploy-first-app-cli)
- [Azure Resource Manager API specification for Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/azure-resource-manager-api-spec)
- [Deploy to Azure Container Apps with GitHub Actions (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/github-actions)
- [Deploy to Azure Container Apps with Azure Developer CLI (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/container-apps-workflows)
- [Blue-green deployment in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/blue-green-deployment)
- [Traffic splitting in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
