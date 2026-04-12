# Azure Container Apps 実務ガイド

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

最初のデプロイから本番環境のトラブルシューティングまで、Azure Container Apps でコンテナ化されたアプリケーションを実行するための包括的なガイドです。

## 主な内容

| セクション | 説明 |
|---------|-------------|
| [ここから開始 (Start Here)](https://yeongseon.github.io/azure-container-apps-practical-guide/) | 概要、学習パス、およびリポジトリマップ |
| [プラットフォーム (Platform)](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | アーキテクチャ、環境、リビジョン、スケーリング、ネットワーク、ジョブ、ID |
| [ベストプラクティス (Best Practices)](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | コンテナ設計、リビジョン戦略、スケーリング、ネットワーク、ID、信頼性、コスト |
| [言語別ガイド (Language Guides)](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Python、Node.js、Java、および .NET のステップバイステップチュートリアル |
| [運用 (Operations)](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | デプロイ、モニタリング、スケーリング、アラート、シークレットローテーション、リカバリ |
| [トラブルシューティング (Troubleshooting)](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | プレイブック、ハンズオンラボ、KQL クエリパック、決定木、エビデンスマップ |
| [リファレンス (Reference)](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI リファレンス、環境変数、プラットフォームの制限 |

## 言語別ガイド

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

各ガイドでは、ローカル開発、最初のデプロイ、構成、ロギング、Infrastructure as Code (IaC)、CI/CD、およびリビジョンとトラフィック分割について説明します。

## クイックスタート

```bash
# リポジトリをクローン
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git

# MkDocs の依存関係をインストール
pip install mkdocs-material mkdocs-minify-plugin

# ローカルドキュメントサーバーを起動
mkdocs serve
```

ローカルで `http://127.0.0.1:8000` にアクセスしてドキュメントを閲覧してください。

## リファレンスアプリケーション

Azure Container Apps のパターンを示す最小限のリファレンスアプリケーションです：

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## リファレンスジョブ

- `jobs/python/` — マネージド ID を使用した Python スケジュールジョブ

## トラブルシューティングラボ (Troubleshooting Labs)

`labs/` フォルダには、実際の Container Apps の問題を再現する Bicep テンプレートを使用した 10 個のハンズオンラボが含まれています。各ラボの構成は以下の通りです：

- 反証可能な仮説とステップバイステップのランブック
- 実際の Azure デプロイデータ (KQL ログ、CLI 出力)
- 予想されるエビデンス (Expected Evidence) セクション (反証ロジック付き)
- 対応するプレイブックへのクロスリンク

## 貢献

貢献を歓迎します。以下の点を確認してください：

- すべての CLI の例で長いフラグを使用してください (`-g` ではなく `--resource-group`)
- すべてのドキュメントに Mermaid ダイアグラムを含めてください
- すべてのコンテンツは、ソース URL とともに Microsoft Learn を参照してください
- CLI 出力の例に個人情報 (PII) を含めないでください

## 関連プロジェクト

| リポジトリ | 説明 |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines 実務ガイド |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking 実務ガイド |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage 実務ガイド |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service 実務ガイド |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions 実務ガイド |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service 実務ガイド |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring 実務ガイド |

## 免責事項

これは独立したコミュニティプロジェクトです。Microsoft との提携や承認を受けているものではありません。Azure および Container Apps は Microsoft Corporation の商標です。

## ライセンス

[MIT](LICENSE)
