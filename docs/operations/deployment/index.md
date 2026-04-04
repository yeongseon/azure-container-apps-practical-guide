# Deployment Workflows

This guide summarizes practical deployment workflows for Azure Container Apps across CLI, Infrastructure as Code, and CI/CD pipelines.

## Deployment Strategies

Choose deployment style based on release frequency and control requirements:

- **Direct CLI** for fast iteration in development environments.
- **Bicep/ARM** for repeatable infrastructure and policy alignment.
- **CI/CD pipelines** for standardized builds, approvals, and rollback control.

## CI/CD with GitHub Actions

Use GitHub Actions to build images, push to ACR, and deploy to Container Apps in one pipeline.

Typical stages:

1. Lint and test application code.
2. Build container image.
3. Push image to ACR.
4. Deploy or update Container App / Job.
5. Verify health endpoint and revision state.

Use workload identity federation where possible to avoid long-lived service principal secrets.

## Azure CLI Deployment

Direct CLI deployment is useful for smoke testing or emergency patching.

```bash
az containerapp up \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --environment "$ENVIRONMENT_NAME" \
  --source "./apps/python"
```

Update image to create a new revision:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/python-app:v2"
```

## Bicep/ARM Deployment

IaC deployments keep environment, identity, and app configuration consistent.

```bash
az deployment group create \
  --resource-group "$RG" \
  --template-file "infra/main.bicep" \
  --parameters "baseName=myapp" "location=$LOCATION"
```

Use `what-if` before production applies:

```bash
az deployment group what-if \
  --resource-group "$RG" \
  --template-file "infra/main.bicep" \
  --parameters "baseName=myapp" "location=$LOCATION"
```

## Image Build and Push to ACR

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "python-app:$(date +%Y%m%d%H%M%S)" \
  --file "apps/python/Dockerfile" \
  "apps/python"
```

Prefer immutable tags for release traceability, and maintain a stable alias tag only for non-production testing.

## Deployment Checklist

- Container image built from pinned base image and scanned.
- Revision mode and traffic strategy validated.
- Health probes configured and verified.
- Managed identity and secret references resolved.
- Post-deploy smoke test completed.
- Rollback path documented and tested.

## See Also

- [Language Guides](../../language-guides/index.md)
- [Revision Management](../revision-management/index.md)
- [Recovery and Incident Readiness](../recovery/index.md)
