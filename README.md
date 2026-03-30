# Azure Container Apps Python Reference

Production-ready Python Flask application demonstrating Azure Container Apps deployment, observability, and operations.

## Features

- 🐳 **Containerized Flask App** with Gunicorn
- 📊 **OpenTelemetry Integration** for distributed tracing
- 🔄 **Revision Management** with traffic splitting
- 📈 **KEDA Autoscaling** based on HTTP traffic
- 🔐 **Managed Identity** for secure Azure service access
- 🌐 **VNet Integration** and Private Endpoints

## Quick Start

```bash
# Local development
cd app
docker build -t aca-python-reference .
docker run -p 8000:8000 aca-python-reference

# Deploy to Azure (basic)
cd infra
cp .env.example .env
./deploy.sh

# Deploy with Private Endpoints (VNet + Key Vault + Storage)
cd infra
./deploy-private.sh
```

## Deployment Options

| Script | Description | Resources |
|--------|-------------|-----------|
| `deploy.sh` | Basic deployment | ACR, Container App, Log Analytics |
| `deploy-private.sh` | Private Endpoint test environment | + VNet, Key Vault, Storage with Private Endpoints |

## Documentation

| Guide | Description |
|-------|-------------|
| [01 - Local Run](docs/01-local-run.md) | Docker-based local development |
| [02 - Provision Infrastructure](docs/02-provision-infra.md) | Bicep deployment |
| [03 - Deploy App](docs/03-deploy-app.md) | Container image deployment |
| [04 - Configure Settings](docs/04-configure-app-settings.md) | Environment variables and secrets |
| [05 - Basic Monitoring](docs/05-monitor-basic.md) | Log streaming and queries |
| [06 - Troubleshooting](docs/06-troubleshoot.md) | Debugging techniques |
| [07 - Advanced Observability](docs/07-observability-advanced.md) | OpenTelemetry setup |
| [08 - GitHub Actions](docs/08-github-actions.md) | CI/CD pipelines |
| [09 - Revisions](docs/09-revisions.md) | Traffic management |

### Recipes

- [Easy Auth](docs/recipes/easy-auth.md) - Built-in authentication
- [Managed Identity](docs/recipes/managed-identity.md) - Passwordless access
- [Dapr Integration](docs/recipes/dapr-integration.md) - Microservices patterns
- [VNet Integration](docs/recipes/networking-vnet.md) - Network isolation
- [Private Endpoints](docs/recipes/networking-private-endpoint.md) - Private connectivity
- [Egress Control](docs/recipes/networking-egress.md) - Outbound traffic management

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check |
| `GET /info` | Application info |
| `GET /api/requests/log-levels` | Log level demonstration |
| `GET /api/dependencies/external` | External API call |
| `GET /api/exceptions/test-error` | Error handling demo |

## License

MIT
