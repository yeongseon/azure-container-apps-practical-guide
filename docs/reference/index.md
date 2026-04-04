# Reference

Use this section as a quick lookup for Azure Container Apps operational commands, runtime environment variables, and platform limits.

## Prerequisites

- Azure CLI 2.57+ and Container Apps extension
- Access to a subscription and resource group where your Container Apps resources exist

```bash
az extension add --name containerapp --upgrade
az login
```

## Reference Materials

- [CLI Reference](cli-reference.md): High-signal `az containerapp` command patterns with long-flag examples.
- [Environment Variables](environment-variables.md): Platform-injected variables and recommended app/runtime variables.
- [Platform Limits](platform-limits.md): Practical limit tables for compute, scale, networking, storage, and jobs.

## Advanced Topics

- Standardize command snippets in runbooks and CI/CD templates.
- Track breaking CLI/API changes per release.
- Re-validate limits and defaults during architecture reviews.

## See Also

- [Operations](../operations/index.md)
- [Troubleshooting Methodology](../troubleshooting/methodology/index.md)
- [Microsoft Learn: Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
