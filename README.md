# Azure Container Apps Guide

A practical hub for learning, designing, operating, and troubleshooting Azure Container Apps and Jobs across languages, revision models, and deployment patterns.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyeongseon%2Fazure-container-apps%2Fmain%2Finfra%2Fazuredeploy.json)

## Repository Structure

```
├── docs/                   # MkDocs documentation
│   ├── start-here/         # Getting started, overview, learning paths
│   ├── platform/           # Architecture, environments, revisions, scaling, networking, jobs, identity, reliability
│   ├── language-guides/    # Per-language tutorials and recipes (currently: Python)
│   │   └── python/         # Flask tutorial steps + recipes
│   ├── operations/         # Deployment, monitoring, scaling, alerts, recovery
│   ├── troubleshooting/    # First 10 minutes, playbooks, methodology, KQL, lab guides
│   │   ├── playbooks/      # Startup, networking, scaling, identity, platform-feature failures
│   │   ├── kql/            # Query packs by category + correlation queries
│   │   └── lab-guides/     # Scenario-based troubleshooting walkthroughs
│   └── reference/          # CLI reference, environment variables, platform limits
├── apps/                   # Reference applications
│   └── python/             # Flask reference app (health, logging, telemetry)
├── jobs/                   # Reference jobs
│   └── python/             # Python reference job (scheduled, identity, storage)
├── labs/                   # Hands-on troubleshooting labs
│   ├── acr-pull-failure/
│   ├── revision-failover/
│   └── scale-rule-mismatch/
├── infra/                  # Bicep infrastructure templates
└── mkdocs.yml              # Documentation configuration
```

## Quick Start

### Option 1: Deploy in 5 minutes

```bash
# Clone and deploy
git clone https://github.com/yeongseon/azure-container-apps.git
cd azure-container-apps/infra

# Configure
cp .env.example .env
# Edit BASE_NAME to a unique value (e.g., your initials + date)

# Deploy
az login
./deploy.sh
```

### Option 2: Run locally first

```bash
cd apps/python
docker build --tag aca-python-guide .
docker run --publish 8000:8000 aca-python-guide
# Visit http://localhost:8000
```

## Documentation Tabs

- **Start Here**: Foundational overview, architectural comparisons, and suggested learning paths for different roles.
- **Platform**: Deep dives into core Azure Container Apps components like environments, revisions, scaling, and networking.
- **Language Guides**: Practical, step-by-step tutorials and integration recipes for specific runtimes (starting with Python).
- **Operations**: Best practices for production deployment, monitoring, alerting, and cost optimization.
- **Troubleshooting**: A systematic methodology for debugging issues, featuring KQL playbooks and hands-on labs.
- **Reference**: Quick lookup content for CLI commands, environment variables, and platform limits.

## Reference Assets

- **apps/**: Production-ready reference applications demonstrating structured logging, health probes, and graceful shutdown.
- **jobs/**: Reference implementations for Azure Container Apps Jobs, covering scheduled tasks and event-driven execution.
- **labs/**: Guided troubleshooting exercises to help you master platform-specific failure modes and resolution patterns.

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
- ✅ **KEDA Scaling** — Event-driven autoscaling (platform-managed, no app dependency)
- ✅ **Dapr Compatible** — Ready for service invocation, state, pub/sub (add `dapr` package when enabling)

## Contributing

Contributions welcome! Please read our contributing guidelines and open a PR.

## License

MIT License — see [LICENSE](./LICENSE)

---

**Questions?** [Open an issue](https://github.com/yeongseon/azure-container-apps/issues)
