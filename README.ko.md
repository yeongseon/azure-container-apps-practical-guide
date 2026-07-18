# Azure Container Apps 실무 가이드

📘 **문서 사이트:** <https://yeongseon.github.io/azure-container-apps-practical-guide/>

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

[![Docs](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/docs.yml)
[![CI](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml/badge.svg)](https://github.com/yeongseon/azure-container-apps-practical-guide/actions/workflows/app-tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Azure Container Apps에서 컨테이너화된 애플리케이션을 실행하기 위한 증거 기반의 운영자 중심 가이드입니다. 첫 배포부터 운영 수준의 모니터링, 알림 및 사고 대응에 이르기까지, 주요 운영 지침은 재현 가능한 랩(Lab), 메트릭 캡처, KQL 예제 및 Microsoft Learn 참조를 통해 지원됩니다.

## 주요 내용

| 섹션 | 설명 | 상태 |
|---------|-------------|--------|
| [시작하기 (Start Here)](https://yeongseon.github.io/azure-container-apps-practical-guide/) | 개요, 학습 경로 및 저장소 맵 | Comprehensive |
| [플랫폼 (Platform)](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/) | 아키텍처, 환경, 리비전, 스케일링, 네트워킹, 작업, ID | Comprehensive |
| [베스트 프랙티스 (Best Practices)](https://yeongseon.github.io/azure-container-apps-practical-guide/best-practices/) | 컨테이너 설계, 리비전 전략, 스케일링, 네트워킹, ID, 안정성, 비용 | Comprehensive |
| [언어별 가이드 (Language Guides)](https://yeongseon.github.io/azure-container-apps-practical-guide/language-guides/) | Python, Node.js, Java, .NET을 위한 단계별 튜토리얼 | Comprehensive |
| [운영 (Operations)](https://yeongseon.github.io/azure-container-apps-practical-guide/operations/) | 배포, 모니터링, 스케일링, 알림, 시크릿 로테이션, 복구 | Comprehensive |
| [트러블슈팅 (Troubleshooting)](https://yeongseon.github.io/azure-container-apps-practical-guide/troubleshooting/) | 플레이북, 실습 랩, KQL 쿼리 팩, 의사 결정 트리, 증거 맵 | Lab-validated |
| [참조 (Reference)](https://yeongseon.github.io/azure-container-apps-practical-guide/reference/) | CLI 참조, 환경 변수, 플랫폼 제한 사항 | Comprehensive |

**상태 범례**: **Lab-validated** = 포괄적인 지침과 함께 이를 증명하는 재현 가능한 랩 제공 · **Comprehensive** = Microsoft Learn 기반의 검증을 마친 운영 환경에 즉시 적용 가능한 완성된 섹션 · **Published** = 핵심 콘텐츠는 포함되어 있으나 계속 확장 중 · **In progress** = 일부 콘텐츠 포함, 현재 활발히 작성 중 · **Planned** = 플레이스홀더 상태, 아직 콘텐츠 작성이 시작되지 않음

## 차별점

- **Lab-validated** — Bicep, 검증 스크립트 및 증거 보고서를 통해 재현 가능한 포괄적인 실습 랩 제품군
- **KQL 쿼리 팩** — Log Analytics 및 App Insights를 위한 30개 이상의 운영 환경용 쿼리
- **메트릭 참조** — 캡처 화면, 분모 참고 사항 및 디멘션 매핑과 함께 설명된 플랫폼 메트릭
- **플레이북** — 대립 가설, 의사 결정 흐름 및 CLI 증거 수집을 포함한 구조화된 트러블슈팅

## 언어별 가이드

- **Python** (Flask + Gunicorn)
- **Node.js** (Express)
- **Java** (Spring Boot)
- **.NET** (ASP.NET Core)

각 가이드는 로컬 개발, 첫 배포, 설정, 로깅, 코드형 인프라(IaC), CI/CD, 그리고 리비전 및 트래픽 분할을 다룹니다.

## 빠른 시작

```bash
git clone https://github.com/yeongseon/azure-container-apps-practical-guide.git
cd azure-container-apps-practical-guide

python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements-docs.txt

mkdocs serve
```

로컬에서 `http://127.0.0.1:8000`에 접속하여 문서를 확인하세요.

## 참조 애플리케이션

Azure Container Apps 패턴을 보여주는 최소한의 참조 애플리케이션들입니다:

- `apps/python/` — Flask + Gunicorn
- `apps/nodejs/` — Express
- `apps/java-springboot/` — Spring Boot
- `apps/dotnet-aspnetcore/` — ASP.NET Core

## 참조 작업

- `jobs/python/` — 관리 ID를 사용하는 Python 예약 작업

## 트러블슈팅 실험

`labs/` 폴더에는 실제 Container Apps 이슈를 재현하는 Bicep 템플릿과 함께 실습 실험이 포함되어 있습니다. 각 실험은 다음을 포함합니다:

- 반증 가능한 가설 및 단계별 런북
- 실제 Azure 배포 데이터 (KQL 로그, CLI 출력)
- 예상 증거(Expected Evidence) 섹션 (반증 논리 포함)
- 관련 플레이북과의 교차 링크

현재 랩 코퍼스 전체의 증거 팩 구성: **27/28개의 반증 실험 + 1개의 메트릭 증거 베이스라인 = 총 28개**. 특별한 예외인 `labs/metrics-load-test/`는 트리거/수정/반증 실험이 아닌 메트릭 참조를 위한 데이터 소스입니다.

### ACR 네트워크 경로 시리즈

`labs/acr-network-path-*`에 있는 5개 실험 시리즈는 Container App이 Azure Container Registry에 접근하는 5가지 서로 다른 네트워크 경로를 재현합니다:

- **경로 A — 방화벽 허용 목록** — Azure Firewall SNAT와 `networkRuleSet.ipRules` 허용 목록 토글이 있는 공용 ACR
- **경로 B — PE 직접 연결** — `privatelink.azurecr.io` 연결된 DNS 영역이 있는 ACR Premium 사설 엔드포인트
- **경로 C — PE 강제 검사** — 사설 엔드포인트 + Azure Firewall + `/32` UDR 경로 (무증상 검사 우회 유형)
- **경로 D — 레코드 수준 영역 권한** — 연결된 사설 DNS 영역에서 레코드 단위 DNS 권한 실패
- **경로 E — DNS 포워더 우회** — 연결된 영역을 우회하는 사용자 지정 DNS 리졸버 토폴로지

5가지 경로의 개념적 분류는 [ACR 네트워크 경로 선택](https://yeongseon.github.io/azure-container-apps-practical-guide/platform/networking/acr-network-path-selection/) 플랫폼 문서를 참조하세요.

## 기여하기

기여는 언제나 환영합니다! 다음 사항은 [기여 가이드](https://yeongseon.github.io/azure-container-apps-practical-guide/contributing/)를 참조하세요:

- 저장소 구조 및 콘텐츠 구성
- 문서 템플릿 및 작성 표준
- CLI 명령어 스타일 및 PII 규칙
- 로컬 개발 환경 설정 및 빌드 검증
- 풀 리퀘스트(PR) 프로세스

## 관련 프로젝트

| 저장소 | 설명 |
|---|---|
| [azure-virtual-machine-practical-guide](https://github.com/yeongseon/azure-virtual-machine-practical-guide) | Azure Virtual Machines 실무 가이드 |
| [azure-networking-practical-guide](https://github.com/yeongseon/azure-networking-practical-guide) | Azure Networking 실무 가이드 |
| [azure-storage-practical-guide](https://github.com/yeongseon/azure-storage-practical-guide) | Azure Storage 실무 가이드 |
| [azure-app-service-practical-guide](https://github.com/yeongseon/azure-app-service-practical-guide) | Azure App Service 실무 가이드 |
| [azure-functions-practical-guide](https://github.com/yeongseon/azure-functions-practical-guide) | Azure Functions 실무 가이드 |
| [azure-communication-services-practical-guide](https://github.com/yeongseon/azure-communication-services-practical-guide) | Azure Communication Services 실무 가이드 |
| [azure-container-apps-practical-guide](https://github.com/yeongseon/azure-container-apps-practical-guide) | Azure Container Apps 실무 가이드 |
| [azure-kubernetes-service-practical-guide](https://github.com/yeongseon/azure-kubernetes-service-practical-guide) | Azure Kubernetes Service (AKS) 실무 가이드 |
| [azure-architecture-practical-guide](https://github.com/yeongseon/azure-architecture-practical-guide) | Azure Architecture 실무 가이드 |
| [azure-monitoring-practical-guide](https://github.com/yeongseon/azure-monitoring-practical-guide) | Azure Monitoring 실무 가이드 |

## 면책 조항

이 프로젝트는 독립적인 커뮤니티 프로젝트입니다. Microsoft와 제휴하거나 보증을 받지 않았습니다. Azure 및 Container Apps는 Microsoft Corporation의 상표입니다.

## 라이선스

[MIT](LICENSE)
