# 07 - Revisions and Traffic Splitting

Azure Container Apps revisions provide immutable deployment snapshots. Use them for safe releases, canary traffic, and quick rollback.

## Revision Traffic Splitting

```mermaid
graph LR
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

2. **Switch to multiple revision mode**

    ```bash
    az containerapp revision set-mode \
      --name "$APP_NAME" \
      --resource-group "$RG" \
      --mode multiple
    ```

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

    ???+ example "Expected output"
        ```text
        "Deactivate succeeded"
        ```

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
- [Revisions Operations](../../operations/revision-management/index.md)

## Sources
- [Revisions (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions)
- [Traffic splitting in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/traffic-splitting)
