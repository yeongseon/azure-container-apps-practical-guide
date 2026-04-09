---
hide:
  - toc
---

# 06 - CI/CD with GitHub Actions

Automate build and deployment so every commit can produce a new Container App revision. This tutorial uses GitHub Actions, ACR, and Azure Container Apps deploy actions.

## CI/CD Pipeline Flow

```mermaid
graph LR
    PUSH[Push to main] --> GHA[GitHub Actions]
    GHA --> ACR[ACR Build]
    ACR --> DEPLOY[Deploy Revision]
    DEPLOY --> HEALTH[Health Check]
```

## Prerequisites

- Completed [05 - Infrastructure as Code with Bicep](05-infrastructure-as-code.md)
- GitHub repository with Actions enabled
- Azure service principal stored as GitHub secret

!!! warning "Never expose credentials in workflow logs"
    Keep all credential material in GitHub Secrets and avoid printing secret-derived values in shell steps. Use masked placeholders in documentation and workflow examples.

## Step-by-step

1. **Configure repository variables and secrets**

    - Variables: `RESOURCE_GROUP`, `APP_NAME`, `ACR_NAME`
    - Secrets: `AZURE_CREDENTIALS`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`

    Example `AZURE_CREDENTIALS` JSON (masked):

    ```json
    {
      "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "clientSecret": "<client-secret>",
      "subscriptionId": "<subscription-id>",
      "tenantId": "<tenant-id>"
    }
    ```

2. **Create workflow file**

    Create a file at `.github/workflows/deploy.yml` in your repository:

    ```yaml
    name: Deploy Node.js App to ACA

    on:
      push:
        branches: [ main ]
        paths:
          - 'apps/nodejs/**'
          - '.github/workflows/deploy.yml'

    jobs:
      build-and-deploy:
        runs-on: ubuntu-latest
        steps:
          - name: Checkout
            uses: actions/checkout@v4

          - name: Azure Login
            uses: azure/login@v2
            with:
              creds: ${{ secrets.AZURE_CREDENTIALS }}

          - name: ACR Login
            uses: azure/docker-login@v2
            with:
              login-server: ${{ vars.ACR_NAME }}.azurecr.io
              username: ${{ secrets.REGISTRY_USERNAME }}
              password: ${{ secrets.REGISTRY_PASSWORD }}

          - name: Build and push image
            run: |
              docker build --tag ${{ vars.ACR_NAME }}.azurecr.io/${{ vars.APP_NAME }}:${{ github.sha }} ./apps/nodejs
              docker push ${{ vars.ACR_NAME }}.azurecr.io/${{ vars.APP_NAME }}:${{ github.sha }}

          - name: Deploy Container App
            uses: azure/container-apps-deploy-action@v1
            with:
              imageToDeploy: ${{ vars.ACR_NAME }}.azurecr.io/${{ vars.APP_NAME }}:${{ github.sha }}
              resourceGroup: ${{ vars.RESOURCE_GROUP }}
              containerAppName: ${{ vars.APP_NAME }}
    ```

3. **Validate rollout behavior**

    - Trigger workflow from a commit to `main`.
    - Confirm a new revision was created.
    - Confirm traffic moved to healthy revision.

    ```bash
    az containerapp revision list \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --query "[].{name:name,active:properties.active,trafficWeight:properties.trafficWeight,healthState:properties.healthState}"
    ```

    ???+ example "Expected output"
        ```json
        [
          {
            "name": "<your-app-name>--0000001",
            "active": false,
            "trafficWeight": 0,
            "healthState": "Healthy"
          },
          {
            "name": "<your-app-name>--0000002",
            "active": true,
            "trafficWeight": 100,
            "healthState": "Healthy"
          }
        ]
        ```

## Node.js Specific CI Tips

- **Run Tests**: Add a step to run `npm test` before building the Docker image.
- **Security Audit**: Use `npm audit` to check for known vulnerabilities in your dependencies.
- **Linting**: Run `npm run lint` to ensure code quality before deployment.

```yaml
          - name: Install dependencies
            run: npm install
            working-directory: ./apps/nodejs

          - name: Run tests
            run: npm test
            working-directory: ./apps/nodejs
```

## Advanced Topics

- Implement multi-environment pipelines (dev -> staging -> prod) with approval gates.
- Use GitHub environments to manage secrets and variables for different stages.
- Integrate with Azure Load Testing to validate performance after deployment.

!!! tip "Use immutable image tags in pipelines"
    Prefer commit SHA or release-based tags for image versions. Immutable tags make revision-to-commit tracing straightforward during incident response.

## See Also
- [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)
- [05 - Infrastructure as Code with Bicep](05-infrastructure-as-code.md)
- [Managed Identity Recipe](../../platform/identity-and-secrets/managed-identity.md)

## Sources
- [GitHub Actions (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/github-actions)
- [Connect GitHub Actions to Azure (Microsoft Learn)](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
