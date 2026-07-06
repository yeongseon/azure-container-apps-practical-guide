# Azure Container Apps Practical Guide

📘 **Documentation site:** <https://yeongseon.github.io/azure-container-apps-practical-guide/>

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Evidence-driven, operator-focused guide for running containerized applications on Azure Container Apps. Key operational guidance is supported by reproducible labs, metric captures, KQL examples, and Microsoft Learn references — from first deployment through production-grade monitoring, alerting, and incident response.

## What's Inside

| Section | Description | Status |
|---------|-------------|--------|
| [Start Here](https://yeongseon.github.io/azure-container-apps-practical-guide/) | Overview, learning paths, and repository map | Comprehensive |
| [Platform](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | Architecture, environments, revisions, scaling, networking, jobs, identity | Comprehensive |
| [Best Practices](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | Container design, revision strategy, scaling, networking, identity, reliability, cost | Comprehensive |
| [Language Guides](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Step-by-step tutorials for Python, Node.js, Java, and .NET | Comprehensive |
| [Operations](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | Deployment, monitoring, scaling, alerts, secret rotation, recovery | Comprehensive |
| [Troubleshooting](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | Playbooks, hands-on labs, KQL query packs, decision tree, evidence map | Lab-validated |
| [Reference](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI reference, environment variables, platform limits | Comprehensive |

**Status legend**: **Lab-validated** = Comprehensive + reproducible labs prove the guidance · **Comprehensive** = Full section, MSLearn-verified, production-ready · **Published** = Core content in place, still expanding · **In progress** = Partial content, active development · **Planned** = Placeholder, content not yet started

## What Makes This Different

- **Lab-validated** — Comprehensive hands-on lab suite with reproducible Bicep, verify scripts, and evidence reports
- **KQL query packs** — 30+ production-ready queries for Log Analytics and App Insights
- **Metrics reference** — Platform metrics explained with captures, denominator notes, and dimension mapping
- **Playbooks** — Structured troubleshooting with competing hypotheses, decision flows, and CLI evidence collection

## Language Guides

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

Each guide covers: local development, first deploy, configuration, logging, infrastructure as code, CI/CD, and revisions & traffic splitting.

## Quick Start

```bash
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git
cd azure-container-apps-practical-guide

python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements-docs.txt

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

Hands-on labs in `labs/` with Bicep templates that reproduce real-world Container Apps issues. Each lab includes:

- Falsifiable hypothesis and step-by-step runbook
- Real Azure deployment data (KQL logs, CLI output)
- Expected Evidence sections with falsification logic
- Cross-links to corresponding playbooks

Current evidence-pack framing across the lab corpus: **27/28 falsification labs + 1 metrics evidence baseline = 28 total**. The special-case exception is `labs/metrics-load-test/`, which is the data source for the metrics reference rather than a trigger/fix/falsification lab.

### ACR Network Path Series

A focused 5-lab series in `labs/acr-network-path-*` reproduces the five distinct network paths a Container App can take to reach Azure Container Registry:

- **Path A — Firewall Allowlist** — Public ACR with Azure Firewall SNAT and `networkRuleSet.ipRules` allowlist toggling
- **Path B — PE Direct** — ACR Premium Private Endpoint with `privatelink.azurecr.io` linked DNS zone
- **Path C — PE with Forced Inspection** — Private Endpoint plus Azure Firewall plus `/32` UDR routes (silent inspection-bypass class)
- **Path D — Record-Level Zone Authority** — Per-record DNS authority failure in a linked Private DNS Zone
- **Path E — DNS Forwarder Bypass** — Custom DNS resolver topology that bypasses the linked zone

See the [ACR Network Path Selection](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/networking/acr-network-path-selection/) platform doc for the conceptual taxonomy that names and orders all five paths.

## Contributing

Contributions welcome! Please see our [Contributing Guide](https://yeongseon.github.io/azure-container-apps-practical-guide/contributing/) for:

- Repository structure and content organization
- Document templates and writing standards
- CLI command style and PII rules
- Local development setup and build validation
- Pull request process

## Related Projects

| Repository | Description |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines practical guide |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking practical guide |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage practical guide |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service practical guide |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions practical guide |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services practical guide |
| [azure-container-apps-practical-guide](https://github.com/yeongseon/azure-container-apps-practical-guide) | Azure Container Apps practical guide |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) practical guide |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture practical guide |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring practical guide |

## Disclaimer

This is an independent community project. Not affiliated with or endorsed by Microsoft. Azure and Container Apps are trademarks of Microsoft Corporation.

## License

[MIT](LICENSE)
