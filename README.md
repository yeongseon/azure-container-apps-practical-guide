# Azure Container Apps Python Guide

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyeongseon%2Fazure-container-apps-python-guide%2Fmain%2Finfra%2Fazuredeploy.json)

Comprehensive guide to running Python/Flask applications on Azure Container Apps — from first deploy to production operations.

> **Not just another sample app.** This guide explains *why* things work the way they do, so you can debug issues and make informed decisions.

## Learning Paths

```
┌─────────────────────────────────────────────────────────────────────┐
│                         QUICK START (30 min)                        │
│  ┌──────────────┐    ┌──────────────┐                              │
│  │ 1. Local Dev │───▶│ 2. Deploy   │                              │
│  └──────────────┘    └──────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         CORE PATH (2-3 hrs)                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐         │
│  │ 3. Config    │───▶│ 4. Logging  │───▶│ 5. IaC       │         │
│  └──────────────┘    └──────────────┘    └──────────────┘         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      PRODUCTION PATH (2-3 hrs)                      │
│  ┌──────────────┐    ┌──────────────┐                              │
│  │ 6. CI/CD     │───▶│ 7. Revisions│                              │
│  │ (Actions)    │    │ (Traffic)   │                              │
│  └──────────────┘    └──────────────┘                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: Deploy in 5 minutes

```bash
# Clone and deploy
git clone https://github.com/yeongseon/azure-container-apps-python-guide.git
cd azure-container-apps-python-guide/infra

# Configure
cp .env.example .env
# Edit BASE_NAME to a unique value (e.g., your initials + date)

# Deploy
az login
./deploy.sh
```

### Option 2: Run locally first

```bash
cd app
docker build -t aca-python-guide .
docker run -p 8000:8000 aca-python-guide
# Visit http://localhost:8000
```

## Documentation

### 📚 Tutorial (Start Here)

Step-by-step guide from zero to production.

| # | Document | Time | Description |
|---|----------|------|-------------|
| 1 | [Local Development](./docs/tutorial/01-local-run.md) | 10 min | Run with Docker locally |
| 2 | [First Deploy](./docs/tutorial/02-first-deploy.md) | 15 min | Deploy to Azure |
| 3 | [Configuration](./docs/tutorial/03-configuration.md) | 20 min | Secrets, env vars, Dapr |
| 4 | [Logging & Monitoring](./docs/tutorial/04-logging-monitoring.md) | 30 min | Logs, Application Insights |
| 5 | [Infrastructure as Code](./docs/tutorial/05-infrastructure-as-code.md) | 30 min | Bicep templates |
| 6 | [CI/CD](./docs/tutorial/06-ci-cd.md) | 45 min | GitHub Actions |
| 7 | [Revisions & Traffic](./docs/tutorial/07-revisions-traffic.md) | 30 min | Blue-green, canary deploys |

### 🧠 Concepts

Understand *how* Container Apps works under the hood.

| Document | Description |
|----------|-------------|
| [How Container Apps Works](./docs/concepts/how-container-apps-works.md) | Platform architecture, environments, containers |
| [Container Apps vs Others](./docs/concepts/container-apps-vs-others.md) | Comparison with AKS, App Service, ACI |
| [Environments & Apps](./docs/concepts/environments-and-apps.md) | Environment types, app relationships |
| [Scaling with KEDA](./docs/concepts/scaling-keda.md) | KEDA autoscaling, scale rules |
| [Networking](./docs/concepts/networking.md) | VNet, ingress, service discovery |

### ⚙️ Operations

Production operations and day-2 activities.

| Document | Description |
|----------|-------------|
| [Scaling](./docs/operations/scaling.md) | Manual scaling, KEDA rules, scale-to-zero |
| [Revisions](./docs/operations/revisions.md) | Revision management, traffic splitting |
| [Health & Recovery](./docs/operations/health-recovery.md) | Health probes, restart policies |
| [Networking](./docs/operations/networking.md) | VNet ops, ingress config |
| [Security](./docs/operations/security.md) | Managed identity, secrets, Easy Auth |
| [Cost Optimization](./docs/operations/cost-optimization.md) | Consumption vs Workload profiles |
| [Observability](./docs/operations/observability.md) | Log Analytics, distributed tracing |

### 🍳 Recipes

Practical integration guides.

| Recipe | Description |
|--------|-------------|
| [Cosmos DB](./docs/recipes/cosmosdb.md) | NoSQL database with Managed Identity |
| [Azure SQL](./docs/recipes/azure-sql.md) | SQL database with Managed Identity |
| [Redis Cache](./docs/recipes/redis.md) | Caching and sessions |
| [Key Vault](./docs/recipes/key-vault.md) | Secrets management |
| [Blob Storage](./docs/recipes/storage.md) | File storage and mounts |
| [Managed Identity](./docs/recipes/managed-identity.md) | Passwordless authentication |
| [Easy Auth](./docs/recipes/easy-auth.md) | Built-in authentication |
| [Dapr Integration](./docs/recipes/dapr-integration.md) | Service invocation, pub/sub, state |
| [VNet Integration](./docs/recipes/networking-vnet.md) | Network isolation |
| [Private Endpoints](./docs/recipes/networking-private-endpoint.md) | Private connectivity |
| [Egress Control](./docs/recipes/networking-egress.md) | Egress traffic control |
| [Service-to-Service](./docs/recipes/networking-service-to-service.md) | Service communication |
| [Container Registry](./docs/recipes/container-registry.md) | Private ACR with Container Apps |

### 📖 Reference

Quick lookup documentation.

| Document | Description |
|----------|-------------|
| [CLI Cheatsheet](./docs/reference/cli-cheatsheet.md) | Common az containerapp commands |
| [KQL Queries](./docs/reference/kql-queries.md) | Log Analytics queries |
| [Troubleshooting](./docs/reference/troubleshooting.md) | Debugging, common issues |
| [Environment Variables](./docs/reference/environment-variables.md) | System and app env vars |
| [Python Runtime](./docs/reference/python-runtime.md) | Gunicorn, workers, settings |
| [Platform Limits](./docs/reference/platform-limits.md) | Timeouts, quotas |

## Repository Structure

```
├── app/                    # Flask reference application
│   ├── src/
│   │   ├── app.py          # Flask entry point
│   │   ├── routes/         # API endpoints
│   │   └── middleware/     # Logging, correlation
│   ├── Dockerfile
│   └── requirements.txt
│
├── docs/                   # Documentation
│   ├── tutorial/           # Step-by-step guides
│   ├── concepts/           # How things work
│   ├── operations/         # Production operations
│   ├── recipes/            # Integration guides
│   └── reference/          # Quick lookup
│
└── infra/                  # Infrastructure as Code
    ├── main.bicep          # Azure resources
    ├── deploy.sh           # Basic deployment
    └── deploy-private.sh   # VNet deployment
```

## What You'll Deploy

| Resource | SKU | Monthly Cost |
|----------|-----|--------------|
| Container Apps Environment | Consumption | $0 (base) |
| Container App | Pay-per-use | ~$0-20 |
| Azure Container Registry | Basic | ~$5 |
| Log Analytics | Pay-as-you-go | ~$0-10 |

**Total: ~$5-35/month** for demo workloads. Scale-to-zero means you only pay when running.

## Key Features of the Reference App

- ✅ **Container Apps Ready** — Health probes, graceful shutdown
- ✅ **Structured Logging** — JSON format for Log Analytics
- ✅ **OpenTelemetry** — Distributed tracing support
- ✅ **Health Endpoint** — `/health` for monitoring
- ✅ **KEDA Scaling** — Event-driven autoscaling
- ✅ **Dapr Ready** — Service invocation, state, pub/sub

## Sample Endpoints

```bash
# Health check
curl https://your-app.azurecontainerapps.io/health

# Generate test logs
curl https://your-app.azurecontainerapps.io/api/requests/log-levels

# Test external dependency
curl https://your-app.azurecontainerapps.io/api/dependencies/external
```

## Contributing

Contributions welcome! Please read our contributing guidelines and open a PR.

## License

MIT License — see [LICENSE](./LICENSE)

---

**Questions?** [Open an issue](https://github.com/yeongseon/azure-container-apps-python-guide/issues)
