# Azure Container Apps 实操指南

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

从首次部署到生产环境故障排除，在 Azure Container Apps 上运行容器化应用程序的全方位指南。

## 主要内容

| 章节 | 描述 |
|---------|-------------|
| [从这里开始 (Start Here)](https://yeongseon.github.io/azure-container-apps-practical-guide/) | 概述、学习路径和仓库地图 |
| [平台 (Platform)](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | 架构、环境、修订版、扩展、网络、作业、身份 |
| [最佳实践 (Best Practices)](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | 容器设计、修订版策略、扩展、网络、身份、可靠性、成本 |
| [语言指南 (Language Guides)](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Python、Node.js、Java 和 .NET 的分步教程 |
| [运营 (Operations)](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | 部署、监控、扩展、告警、密钥轮换、恢复 |
| [故障排除 (Troubleshooting)](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | 实战手册、动手实验、KQL 查询包、决策树、证据图 |
| [参考 (Reference)](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI 参考、环境变量、平台限制 |

## 语言指南

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

每个指南都涵盖：本地开发、首次部署、配置、日志记录、基础设施即代码 (IaC)、CI/CD 和修订版与流量分配。

## 快速入门

```bash
# 克隆仓库
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git

# 安装 MkDocs 依赖
pip install mkdocs-material mkdocs-minify-plugin

# 启动本地文档服务器
mkdocs serve
```

访问 `http://127.0.0.1:8000` 在本地浏览文档。

## 参考应用程序

展示 Azure Container Apps 模式的最小化参考应用程序：

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## 参考作业

- `jobs/python/` — 使用托管身份的 Python 定时作业

## 故障排除实验 (Troubleshooting Labs)

`labs/` 文件夹中包含 10 个动手实验，配有 Bicep 模板，可重现真实的 Container Apps 问题。每个实验包括：

- 可证伪的假设和分步运行手册
- 真实的 Azure 部署数据 (KQL 日志、CLI 输出)
- 预期证据 (Expected Evidence) 章节 (包含证伪逻辑)
- 到相应实战手册的交叉链接

## 贡献

欢迎贡献。请确保：

- 所有 CLI 示例使用长标记 (使用 `--resource-group` 而不是 `-g`)
- 所有文档包含 Mermaid 图表
- 所有内容参考 Microsoft Learn 并附带源 URL
- CLI 输出示例中不含个人身份信息 (PII)

## 相关项目

| 仓库 | 描述 |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines 实操指南 |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking 实操指南 |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage 实操指南 |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service 实操指南 |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions 实操指南 |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service 实操指南 |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring 实操指南 |

## 免责声明

这是一个独立的社区项目。与 Microsoft 无关，也不受其认可。Azure 和 Container Apps 是 Microsoft Corporation 的商标。

## 许可证

[MIT](LICENSE)
