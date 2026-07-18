---
content_sources:
  diagrams:
    - id: this-tutorial-assumes-a-production-ready-container
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
    - id: revision-traffic-splitting
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
validation:
  az_cli:
    last_tested:
    cli_version:
    result: not_tested
  bicep:
    last_tested:
    result: not_tested
---
# 07 - Revisions and Traffic Splitting

Azure Container Apps revisions provide immutable deployment snapshots. Use them for safe releases, canary traffic, and quick rollback.

!!! info "Infrastructure Context"
    **Service**: Container Apps (Consumption) | **Network**: VNet integrated | **VNet**: ✅

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet, ACR with managed identity pull, and private endpoints for backend services.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
flowchart TD
    INET[Internet] -->|HTTPS| CA["Container App\nConsumption\nLinux Node 18 LTS"]

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
graph TD
    INGRESS[Ingress] -->|90%| V1[Revision v1]
    INGRESS -->|10%| V2[Revision v2]
```

## Prerequisites

- Completed [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- At least two deployed images/tags

!!! tip "Define promotion criteria before traffic split"
    Decide in advance which metrics (error rate, latency percentile, saturation) must stay within threshold before increasing canary traffic.

## Step-by-step

1. **Set standard variables**

    ```bash
    RG="rg-nodejs-guide"
    BASE_NAME="nodejs-guide"
    DEPLOYMENT_NAME="main"

    APP_NAME=$(az deployment group show \
      --name "$DEPLOYMENT_NAME" \
      --resource-group "$RG" \
      --query "properties.outputs.containerAppName.value" \
      --output tsv)
    ```

    | Command | Purpose |
    |---|---|
    | `APP_NAME=$(az deployment group show --name "$DEPLOYMENT_NAME" --resource-group "$RG" --query "properties.outputs.containerAppName.value" --output tsv)` | Captures the deployed app name so revision-mode and traffic-splitting commands apply to the correct Node.js app. |

2. **Switch to multiple revision mode**

    ```bash
    az containerapp revision set-mode \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --mode multiple
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp revision set-mode --name "$APP_NAME" --resource-group "$RG" --mode multiple` | Switches the app into multiple revision mode so you can keep old and new Node.js revisions active at the same time for traffic splitting. |

    ???+ example "Expected output"
        ```text
        "Multiple"
        ```

3. **Deploy a new version to create a new revision**

    ```bash
    az acr build --registry "$ACR_NAME" --image "$BASE_NAME:v3" ./apps/nodejs

    az containerapp update \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --image "$ACR_LOGIN_SERVER/$BASE_NAME:v3"
    ```

    | Command | Why it is used |
    |---|---|
    | `az acr build --registry ...` | Builds and pushes the container image to Azure Container Registry. |

    ???+ example "Expected output"
        `az acr build` takes 1-2 minutes. The `az containerapp update` returns:
        ```json
        {
          "latestRevision": "<your-app-name>--xxxxxxx",
          "name": "<your-app-name>",
          "provisioningState": "Succeeded"
        }
        ```

4. **List revisions and choose targets**

    ```bash
    az containerapp revision list \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --query "[].{name:name,active:properties.active,createdTime:properties.createdTime}" \
      --output table
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp revision list ...` | Lists revisions so rollout state, traffic, and health can be verified. |

    ???+ example "Expected output"
        ```text
        Name                                     Active    CreatedTime
        ---------------------------------------  --------  -------------------------
        <your-app-name>--0000001                 True      2026-04-05T10:00:00+00:00
        <your-app-name>--0000002                 True      2026-04-05T10:15:00+00:00
        ```

5. **Apply canary traffic split (90/10)**

    ```bash
    # Capture revision names from the list above
    STABLE_REV="${APP_NAME}--0000001"
    CANARY_REV="${APP_NAME}--0000002"

    az containerapp ingress traffic set \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --revision-weight "$STABLE_REV=90" "$CANARY_REV=10"
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp ingress traffic ...` | Runs the Azure CLI operation required by the documented step. |

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

6. **Rollback instantly if errors increase**

    ```bash
    az containerapp ingress traffic set \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --revision-weight "$STABLE_REV=100"
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp ingress traffic ...` | Runs the Azure CLI operation required by the documented step. |

    ???+ example "Expected output"
        ```json
        [
          {
            "revisionName": "<your-app-name>--0000001",
            "weight": 100
          }
        ]
        ```

7. **Deactivate bad revision after confirmation**

    ```bash
    az containerapp revision deactivate \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --revision "$CANARY_REV"
    ```

    | Command | Why it is used |
    |---|---|
    | `az containerapp revision deactivate ...` | Runs the Azure CLI operation required by the documented step. |

    ???+ example "Expected output"
        ```text
        "Deactivate succeeded"
        ```

### Verify revisions and traffic in Azure Portal

![ca-nodejs-d38538 | Container App | Revisions and replicas | Create new revision | Save | Refresh | Deployment mode | Send us your feedback | Active revisions | Inactive revisions | Replicas | Name | Date created | 6/4/2026, 5:33:42 PM | Running status | View Logs | Label | Traffic | Replicas | ca-nodejs-d38538--0000001 | Running | 100 % | 1](../../../assets/language-guides/nodejs/tutorial/07-revisions-and-replicas-blade.png)

**[Observed]** `ca-nodejs-d38538`. `Container App`. `Revisions and replicas`. `Create new revision`. `Save`. `Refresh`. `Deployment mode`. `Send us your feedback`. `Learn more`. `Active revisions`. `Inactive revisions`. `Replicas`. `Name`. `Date created`. `Running status`. `View Logs`. `Label`. `Traffic`. `ca-nodejs-d38538--0000001`. `6/4/2026, 5:33:42 PM`. `Running`. `View details`. `Show Logs`. `100`. `%`. `1`. `Show replicas`. `Application`. `Revisions and replicas`. `Containers`. `Scale`. `Volumes`. `Settings`. `Networking`. `Ingress`. `Custom domains`. `CORS`. `Security`. `Monitoring`. `Log stream`. `Logs`. `Console`. `Alerts`. `Metrics`.

**[Inferred]** The `Deployment mode` toolbar action appears to map to the same lever set by `az containerapp revision set-mode --mode multiple` in [Step-by-step](#step-by-step) Step 2. The `Create new revision` toolbar action is consistent with the new-revision effect of `az containerapp update --image` in [Step-by-step](#step-by-step) Step 3. The `Active revisions` and `Inactive revisions` tabs are consistent with the `revision list` and `revision deactivate` operations in [Step-by-step](#step-by-step) Steps 4 and 7. The `Traffic` column value `100 %` for `ca-nodejs-d38538--0000001` appears to map to the per-revision weight set by `az containerapp ingress traffic set --revision-weight` in [Step-by-step](#step-by-step) Steps 5 and 6.

**[Not Proven]** Additional revision detail and traffic-split detail are not visible on this view.

## Node.js Revision Management

When using multiple revisions with Node.js, ensure your application handles statelessness correctly. Session data should be stored in an external cache like Azure Cache for Redis to prevent user impact when traffic is split between different revisions.

## Operational guidance

- Pair canary rollout with telemetry checks (errors, latency, saturation).
- Keep one prior known-good revision for emergency rollback.
- Use KEDA metrics and revision health together for rollout decisions.

!!! warning "Do not leave stale canary revisions active"
    After rollback or promotion, deactivate obsolete revisions to reduce operational confusion and prevent unintended traffic assignment during future updates.

## Advanced Topics

- Route traffic by labels for blue/green style releases.
- Combine revisions with Dapr service invocation for progressive migration.
- Automate canary promotion in CI/CD using policy checks.

## See Also
- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- [Revisions Operations](../../../operations/revision-management/index.md)

## Sources
- [Revisions (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Traffic splitting in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
