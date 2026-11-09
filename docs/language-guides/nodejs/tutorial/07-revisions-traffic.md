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

    This tutorial assumes a production-ready Container Apps deployment with a custom VNet and private ACR access using managed identity.

    <!-- diagram-id: this-tutorial-assumes-a-production-ready-container -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "10px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 55}}}%%
flowchart TD
    accTitle: Production-ready Container Apps context for the Node.js tutorial
    accDescr: Client requests and responses pass through managed ingress. The customer VNet and private-endpoint subnet host the ACR private endpoint and link its DNS zone. Managed identity is assigned to the app and authorizes registry pulls, while platform provisioning exchanges image traffic with ACR through the private endpoint.
    CALLER(["Client"])
    VNET["VNet + PE<br/>subnet"]
    IDENTITY["Managed identity"]
    PE_ACR["ACR PE"]
    ACR["ACR"]
    DNS["ACR DNS zone"]
    subgraph ENV["ACA environment"]
        INGRESS["Ingress"]
        APP["Container app<br/>Node.js"]
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

*Figure: The customer VNet and private-endpoint subnet host the ACR private endpoint and link its DNS zone. Managed identity is assigned to the app and authorizes registry pulls through a role assignment; platform provisioning remains the image-pull actor, and both pull requests and layer responses pass through the private endpoint.*

## Revision Traffic Splitting

<!-- diagram-id: revision-traffic-splitting -->
```mermaid
%%{init: {"themeVariables": {"fontSize": "10px"}, "flowchart": {"curve": "linear", "nodeSpacing": 5, "rankSpacing": 20, "diagramPadding": 2, "wrappingWidth": 55}}}%%
flowchart TD
    accTitle: Weighted traffic split between Node.js revisions
    accDescr: A population of client requests reaches managed ingress. Traffic weights configure ingress, which sends 90 percent of requests to stable replicas and 10 percent to canary replicas. Both replica groups return responses through ingress.
    CLIENT["Requests<br/>(population)"]
    INGRESS["Managed Envoy ingress"]
    ROUTER["Traffic weights<br/>90% / 10%"]
    APP["Container app"]
    STABLE["Stable revision<br/>90% weight"]
    STABLE_REPLICAS["Stable revision replicas"]
    CANARY["Canary revision<br/>10% weight"]
    CANARY_REPLICAS["Canary revision replicas"]
    CLIENT ~~~ INGRESS ~~~ STABLE_REPLICAS ~~~ STABLE ~~~ APP ~~~ ROUTER ~~~ CANARY ~~~ CANARY_REPLICAS
    APP -.-> STABLE
    APP -.-> CANARY
    STABLE -.-> STABLE_REPLICAS
    CANARY -.-> CANARY_REPLICAS
    CLIENT ==>|"HTTPS requests"| INGRESS
    ROUTER -.-> INGRESS
    INGRESS ==>|"90% requests"| STABLE_REPLICAS
    INGRESS ==>|"10% requests"| CANARY_REPLICAS
    STABLE_REPLICAS ==>|"Responses"| INGRESS
    CANARY_REPLICAS ==>|"Responses"| INGRESS
    INGRESS ==>|"HTTPS responses"| CLIENT
    linkStyle 0,1,2,3,4,5,6 opacity:0
```

*Figure: Traffic weights configure managed ingress; ingress sends the population of requests directly to stable and canary replicas at 90% and 10%, and each replica group returns responses through ingress.*

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
- [Container Apps networking (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/networking)
- [Managed identity image pull (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity-image-pull)
- [Azure Container Registry private link (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-link)
- [Revisions (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Traffic splitting in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
