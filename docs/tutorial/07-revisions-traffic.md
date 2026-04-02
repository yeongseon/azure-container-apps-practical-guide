# 07 - Revisions and Traffic Splitting

Azure Container Apps revisions provide immutable deployment snapshots. Use them for safe releases, canary traffic, and quick rollback.

## Prerequisites

- Completed [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- At least two deployed images/tags

## Step-by-step

1. **Set standard variables**

   ```bash
   RG="rg-aca-python-demo"
   APP_NAME="app-aca-python-demo"
   ENVIRONMENT_NAME="aca-env-python-demo"
   ACR_NAME="acrpythondemo12345"
   ```

2. **Switch to multiple revision mode**

   ```bash
   az containerapp revision set-mode \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --mode multiple
   ```

3. **Deploy a new version to create a new revision**

   ```bash
   az acr build --registry "$ACR_NAME" --image "$APP_NAME:v3" .

   az containerapp update \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --image "$ACR_NAME.azurecr.io/$APP_NAME:v3"
   ```

4. **List revisions and choose targets**

   ```bash
   az containerapp revision list \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --query "[].{name:name,active:properties.active,createdTime:properties.createdTime}"
   ```

5. **Apply canary traffic split (90/10)**

   ```bash
   az containerapp ingress traffic set \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --traffic-weight "<stable-revision>=90" "<canary-revision>=10"
   ```

6. **Rollback instantly if errors increase**

   ```bash
   az containerapp ingress traffic set \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --traffic-weight "<stable-revision>=100"
   ```

7. **Deactivate bad revision after confirmation**

   ```bash
   az containerapp revision deactivate \
     --name "$APP_NAME" \
     --resource-group "$RG" \
     --revision "<canary-revision>"
   ```

## Operational guidance

- Pair canary rollout with telemetry checks (errors, latency, saturation).
- Keep one prior known-good revision for emergency rollback.
- Use KEDA metrics and revision health together for rollout decisions.

## Advanced Topics

- Route traffic by labels for blue/green style releases.
- Combine revisions with Dapr service invocation for progressive migration.
- Automate canary promotion in CI/CD using policy checks.

## See Also

- [04 - Logging, Monitoring, and Observability](04-logging-monitoring.md)
- [06 - CI/CD with GitHub Actions](06-ci-cd.md)
- [Revisions Operations](../operations/revisions.md)
