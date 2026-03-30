# Azure Portal Screenshots Guide

This guide provides URLs for capturing Azure Portal screenshots for documentation.

## Resource Information

| Resource Type | Name | Portal URL |
|---------------|------|------------|
| Resource Group | `rg-container-apps-python` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/overview) |
| Container App | `ca-pycontainer-zxyaw4an5c742` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/providers/Microsoft.App/containerApps/ca-pycontainer-zxyaw4an5c742/overview) |
| Container Apps Environment | `cae-pycontainer-zxyaw4an5c742` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/providers/Microsoft.App/managedEnvironments/cae-pycontainer-zxyaw4an5c742/overview) |
| Container Registry | `crpycontainerzxyaw4an5c742` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/providers/Microsoft.ContainerRegistry/registries/crpycontainerzxyaw4an5c742/overview) |
| Application Insights | `appi-pycontainer-zxyaw4an5c742` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/providers/microsoft.insights/components/appi-pycontainer-zxyaw4an5c742/overview) |
| Log Analytics | `log-pycontainer-zxyaw4an5c742` | [Open in Portal](https://portal.azure.com/#@/resource/subscriptions/1375a781-21fb-430a-be54-2465c36b0ee2/resourceGroups/rg-container-apps-python/providers/Microsoft.OperationalInsights/workspaces/log-pycontainer-zxyaw4an5c742/overview) |

## Recommended Screenshots

### 1. Container App Overview
- **URL**: Container App → Overview
- **What to capture**: App URL, replicas, revision status
- **Save as**: `portal-01-container-app-overview.png`

### 2. Container App Revisions
- **URL**: Container App → Revisions
- **What to capture**: Active revision, traffic split
- **Save as**: `portal-02-revisions.png`

### 3. Container App Logs
- **URL**: Container App → Log stream
- **What to capture**: Real-time application logs
- **Save as**: `portal-03-log-stream.png`

### 4. Container Apps Environment
- **URL**: Container Apps Environment → Overview
- **What to capture**: Environment details, apps list
- **Save as**: `portal-04-environment.png`

### 5. Application Insights
- **URL**: Application Insights → Overview
- **What to capture**: Request metrics, performance
- **Save as**: `portal-05-app-insights.png`

### 6. Application Map
- **URL**: Application Insights → Application map
- **What to capture**: Distributed tracing visualization
- **Save as**: `portal-06-application-map.png`

### 7. Live Metrics
- **URL**: Application Insights → Live Metrics
- **What to capture**: Real-time request stream
- **Save as**: `portal-07-live-metrics.png`

### 8. Container Registry
- **URL**: Container Registry → Repositories
- **What to capture**: Image list, tags
- **Save as**: `portal-08-acr-repositories.png`

## How to Capture

1. Open the Portal URL in your browser
2. Wait for the page to fully load
3. Use browser screenshot tool or Snipping Tool
4. Save to `docs/screenshots/` directory
5. Use 1280x720 or higher resolution

## Current App Screenshots (Automated)

| Screenshot | Description |
|------------|-------------|
| `01-health-endpoint.png` | Health check endpoint response |
| `02-info-endpoint.png` | App info endpoint response |
| `03-log-levels.png` | Log levels demo response |
| `04-external-dependency.png` | External API call response |
| `05-exception-endpoint.png` | Exception handling response |
