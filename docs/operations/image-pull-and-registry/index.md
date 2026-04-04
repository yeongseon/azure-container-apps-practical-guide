# Image Pull and Registry Operations

Image distribution reliability is foundational for stable deployments. This guide covers authentication, tagging, rotation, and troubleshooting for registry operations.

## ACR Authentication Methods

Container Apps can pull images from Azure Container Registry using several methods:

1. **Managed identity (recommended)**
   - Best for production security posture
   - No long-lived credentials in configuration
2. **Service principal**
   - Useful for cross-tenant or constrained scenarios
   - Requires credential lifecycle management
3. **Admin user (not recommended for production)**
   - Fast setup for testing only
   - Broad credentials increase risk

Assign pull role for managed identity:

```bash
az role assignment create \
  --assignee-object-id "<object-id>" \
  --assignee-principal-type "ServicePrincipal" \
  --role "AcrPull" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RG/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
```

## Private ACR with VNet

For regulated workloads:

- Use Private Endpoint for ACR.
- Configure private DNS resolution in the same network boundary as Container Apps environment.
- Restrict public network access for the registry.

Validate connectivity from workload subnet before enforcing deny-public rules.

## Image Tagging Strategy

Use immutable version tags for deployment references:

- Good: `python-app:20260404.1`, `python-app:gitsha-1a2b3c4d`
- Avoid: relying only on `latest` in production

Maintain retention policy to prune stale tags while preserving rollback window.

## Registry Credential Rotation

If using service principal credentials:

- Rotate client secret on a fixed schedule.
- Update Container Apps secret references before expiry.
- Verify image pull after rotation and keep previous secret for rollback window.

Prefer managed identity to reduce operational rotation burden.

## ACR Tasks for Automated Builds

ACR Tasks can build images on commit or schedule without external runners.

```bash
az acr task create \
  --registry "$ACR_NAME" \
  --name "build-python-app" \
  --context "https://github.com/yeongseon/azure-container-apps-python-guide.git" \
  --file "apps/python/Dockerfile" \
  --image "python-app:{{.Run.ID}}" \
  --commit-trigger-enabled true
```

## Troubleshooting Image Pull Failures

Common causes:

- Identity lacks `AcrPull`
- Image tag does not exist
- Registry firewall/private endpoint DNS misconfiguration
- Secret reference mismatch when using username/password auth

Collect system logs and verify effective image reference during rollout:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system
```

## See Also

- [Troubleshooting Playbooks](../../troubleshooting/playbooks/index.md)
- [Deployment Workflows](../deployment/index.md)
- [Secret Rotation](../secret-rotation/index.md)
