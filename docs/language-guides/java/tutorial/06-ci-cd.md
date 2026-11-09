---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link
    - id: ci-cd-workflow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/github-actions
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 06 - CI/CD with GitHub Actions

Automating the build and deployment of your Spring Boot application ensures consistent, repeatable releases to Azure Container Apps. This guide covers how to set up a GitHub Actions workflow to build, push, and deploy your Java app on every commit.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet and private ACR access using managed identity.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "10px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 55}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Java tutorial
    accDescr: Client requests and responses pass through managed ingress to Java replicas. The customer VNet associates with the environment and ACR private endpoint and links the endpoint's private DNS zone. Managed identity is assigned to the app, and platform provisioning exchanges image pull requests and layer responses with ACR through that endpoint.
    CALLER(["Client"])
    VNET["VNet + PE<br/>subnet"]
    IDENTITY["Managed identity"]
    PE_ACR["ACR PE"]
    ACR["ACR"]
    DNS["ACR DNS zone"]
    subgraph ENV["ACA environment"]
        INGRESS["Ingress"]
        APP["Container app<br/>Java"]
        REVISION["Revision config"]
        REPLICAS["Replicas"]
        PLATFORM["Provisioning<br/>(platform)"]
    end
    CALLER ~~~ INGRESS ~~~ REPLICAS ~~~ REVISION ~~~ APP ~~~ IDENTITY ~~~ ACR ~~~ PE_ACR ~~~ PLATFORM ~~~ DNS ~~~ VNET
    CALLER ==>|"Request"| INGRESS
    INGRESS ==>|"Response"| CALLER
    INGRESS ==>|"Request"| REPLICAS
    REPLICAS ==>|"Response"| INGRESS
    VNET -.-> ENV
    VNET -.-> PE_ACR
    DNS -.-> VNET
    APP -.-> IDENTITY
    IDENTITY -.-> ACR
    APP -.-> REVISION
    REVISION -.-> REPLICAS
    PLATFORM -.-> REVISION
    PLATFORM ==>|"Pull"| PE_ACR
    PE_ACR ==>|"Pull"| ACR
    ACR ==>|"Layers"| PE_ACR
    PE_ACR ==>|"Layers"| PLATFORM
    PE_ACR -.-> DNS
```

*Figure: Client traffic crosses managed ingress to Java replicas. The customer VNet associates with the environment and ACR private endpoint and links the endpoint's private DNS zone. Managed identity is assigned to the app and authorizes registry pulls; platform provisioning sends pull requests and receives image layers through that endpoint.*

## CI/CD Workflow

<!-- diagram-id: ci-cd-workflow -->
```mermaid
flowchart TD
    accTitle: GitHub Actions delivery flow for the Java container app
    accDescr: A commit starts a workflow that packages Java with tests skipped, builds a commit-tagged image, and pushes it to Azure Container Registry. The workflow independently invokes the deploy action with that image reference; ACR returns the push result but does not initiate deployment. Revision and application health are then verified manually.

    COMMIT["Commit to the configured branch"]
    WORKFLOW["GitHub Actions workflow"]
    PACKAGE["Package Java source<br/>tests skipped"]
    IMAGE["Build container image<br/>tagged with commit SHA"]
    ACR["Azure Container Registry"]
    DEPLOY["Azure Container Apps<br/>deploy action"]
    REVISION["New immutable revision"]
    VERIFY["Manual post-deployment checks<br/>revision name and /health"]
    COMPLETE["Verification complete"]
    INVESTIGATE["Inspect workflow or revision<br/>before changing traffic"]

    COMMIT -->|"Trigger"| WORKFLOW
    WORKFLOW --> PACKAGE
    PACKAGE --> IMAGE
    IMAGE ==>|"Push image"| ACR
    ACR ==>|"Push result"| WORKFLOW
    WORKFLOW -->|"Deploy image reference"| DEPLOY
    DEPLOY -->|"Update image reference"| REVISION
    REVISION --> VERIFY
    VERIFY -->|"Expected state confirmed"| COMPLETE
    VERIFY -.->|"Unexpected state"| INVESTIGATE

    LEGEND["Arrow key<br/>solid = automated delivery then manual checks<br/>dotted = unexpected verification result"]
```

*Figure: The shown workflow packages Java with `-DskipTests`, builds and deploys the image, and then relies on the manual revision and `/health` checks below. Remove `-DskipTests` or add a separate test step before using this as a test-gated release.*

## Prerequisites

- GitHub repository with your source code
- Existing Azure Container App and Container Registry (created in [02 - First Deploy](02-first-deploy.md))
- Azure CLI 2.57+

## Setting up GitHub Secrets

To allow GitHub Actions to authenticate with Azure, you must store credentials as [GitHub Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets).

1. **Create a Service Principal**

    ```bash
    az ad sp create-for-rbac \
      --name "gh-actions-sp-java" \
      --role Contributor \
      --scopes /subscriptions/<subscription-id>/resourceGroups/$RG \
      --json-auth
    ```

    | Command/Parameter | Purpose |
    |---|---|
    | `az ad sp create-for-rbac` | Creates the GitHub Actions service principal scoped to the tutorial resource group. |
    | `--name` | Sets the display name for the GitHub Actions service principal. |
| `--role` | Assigns `Contributor` so the workflow can build and deploy tutorial resources. |
    | `--scopes` | Limits the service principal assignment to the tutorial resource group. |
    | `--json-auth` | Returns credential JSON in the format expected by the Azure Login action. |

2. **Add Secrets to GitHub**

    Add the following secrets in your GitHub repository's `Settings > Secrets and variables > Actions`:

    - `AZURE_CREDENTIALS`: The entire JSON output from the service principal command.
    - `AZURE_RG`: Your resource group name.
    - `ACR_NAME`: Your Azure Container Registry name.
    - `ACA_NAME`: Your Azure Container App name.

## Creating the Workflow File

Create a file named `.github/workflows/deploy.yml` in your repository.

```yaml
name: Build and Deploy Java to ACA

on:
  push:
    branches:
      - main
    paths:
      - 'apps/java-springboot/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'

      - name: Package with Maven (tests skipped)
        run: |
          cd apps/java-springboot
          mvn package -DskipTests

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Build and Push to ACR
        run: |
          cd apps/java-springboot
          az acr build \
            --registry ${{ secrets.ACR_NAME }} \
            --image java-guide:${{ github.sha }} \
            --file Dockerfile .

      - name: Deploy to ACA
        run: |
          az containerapp update \
            --resource-group ${{ secrets.AZURE_RG }} \
            --name ${{ secrets.ACA_NAME }} \
            --image ${{ secrets.ACR_NAME }}.azurecr.io/java-guide:${{ github.sha }}
```

| Command | Why it is used |
|---|---|
| `az acr build` | Builds the Spring Boot image remotely and pushes its commit-tagged artifact to ACR. |
| `--registry` | Targets the Azure Container Registry named by the `ACR_NAME` repository secret. |
| `--image` | Tags the Java image with `${{ github.sha }}` for both build and deployment. |
| `--file` | Selects the Dockerfile used by the ACR build. |
| `az containerapp update` | Creates a Java app revision from the image produced by the preceding ACR build. |
| `--resource-group` | Targets the resource group named by the `AZURE_RG` repository secret. |
| `--name` | Targets the Container App named by the `ACA_NAME` repository secret. |

## Verifying the Deployment

1. **Check the GitHub Actions tab**

    Navigate to the `Actions` tab in your repository and verify that the workflow has run successfully.

2. **Verify the new revision**

    ```bash
    RG="<resource-group-name>"
    APP_NAME="<container-app-name>"
    az containerapp revision list \
      --resource-group $RG \
      --name $APP_NAME \
      --query "[0].name" --output tsv
    ```

    | Command/Parameter | Purpose |
    |---|---|
| `az containerapp revision list` | Reads the newest Spring Boot revision created by the workflow. |
| `--resource-group` | Uses local `$RG`; set it to the same resource-group value stored in the `AZURE_RG` repository secret. |
| `--name` | Uses local `$APP_NAME`; set it to the same app-name value stored in the `ACA_NAME` repository secret. |
| `--query` | Extracts `[0].name`, the first revision in the returned ordering. |
| `--output` | Emits only that revision name as text for subsequent verification. |

    ???+ example "Expected output"
        ```text
        <your-app-name>--xxxxxxx
        ```

3. **Verify the application health**

    ```bash
    curl https://<your-aca-fqdn>/health
    ```

## CI/CD Checklist

- [x] Service principal has `Contributor` permissions on the resource group
- [x] Maven cache is enabled in GitHub Actions to speed up builds
- [x] Workflow uses specific commit SHAs for container image tags (avoid `latest`)
- [x] Workflow triggers only on changes to the application's source path
- [x] The operator verifies the deployment with the revision query and health endpoint after the workflow completes

!!! info "Using Federated Credentials (OIDC)"
    For enhanced security, consider using [Workload Identity Federation](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Clinux) (OIDC) instead of storing secrets in GitHub. This removes the need for long-lived service principal keys.

### Verify deployment activity in Azure Portal

![Management Group|None|Subscription|Visual Studio Enterprise Subscription|Event severity|All|Timespan|Last 6 hours|Resource group|rg-aca-basics-d38538|Resource|ca-java-d38538|Status|Succeeded|Event initiated by|user@example.com](../../../assets/language-guides/java/tutorial/06-activity-log-blade.png)

**[Observed]** `Microsoft Azure (Preview)`. `Report a bug`. `Search resources, services, and docs (G+/)`. `Copilot`. `Home`. `ca-java-d38538`. `Container App`. `Activity log`. `Activity`. `Edit columns`. `Refresh`. `Export Activity Logs`. `Download as CSV`. `Insights`. `Feedback`. `Pin current filters`. `Reset filters`. `Looking for Log Analytics?`. `Visit Log Analytics`. `Search`. `Quick Insights`. `Management Group`. `None`. `Subscription`. `Visual Studio Enterprise Subscription`. `Event severity`. `All`. `Timespan`. `Last 6 hours`. `Resource group`. `rg-aca-basics-d38538`. `Resource`. `ca-java-d38538`. `Add Filter`. `3 items.`. `Operation name`. `Status`. `Time`. `Time stamp`. `Subscription`. `Event initiated by`. `Auth Token for Container App Dev APIs`. `Create or Update Container App`. `Succeeded`. `21 minutes ...`. `5 hours ago`. `Thu Jun 04 ...`. `user@example.com`. `Overview`. `Activity log`. `Access control (IAM)`. `Tags`. `Diagnose and solve problems`. `Resource visualizer`. `Application`. `Revisions and replicas`. `Containers`. `Scale`. `Volumes`. `Settings`. `Networking`. `Ingress`. `Custom domains`. `CORS`. `Security`. `Monitoring`. `Log stream`. `Logs`. `Console`. `Alerts`. `Metrics`. `Dashboards with Grafana`. `Advisor recommendations`.

**[Inferred]** The resource-scoped filter chips `Resource group` value `rg-aca-basics-d38538` and `Resource` value `ca-java-d38538` appear to map to the same `${{ secrets.AZURE_RG }}` and `${{ secrets.ACA_NAME }}` values passed to `--resource-group` and `--name` by the `az containerapp update` step in [Creating the Workflow File](#creating-the-workflow-file). The `Create or Update Container App` row appears consistent with the deployment outcome that the same `az containerapp update` step in [Creating the Workflow File](#creating-the-workflow-file) is expected to trigger when the workflow runs against the configured `ACA_NAME` secret. The `Succeeded` `Status` appears consistent with the healthy rollout signal that [Verifying the Deployment](#verifying-the-deployment) looks for via `az containerapp revision list`, which returns the active revision name when the rollout completes without error. The repeated `Create or Update Container App` rows with `Succeeded` `Status` within the `Last 6 hours` `Timespan` appear consistent with multiple workflow runs invoking the `az containerapp update` step in [Creating the Workflow File](#creating-the-workflow-file) against the same `ACA_NAME` secret.

**[Not Proven]** Additional GitHub Actions workflow output and CLI command output are not visible on this view.

## See Also
- [07 - Revisions and Traffic](07-revisions-traffic.md)
- [02 - First Deploy to Azure](02-first-deploy.md)
- [GitHub Actions for Azure (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/github-actions)

## Sources
- [Networking in an Azure Container Apps environment (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Azure Container Apps image pull from ACR with managed identity (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry private link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [Deploy to Azure Container Apps with GitHub Actions (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/github-actions)
- [Revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Health probes in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
- [Setup Java Action (GitHub Marketplace)](https://github.com/marketplace/actions/setup-java-jdk-binaries)
