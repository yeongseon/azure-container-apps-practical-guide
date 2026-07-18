# Azure Container Apps 実務ガイド

📘 **ドキュメントサイト:** <https://yeongseon.github.io/azure-container-apps-practical-guide/>

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

[![Docs](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml)
[![CI](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Azure Container Apps でコンテナ化されたアプリケーションを実行するための、エビデンス駆動でオペレーター重視のガイドです。最初のデプロイから本番グレードの監視、アラート、インシデント対応まで、再現可能なラボ、メトリックキャプチャ、KQL サンプル、Microsoft Learn のリファレンスによって主要な運用ガイダンスがサポートされています。

## 内容の概要

| セクション | 説明 | ステータス |
|---------|-------------|--------|
| [ここから開始](https://yeongseon.github.io/azure-container-apps-practical-guide/) | 概要、学習パス、およびリポジトリマップ | 包括的 |
| [プラットフォーム](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | アーキテクチャ、環境、リビジョン、スケーリング、ネットワーク、ジョブ、ID | 包括的 |
| [ベストプラクティス](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | コンテナ設計、リビジョン戦略、スケーリング、ネットワーク、ID、信頼性、コスト | 包括的 |
| [言語別ガイド](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Python、Node.js、Java、および .NET のステップバイステップチュートリアル | 包括的 |
| [運用](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | デプロイ、モニタリング、スケーリング、アラート、シークレットローテーション、リカバリ | 包括的 |
| [トラブルシューティング](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | プレイブック、ハンズオンラボ、KQL クエリパック、決定木、エビデンスマップ | ラボで検証済み |
| [リファレンス](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI リファレンス、環境変数、プラットフォームの制限 | 包括的 |

**ステータスの凡例**: **ラボで検証済み** = 包括的 + 再現可能なラボでガイダンスを証明済み · **包括的** = セクション全体が完成し、MSLearn で検証済みの本番対応レベル · **公開済み** = 主要なコンテンツは揃っているが、現在も拡張中 · **進行中** = 部分的なコンテンツ、アクティブに開発中 · **計画中** = プレースホルダー、コンテンツは未着手

## 本ガイドの特徴

- **ラボで検証済み** — 再現可能な Bicep、検証スクリプト、エビデンスレポートを備えた包括的なハンズオンラボスイート
- **KQL クエリパック** — Log Analytics および App Insights 用の 30 以上の本番対応クエリ
- **メトリックリファレンス** — キャプチャ、分母の注釈、ディメンションマッピングを用いて解説されたプラットフォームメトリック
- **プレイブック** — 競合する仮説、決定フロー、CLI エビデンス収集を用いた構造化されたトラブルシューティング

## 言語別ガイド

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

各ガイドでは、ローカル開発、最初のデプロイ、構成、ロギング、Infrastructure as Code (IaC)、CI/CD、およびリビジョンとトラフィック分割について説明します。

## クイックスタート

```bash
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git
cd azure-container-apps-practical-guide

python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements-docs.txt

mkdocs serve
```

`http://127.0.0.1:8000` にアクセスして、ローカルでドキュメントを閲覧してください。

## リファレンスアプリケーション

Azure Container Apps のパターンを示す最小限のリファレンスアプリケーションです：

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## リファレンスジョブ

- `jobs/python/` — マネージド ID を使用した Python スケジュールジョブ

## トラブルシューティングラボ

`labs/` フォルダには、実際の Container Apps の問題を再現する Bicep テンプレートを使用したハンズオンラボが含まれています。各ラボの構成は以下の通りです：

- 反証可能な仮説とステップバイステップのランブック
- 実際の Azure デプロイデータ (KQL ログ、CLI 出力)
- 予想されるエビデンス (Expected Evidence) セクション (反証ロジック付き)
- 対応するプレイブックへのクロスリンク

現在のラボコーパス全体のエビデンスパックの構成：**27/28 の反証ラボ + 1 つのメトリックエビデンスベースライン = 計 28**。特殊な例外は `labs/metrics-load-test/` で、これはトリガー/修正/反証ラボではなく、メトリックリファレンスのデータソースです。

### ACR ネットワークパスシリーズ

`labs/acr-network-path-*` の 5 ラボシリーズは、Container App が Azure Container Registry に到達する 5 つの異なるネットワークパスを再現します：

- **Path A — ファイアウォール許可リスト** — Azure Firewall SNAT と `networkRuleSet.ipRules` 許可リスト切り替えを伴うパブリック ACR
- **Path B — PE 直接接続** — `privatelink.azurecr.io` リンクされた DNS ゾーンを使用する ACR Premium プライベートエンドポイント
- **Path C — PE 強制検査** — プライベートエンドポイント + Azure Firewall + `/32` UDR ルート (サイレント検査バイパスクラス)
- **Path D — レコードレベルゾーン権限** — リンクされたプライベート DNS ゾーンでのレコード単位の DNS 権限障害
- **Path E — DNS フォワーダーバイパス** — リンクされたゾーンをバイパスするカスタム DNS リゾルバートポロジー

5 つのパスの概念的な分類については、[ACR ネットワークパス選択](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/networking/acr-network-path-selection/) プラットフォームドキュメントを参照してください。

## 貢献

貢献を歓迎します！以下の詳細については、[貢献ガイド](https://yeongseon.github.io/azure-container-apps-practical-guide/contributing/) を参照してください：

- リポジトリの構造とコンテンツの構成
- ドキュメントテンプレートと執筆基準
- CLI コマンドのスタイルと PII ルール
- ローカル開発環境のセットアップとビルド検証
- プルリクエストのプロセス

## 関連プロジェクト

| リポジトリ | 説明 |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines 実務ガイド |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking 実務ガイド |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage 実務ガイド |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service 実務ガイド |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions 実務ガイド |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services 実務ガイド |
| [azure-container-apps-practical-guide](https://github.com/yeongseon/azure-container-apps-practical-guide) | Azure Container Apps 実務ガイド |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) 実務ガイド |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure アーキテクチャ実務ガイド |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure モニタリング実務ガイド |

## 免責事項

これは独立したコミュニティプロジェクトです。Microsoft との提携や承認を受けているものではありません。Azure および Container Apps は Microsoft Corporation の商標です。

## ライセンス

[MIT](LICENSE)
