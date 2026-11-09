---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/networking
        - https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull
        - https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link
    - id: monitoring-workflow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/azure-monitor/app/java-in-process-agent
        - https://learn.microsoft.com/en-us/azure/container-apps/log-options
        - https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 04 - Logging and Monitoring

Azure Container Apps provides native support for observability through Azure Monitor, Log Analytics, and Application Insights. This guide covers how to configure structured logging and monitor your Spring Boot application in production.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet and private ACR access using managed identity.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "10px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 55}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Java tutorial
    accDescr: Client requests and responses pass through managed ingress. The customer VNet and private-endpoint subnet host the ACR private endpoint and link its DNS zone. Managed identity is assigned to the app and authorizes registry pulls, while platform provisioning exchanges image traffic with ACR through the private endpoint.
    CALLER(["Client"])
    VNET["VNet + PE<br/>subnet"]
    IDENTITY["Managed identity"]
    PE_ACR["ACR PE"]
    ACR["ACR"]
    DNS["ACR DNS zone"]
    subgraph ENV["ACA environment"]
        INGRESS["Ingress"]
        APP["Container app<br/>Java"]
        REVISION["Revision config"]
        REPLICAS["Replicas"]
        PLATFORM["Provisioning<br/>(platform)"]
    end
    CALLER ~~~ INGRESS ~~~ REPLICAS ~~~ REVISION ~~~ APP ~~~ IDENTITY ~~~ ACR ~~~ PE_ACR ~~~ PLATFORM ~~~ DNS ~~~ VNET
    CALLER ==>|"Request"| INGRESS
    INGRESS ==>|"Response"| CALLER
    INGRESS ==>|"Request"| REPLICAS
    REPLICAS ==>|"Response"| INGRESS
    VNET -.-> ENV
    VNET -.-> PE_ACR
    DNS -.-> VNET
    APP -.-> IDENTITY
    IDENTITY -.-> ACR
    APP -.-> REVISION
    REVISION -.-> REPLICAS
    PLATFORM -.-> REVISION
    PLATFORM ==>|"Pull"| PE_ACR
    PE_ACR ==>|"Pull"| ACR
    ACR ==>|"Layers"| PE_ACR
    PE_ACR ==>|"Layers"| PLATFORM
    PE_ACR -.-> DNS
```

*Figure: Client traffic crosses managed ingress to the replicas. The customer VNet and private-endpoint subnet host the ACR private endpoint and link its DNS zone. Managed identity is assigned to the app and authorizes registry pulls through a role assignment; platform provisioning remains the image-pull actor, and both pull requests and layer responses pass through the private endpoint.*

## Monitoring Workflow

<!-- diagram-id: monitoring-workflow -->
```mermaid
flowchart TD
    accTitle: Logging and telemetry paths for the Java container app
    accDescr: Spring Boot console and Container Apps system logs use the environment's direct Log Analytics destination and custom tables. The Java agent sends application telemetry to Application Insights, while platform metrics are available through Azure Monitor.
    APP["Spring Boot app<br/>stdout and stderr"]
    PLATFORM["Container Apps platform<br/>system events"]
    CONSOLE["Console log stream"]
    SYSTEM["System log stream"]
    LAW["Log Analytics workspace<br/>direct environment destination"]
    CONSOLE_TABLE["ContainerAppConsoleLogs_CL<br/>Log_s and RevisionName_s"]
    SYSTEM_TABLE["ContainerAppSystemLogs_CL<br/>Log_s and RevisionName_s"]
    AGENT["Application Insights<br/>Java agent"]
    AI["Application Insights"]
    AZMON["Azure Monitor metrics<br/>requests, CPU, memory, replicas"]
    APP --> CONSOLE
    PLATFORM --> SYSTEM
    CONSOLE ==>|"Log records"| LAW
    SYSTEM ==>|"Log records"| LAW
    LAW --> CONSOLE_TABLE
    LAW --> SYSTEM_TABLE
    APP ==>|"Application telemetry"| AGENT
    AGENT ==>|"Telemetry export"| AI
    PLATFORM -.->|"Platform measurements"| AZMON
```

*Figure: This tutorial uses the direct Log Analytics custom-table destination, so KQL queries target the `*_CL` custom tables and `_s` columns. An environment configured with the Azure Monitor destination instead requires diagnostic settings; resource-specific native tables require `--export-to-resource-specific true`. Container Apps platform measurements are available separately through Azure Monitor metrics.*

## Prerequisites

- Existing Azure Container App (created in [02 - First Deploy](02-first-deploy.md))
- Azure CLI 2.57+
- Azure Monitor Workspace (created automatically with Azure Container Apps environment)

## Structured Logging

For production, Spring Boot should output logs to `stdout` in a format that's easy for log collectors to parse. JSON format is recommended.

### 1. Logback Configuration

The reference application includes a `src/main/resources/logback-spring.xml` file configured for structured logging.

```xml
<!-- Example logback-spring.xml snippet -->
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <!-- Custom fields for Azure integration -->
            <field name="containerApp">${CONTAINER_APP_NAME}</field>
            <field name="revision">${CONTAINER_APP_REVISION}</field>
        </encoder>
    </appender>
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>
</configuration>
```

### 2. View Logs via CLI

Stream logs directly from your container app for real-time debugging:

```bash
az containerapp logs show \
  --resource-group $RG \
  --name $APP_NAME \
  --follow \
  --tail 100
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show ...` | Runs the Azure CLI operation required by the documented step. |

???+ example "Expected output"
    ```text
    {"timestamp":"2026-04-05T10:00:00.000Z","level":"INFO","logger":"com.example.demo.DemoApplication","message":"Started DemoApplication in 8.67 seconds","containerApp":"<your-app-name>","revision":"<your-app-name>--xxxxxxx"}
    ```

## Application Insights Integration

Azure Monitor's Application Insights provides distributed tracing, performance monitoring, and live metrics.

### 1. Enable Application Insights

The easiest way to enable Application Insights for Spring Boot is using the [Java In-Process Agent](https://learn.microsoft.com/en-us/azure/azure-monitor/app/java-in-process-agent).

```bash
# Add Application Insights Connection String
INSTRUMENTATION_KEY=$(az monitor app-insights component show --app $APP_NAME --resource-group $RG --query "connectionString" --output tsv)

az containerapp update \
  --resource-group $RG \
  --name $APP_NAME \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=$INSTRUMENTATION_KEY"
```

| Command | Why it is used |
|---|---|
| `az monitor app-insights ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

### 2. Spring Boot Actuator

Ensure Spring Boot Actuator endpoints are exposed to provide health and metrics data to Azure Monitor.

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: always
```

## Querying Logs with KQL via CLI

Use the Azure CLI to query logs directly from the command line. This is essential for automated monitoring and CI/CD pipelines.

### Get Log Analytics Workspace ID

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace list \
  --resource-group $RG \
  --query "[0].customerId" \
  --output tsv)
```

| Command | Purpose |
|---|---|
| `WORKSPACE_ID=$(az monitor log-analytics workspace list --resource-group $RG --query "[0].customerId" --output tsv)` | Captures the customer ID of the first Log Analytics workspace returned in the resource group, which is sufficient here because this tutorial provisions a single workspace and then queries it from the CLI. |

### Query Console Logs

```bash
# Use the APP_NAME variable set in 02-first-deploy.md
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == '$APP_NAME' | project TimeGenerated, ContainerAppName_s, Log_s | take 5" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az monitor log-analytics ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

???+ example "Expected output"
    ```text
    ContainerAppName_s    Log_s                                      TimeGenerated
    --------------------  -----------------------------------------  ----------------------------
    <your-app-name>       .   ____          _            __ _ _      2026-04-04T16:03:47.659Z
    <your-app-name>       /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \    2026-04-04T16:03:47.659Z
    <your-app-name>       Started DemoApplication in 8.67 seconds    2026-04-04T16:04:00.123Z
    ```

### Query Error Logs

```bash
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == '$APP_NAME' | where Log_s contains 'ERROR' | project TimeGenerated, Log_s | take 10" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az monitor log-analytics ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

### Query System Logs (Startup Events)

```bash
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "ContainerAppSystemLogs_CL | where ContainerAppName_s == '$APP_NAME' | project TimeGenerated, Reason_s, Log_s | take 5" \
  --output table
```

| Command | Why it is used |
|---|---|
| `az monitor log-analytics ...` | Creates or inspects Azure Monitor alerts, diagnostic settings, or metrics. |

???+ example "Expected output"
    ```text
    Log_s                                                                         Reason_s            TimeGenerated
    ----------------------------------------------------------------------------  ------------------  ----------------------------
    Updating containerApp: <your-app-name>                                        ContainerAppUpdate  2026-04-04T16:03:06.835Z
    Replica '<your-app-name>--9kvcb6d-...' has been scheduled to run on a node.   AssigningReplica    2026-04-04T16:03:06.835Z
    KEDA is starting a watch for revision '<your-app-name>--9kvcb6d'...           KEDAScalersStarted  2026-04-04T16:03:06.835Z
    ```

## Monitoring Checklist

- [x] Application logs are written to `stdout` (not to a local file)
- [x] Log level is configurable via environment variable (`LOGGING_LEVEL_ROOT`)
- [x] Application Insights is receiving data (Traces, Exceptions, Requests)
- [x] Spring Boot Actuator endpoints are accessible and returning metrics

!!! warning "Avoid excessive logging"
    In a high-throughput production environment, avoid logging large request/response bodies or sensitive information (PII). Use `INFO` level for normal operations and `DEBUG` only when troubleshooting.

### Verify log stream in Azure Portal

![Container App|ca-java-d38538|Log stream|Real-time|Category|Application|Based on revision|ca-java-d38538--0000001|Replica|ca-java-d38538--0000001-646ffd66f5-hxkbc|Container|ca-java-d38538](../../../assets/language-guides/java/tutorial/04-log-stream-blade.png)

**[Observed]** `Microsoft Azure (Preview)`. `Report a bug`. `Search resources, services, and docs (G+/)`. `Copilot`. `Home`. `ca-java-d38538`. `Container App`. `Log stream`. `Refresh`. `Send us your feedback`. `Historical`. `Real-time`. `Category`. `System`. `Application`. `Based on revision`. `ca-java-d38538--0000001`. `Not seeing your revision?`. `Click here to find and activate an existing revision.`. `Replica`. `ca-java-d38538--0000001-646ffd66f5-hxkbc`. `Container`. `ca-java-d38538`. `Reconnect`. `Stop`. `Copy`. `Clear`. `Maximize`. `Connecting to stream...`. `Connecting to the container 'ca-java-d38538'...`. `Successfully Connected to container: 'ca-java-d38538' [Revision: 'ca-java-d38538--0000001', Replica: 'ca-java-d38538--0000001-646ffd66f5-hxkbc']`. `Spring Boot`. `(v3.3.0)`. `Starting DemoApplication v1.0.0 using Java 21.0.11 with PID 1`. `com.example.demo.DemoApplication`. `Tomcat initialized with port 8000 (http)`. `Tomcat started on port 8000 (http) with context path '/'`. `Started DemoApplication in 2.912 seconds`. `No logs since last 60 seconds`. `Overview`. `Activity log`. `Access control (IAM)`. `Tags`. `Diagnose and solve problems`. `Resource visualizer`. `Application`. `Revisions and replicas`. `Containers`. `Scale`. `Volumes`. `Settings`. `Networking`. `Ingress`. `Custom domains`. `CORS`. `Security`. `Monitoring`. `Log stream`. `Logs`. `Console`. `Alerts`. `Metrics`. `Dashboards with Grafana`. `Advisor recommendations`.

**[Inferred]** The `Real-time` radio appears to map to the live tail behavior triggered by `az containerapp logs show --follow` in [View Logs via CLI](#2-view-logs-via-cli). The `Category` toggle value `Application` appears consistent with the `stdout` JSON output produced by the `net.logstash.logback.encoder.LogstashEncoder` `CONSOLE` appender configured in [Logback Configuration](#1-logback-configuration). The `Based on revision` selector value `ca-java-d38538--0000001` appears consistent with the revision-scoped log stream surfaced by `az containerapp logs show` in [View Logs via CLI](#2-view-logs-via-cli). The `Successfully Connected to container: 'ca-java-d38538'` line appears consistent with the live tail connection initiated by `az containerapp logs show --follow` in [View Logs via CLI](#2-view-logs-via-cli).

**[Not Proven]** Additional log query output and monitoring configuration detail are not visible on this view.

## See Also
- [07 - Revisions and Traffic](07-revisions-traffic.md)
- [Troubleshooting Playbooks](../../../troubleshooting/playbooks/index.md)
- [KQL Query Pack](../../../troubleshooting/kql/index.md)

## Sources
- [Container Apps networking (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Managed identity image pull (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry private link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [Log storage and monitoring options (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/log-options)
- [Log monitoring with Log Analytics (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/log-monitoring)
- [Azure Monitor Application Insights for Java (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/azure-monitor/app/java-in-process-agent)
- [Spring Boot Logging (Documentation)](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.logging)
- [Monitor Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/monitor)
