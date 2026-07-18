# Azure Container Apps 实操指南

📘 **文档站点：** <https://yeongseon.github.io/azure-container-apps-practical-guide/>

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

[![Docs](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml)
[![CI](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

以证据为驱动、面向运维人员的 Azure Container Apps 容器化应用运行指南。关键运维指导由可重现的实验室、指标捕获、KQL 示例以及 Microsoft Learn 参考提供支持 —— 涵盖从首次部署到生产级监控、告警和事件响应的全过程。

## 内容概览

| 章节 | 描述 | 状态 |
|---------|-------------|--------|
| [从这里开始](https://yeongseon.github.io/azure-container-apps-practical-guide/) | 概述、学习路径和仓库地图 | 全面 |
| [平台](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | 架构、环境、修订版、扩展、网络、作业、身份 | 全面 |
| [最佳实践](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | 容器设计、修订版策略、扩展、网络、身份、可靠性、成本 | 全面 |
| [编程语言指南](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Python、Node.js、Java 和 .NET 的分步教程 | 全面 |
| [运营](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | 部署、监控、扩展、告警、密钥轮换、恢复 | 全面 |
| [故障排查](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | 实战手册、动手实验、KQL 查询包、决策树、证据图 | 实验室验证 |
| [参考](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI 参考、环境变量、平台限制 | 全面 |

**状态说明**：**实验室验证** = 全面内容 + 可重现的实验室证明了该指导 · **全面** = 完整章节，经 MSLearn 验证，可用于生产环境 · **已发布** = 核心内容已到位，仍处于扩展中 · **进行中** = 部分内容，处于活跃开发中 · **已计划** = 占位符，内容尚未开始

## 本指南的独特之处

- **实验室验证** —— 包含可重现 Bicep、验证脚本和证据报告的完整动手实验套件
- **KQL 查询包** —— 30 多个适用于 Log Analytics 和 App Insights 的生产级查询
- **指标参考** —— 通过捕获图、分母说明和维度映射解释平台指标
- **实战手册** —— 结构化故障排查，包含竞争假设、决策流和 CLI 证据收集

## 编程语言指南

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

每个指南都涵盖：本地开发、首次部署、配置、日志记录、基础设施即代码 (IaC)、CI/CD 以及修订版与流量分配。

## 快速入门

```bash
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git
cd azure-container-apps-practical-guide

python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements-docs.txt

mkdocs serve
```

访问 `http://127.0.0.1:8000` 在本地浏览文档。

## 参考应用

演示 Azure Container Apps 模式的最小化参考应用：

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## 参考作业

- `jobs/python/` — 使用托管身份的 Python 定时作业

## 故障排查实验室

labs/ 文件夹中包含动手实验，配有 Bicep 模板，可重现真实的 Container Apps 问题。每个实验包括：

- 可证伪的假设和分步运行手册
- 真实的 Azure 部署数据 (KQL 日志、CLI 输出)
- 预期证据 (Expected Evidence) 章节，包含证伪逻辑
- 到相应实战手册的交叉链接

当前全部实验的证据包框架：**27/28 个证伪实验室 + 1 个指标证据基准 = 总计 28 个**。唯一的特例是 `labs/metrics-load-test/`，它是指标参考的数据源，而不是触发/修复/证伪实验室。

### ACR 网络路径系列

`labs/acr-network-path-*` 中的 5 个专题实验系列重现了 Container App 访问 Azure Container Registry 的五种不同网络路径：

- **路径 A — 防火墙允许列表** —— 通过 Azure Firewall SNAT 和 `networkRuleSet.ipRules` 允许列表切换的公共 ACR
- **路径 B — PE 直连** —— 带有 `privatelink.azurecr.io` 链接 DNS 区域的 ACR Premium 私有终结点
- **路径 C — PE 强制检查** —— 私有终结点 + Azure Firewall + `/32` UDR 路由（静默检查绕过类）
- **路径 D — 记录级区域权限** —— 链接的专用 DNS 区域中按记录的 DNS 权限故障
- **路径 E — DNS 转发器绕过** —— 绕过链接区域的自定义 DNS 解析器拓扑

有关命名和排序所有五种路径的概念分类，请参阅 [ACR 网络路径选择](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/networking/acr-network-path-selection/) 平台文档。

## 参与贡献

欢迎贡献！请参阅我们的 [贡献指南](https://yeongseon.github.io/azure-container-apps-practical-guide/contributing/) 了解以下内容：

- 仓库结构和内容组织
- 文档模板和写作标准
- CLI 命令风格和 PII 规则
- 本地开发设置和构建验证
- 拉取请求 (PR) 流程

## 相关项目

| 仓库 | 描述 |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines 实操指南 |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking 实操指南 |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage 实操指南 |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service 实操指南 |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions 实操指南 |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services 实操指南 |
| [azure-container-apps-practical-guide](https://github.com/yeongseon/azure-container-apps-practical-guide) | Azure Container Apps 实操指南 |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) 实操指南 |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture 实操指南 |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring 实操指南 |

## 免责声明

这是一个独立的社区项目。与 Microsoft 无关，也不受其认可。Azure 和 Container Apps 是 Microsoft Corporation 的商标。

## 许可证

[MIT](LICENSE)
