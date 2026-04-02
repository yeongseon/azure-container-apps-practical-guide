# Tutorial: Azure Container Apps for Python

Follow this tutorial sequence to containerize a Python app, deploy it to Azure Container Apps, configure runtime settings, and operate it with production-ready practices.

## Prerequisites

- Azure CLI 2.57+ with Container Apps extension
- Docker (for local testing)
- An Azure subscription
- A Python web app that exposes `/health`

```bash
az extension add --name containerapp --upgrade
az login
```

## Tutorial Path

1. [01 - Run Locally with Docker](01-local-run.md)
2. [02 - First Deploy to Azure Container Apps](02-first-deploy.md)
3. [03 - Configuration, Secrets, and Dapr](03-configuration.md)
4. [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
5. [05 - Infrastructure as Code with Bicep](05-infrastructure-as-code.md)
6. [06 - CI/CD with GitHub Actions](06-ci-cd.md)
7. [07 - Revisions and Traffic Splitting](07-revisions-traffic.md)

## Advanced Topics

- Use [Dapr integration](../recipes/dapr-integration.md) for service invocation, pub/sub, and state APIs.
- Add VNet and private networking patterns from [networking recipes](../recipes/networking-vnet.md).
- Standardize environment provisioning with reusable Bicep modules.

## See Also

- [How Container Apps Works](../concepts/how-container-apps-works.md)
- [Environment Variables Reference](../reference/environment-variables.md)
- [Managed Identity Recipe](../recipes/managed-identity.md)
