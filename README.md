# Azure Container Apps Practical Guide

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Comprehensive guide for running containerized applications on Azure Container Apps — from first deployment to production troubleshooting.

## What's Inside

| Section | Description |
|---------|-------------|
| [Start Here](https://yeongseon.github.io/azure-container-apps-practical-guide/) | Overview, learning paths, and repository map |
| [Platform](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | Architecture, environments, revisions, scaling, networking, jobs, identity |
| [Best Practices](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | Container design, revision strategy, scaling, networking, identity, reliability, cost |
| [Language Guides](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Step-by-step tutorials for Python, Node.js, Java, and .NET |
| [Operations](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | Deployment, monitoring, scaling, alerts, secret rotation, recovery |
| [Troubleshooting](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | Playbooks, hands-on labs, KQL query packs, decision tree, evidence map |
| [Reference](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI reference, environment variables, platform limits |

## Language Guides

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

Each guide covers: local development, first deploy, configuration, logging, infrastructure as code, CI/CD, and revisions & traffic splitting.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git

# Install MkDocs dependencies
pip install mkdocs-material mkdocs-minify-plugin

# Start local documentation server
mkdocs serve
```

Visit `http://127.0.0.1:8000` to browse the documentation locally.

## Reference Applications

Minimal reference applications demonstrating Azure Container Apps patterns:

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## Reference Jobs

- `jobs/python/` — Python scheduled job with managed identity

## Troubleshooting Labs

10 hands-on labs in `labs/` with Bicep templates that reproduce real-world Container Apps issues. Each lab includes:

- Falsifiable hypothesis and step-by-step runbook
- Real Azure deployment data (KQL logs, CLI output)
- Expected Evidence sections with falsification logic
- Cross-links to corresponding playbooks

## Contributing

Contributions welcome. Please ensure:

- All CLI examples use long flags (`--resource-group`, not `-g`)
- All documents include mermaid diagrams
- All content references Microsoft Learn with source URLs
- No PII in CLI output examples

## Related Projects

| Repository | Description |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines practical guide |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking practical guide |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage practical guide |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service practical guide |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions practical guide |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services practical guide |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) practical guide |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture practical guide |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring practical guide |

## Disclaimer

This is an independent community project. Not affiliated with or endorsed by Microsoft. Azure and Container Apps are trademarks of Microsoft Corporation.

## License

[MIT](LICENSE)
