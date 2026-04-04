# Reference

Quick lookup documentation for Azure Container Apps operations and diagnostics.

## Documents

| Document | Description |
|----------|-------------|
| [CLI Reference](cli-reference.md) | Common `az containerapp` commands for app lifecycle, configuration, deployment, and scaling |
| [Environment Variables](environment-variables.md) | Platform-injected variables and recommended app/runtime variables |
| [Platform Limits](platform-limits.md) | Platform quotas, request/timeout constraints, storage behavior, and scale boundaries |

## Quick Links

| URL | Purpose |
|-----|---------|
| `https://${APP_NAME}.${ENVIRONMENT_DEFAULT_DOMAIN}` | Application endpoint (external ingress) |
| `${APP_NAME}.internal.${ENVIRONMENT_DEFAULT_DOMAIN}` | Internal endpoint (internal ingress) |
| Azure Portal → Container App → Log stream | Real-time container logs |
| Azure Portal → Container App → Console | Interactive container shell |

## Common Variables

| Variable | Description |
|----------|-------------|
| `$RG` | Resource group name |
| `$APP_NAME` | Container App name |
| `$ENVIRONMENT_NAME` | Container Apps Environment name |
| `$ACR_NAME` | Azure Container Registry name |
| `$LOCATION` | Azure region (e.g., `koreacentral`) |

## Language-Specific Details

For runtime-specific guidance, see:
- [Python Guide](../language-guides/python/index.md)

## See Also

- [Operations](../operations/index.md)
- [Troubleshooting Methodology](../troubleshooting/methodology/index.md)

## Sources

- [Azure Container Apps documentation (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/)
- [Azure Container Apps CLI reference](https://learn.microsoft.com/cli/azure/containerapp)
