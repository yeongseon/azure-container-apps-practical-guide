---
hide:
  - toc
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/revisions
        - https://learn.microsoft.com/azure/container-apps/traffic-splitting
    - id: revision-traffic-splitting
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/revisions
        - https://learn.microsoft.com/azure/container-apps/traffic-splitting
---

# 07 - Revisions and Traffic Splitting

Azure Container Apps revisions provide immutable deployment snapshots of your .NET application. Use them for safe releases, canary traffic, and quick rollback to a known-good state.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, ACR with managed identity pull, and private endpoints for backend services.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
    ```mermaid
    flowchart TD
        INET[Internet] -->|HTTPS| CA["Container App\nConsumption\nLinux .NET 8"]

        subgraph VNET["VNet 10.0.0.0/16"]
            subgraph ENV_SUB["Environment Subnet 10.0.0.0/23\nDelegation: Microsoft.App/environments"]
                CAE[Container Apps Environment]
                CA
            end
            subgraph PE_SUB["Private Endpoint Subnet 10.0.2.0/24"]
                PE_ACR[PE: ACR]
                PE_KV[PE: Key Vault]
                PE_ST[PE: Storage]
            end
        end

        PE_ACR --> ACR[Azure Container Registry]
        PE_KV --> KV[Key Vault]
        PE_ST --> ST[Storage Account]

        subgraph DNS[Private DNS Zones]
            DNS_ACR[privatelink.azurecr.io]
            DNS_KV[privatelink.vaultcore.azure.net]
            DNS_ST[privatelink.blob.core.windows.net]
        end

        PE_ACR -.-> DNS_ACR
        PE_KV -.-> DNS_KV
        PE_ST -.-> DNS_ST

        CA -.->|System-Assigned MI| ENTRA[Microsoft Entra ID]
        CAE --> LOG[Log Analytics]
        CA --> AI[Application Insights]

        style CA fill:#107c10,color:#fff
        style VNET fill:#E8F5E9,stroke:#4CAF50
        style DNS fill:#E3F2FD
    ```

## Revision Traffic Splitting

<!-- diagram-id: revision-traffic-splitting -->
```mermaid
graph LR
    INGRESS[Ingress] -->|90%| V1[Revision v1]
    INGRESS -->|10%| V2[Revision v2]
```

## Prerequisites

- Completed [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- At least two deployed images/tags in your ACR
- Container App currently running in `multiple` revision mode or ready to switch

!!! tip "Define promotion criteria before traffic split"
    Decide in advance which metrics (ASP.NET Core error rates, Kestrel request latency, CPU saturation) must stay within threshold before increasing canary traffic.

## Step-by-step

1. **Set standard variables**

   ```bash
   RG="rg-dotnet-guide"
   DEPLOYMENT_NAME="main"
   BASE_NAME="dotnet-guide"

   APP_NAME=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerAppName.value" \
     --output tsv)

   ACR_NAME=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerRegistryName.value" \
     --output tsv)

   ACR_LOGIN_SERVER=$(az deployment group show \
     --name "$DEPLOYMENT_NAME" \
     --resource-group "$RG" \
     --query "properties.outputs.containerRegistryLoginServer.value" \
     --output tsv)
   ```

2. **Switch to multiple revision mode**

   By default, Container Apps operate in `single` revision mode (100% traffic to the latest). To split traffic, you must enable `multiple` mode.

   ```bash
   az containerapp revision set-mode \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --mode multiple
   ```

   ???+ example "Expected output"
       ```
       "Multiple"
       ```

3. **Deploy a new version to create a new revision**

   ```bash
   az acr build --registry "$ACR_NAME" --image "$BASE_NAME:v3" ./apps/dotnet-aspnetcore

   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --image "$ACR_LOGIN_SERVER/$BASE_NAME:v3"
   ```

   ???+ example "Expected output"
       ```json
       {
         "latestRevision": "<your-app-name>--xxxxxxx",
         "name": "<your-app-name>",
         "provisioningState": "Succeeded"
       }
       ```

4. **List revisions and identify target names**

   ```bash
   az containerapp revision list \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --query "[].{name:name,active:properties.active,createdTime:properties.createdTime}" \
     --output table
   ```

   ???+ example "Expected output"
        ```text
        Name                               Active    CreatedTime
        ---------------------------------  --------  -------------------------
        <your-app-name>--0000001           True      2026-04-04T16:00:00+00:00
        <your-app-name>--0000002           True      2026-04-04T16:30:00+00:00
        ```

5. **Apply canary traffic split (90/10)**

   Capture the revision names from the list above, then apply traffic weights:

   ```bash
   # Replace with your actual revision names from Step 4
   OLD_REV="${APP_NAME}--0000001"
   NEW_REV="${APP_NAME}--0000002"

   az containerapp ingress traffic set \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --revision-weight "$OLD_REV=90" "$NEW_REV=10"
   ```

   ???+ example "Expected output"
        ```json
        [
          {
            "revisionName": "<your-app-name>--0000001",
            "weight": 90
          },
          {
            "revisionName": "<your-app-name>--0000002",
            "weight": 10
          }
        ]
        ```

6. **Verify applied traffic routing**

   ```bash
   az containerapp ingress show \
     --name "$APP_NAME" \
     --resource-group "$RG"
   ```

   ???+ example "Expected output"
        ```json
        {
          "fqdn": "<your-app-name>.<env-suffix>.koreacentral.azurecontainerapps.io",
          "traffic": [
            { "revisionName": "<your-app-name>--0000001", "weight": 90 },
            { "revisionName": "<your-app-name>--0000002", "weight": 10 }
          ]
        }
        ```

7. **Rollback instantly if .NET exceptions increase**

   If the canary revision shows high error rates in Log Analytics, move all traffic back to the stable revision.

   ```bash
   az containerapp ingress traffic set \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --revision-weight "$OLD_REV=100"
   ```

8. **Deactivate the bad revision**

   ```bash
   az containerapp revision deactivate \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --revision "$NEW_REV"
   ```

## Operational Guidance for .NET

- **Health Probes**: Ensure your liveness and readiness probes (`/health`) are correctly configured so Container Apps doesn't route traffic to a revision that hasn't finished its .NET runtime startup.
- **Graceful Shutdown**: ASP.NET Core handles `SIGTERM` signals. When you shift traffic away from a revision, the platform waits for active connections to finish (up to the termination grace period) before stopping the container.
- **Sticky Sessions**: If your .NET app uses in-memory sessions (not recommended), traffic splitting will break session state unless you use an external provider like Redis.

## Advanced Topics

- **Blue/Green Deployment**: Use labels to route traffic to specific revisions without modifying weights until the "Green" revision is fully verified.
- **Dapr service invocation**: Dapr can be configured to respect traffic splitting or route to specific revisions using headers.
- **Automated Promotion**: Use GitHub Actions to increase traffic weight automatically if health checks and telemetry thresholds are met.

!!! warning "Cleanup Stale Revisions"
    Deactivate or delete old revisions once they are no longer needed for rollback. This simplifies your environment and reduces the risk of accidental traffic assignment.

## See Also
- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- [Revision Management Operations](../../operations/revision-management/index.md)

## Sources
- [Revisions in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions)
- [Traffic splitting (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/traffic-splitting)
