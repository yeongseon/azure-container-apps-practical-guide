# First 10 Minutes: Quick Triage Checklist

Use this ordered checklist when a Container App is down, unhealthy, or unreachable. Run each step in sequence and stop when you find the first confirmed failure.

!!! tip "Run from a clean shell session"
    Export variables once to avoid command mistakes:

    ```bash
    RG="rg-myapp"
    APP_NAME="ca-myapp-api"
    ENVIRONMENT_NAME="cae-myapp"
    ACR_NAME="acrmyapp"
    ```

## 1) Revision Status

```bash
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --query "[].{name:name,active:properties.active,health:properties.healthState,running:properties.runningState,created:properties.createdTime}" --output table
```

- Look for the latest revision with `health=Healthy` and `running=Running`.
- Failure patterns: `Provisioning failed`, `Failed`, `Degraded`, inactive latest revision.
- If failed → go to [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md).

## 2) Replica Status

```bash
az containerapp replica list --name "$APP_NAME" --resource-group "$RG" --query "[].{replica:name,runningState:properties.runningState,created:properties.createdTime}" --output table
```

- Look for replicas that remain in `Running` state.
- Failure patterns: repeated short-lived replicas, no replicas created, restart loops.
- If failed → go to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

## 3) Container Logs

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type console --follow
```

- Look for Python traceback, startup command failures, bind errors, missing configuration.
- Failure patterns: `ModuleNotFoundError`, `Address already in use`, `connection refused`, crash loops.
- If failed → go to [Container Start Failure](../playbooks/startup-and-provisioning/container-start-failure.md).

## 4) Image Pull

```bash
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
az acr repository show-tags --name "$ACR_NAME" --repository "$APP_NAME" --output table
```

- Confirm image tag exists and system logs do not show pull/auth errors.
- Failure patterns: `ImagePullBackOff`, `manifest unknown`, `unauthorized`, `denied`.
- If failed → go to [Image Pull Failure](../playbooks/startup-and-provisioning/image-pull-failure.md).

## 5) Ingress Configuration

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.configuration.ingress" --output json
```

- Confirm `external` setting matches your access model and `targetPort` matches app listening port.
- Failure patterns: ingress disabled, wrong `targetPort`, internal app tested from public internet.
- If failed → go to [Ingress Not Reachable](../playbooks/ingress-and-networking/ingress-not-reachable.md).

## 6) Health Probes

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].probes" --output json
```

- Confirm liveness/readiness probe paths and ports are valid; startup probe timeout fits app boot time.
- Failure patterns: probe path returns 404/500, startup timeout too short, wrong probe port.
- If failed → go to [Probe Failure and Slow Start](../playbooks/startup-and-provisioning/probe-failure-and-slow-start.md).

!!! warning "Probe defaults can still fail"
    Apps with migrations, cold dependency checks, or large model loads often need a longer startup probe window.

## 7) Registry Authentication

```bash
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "identity" --output json
az role assignment list --scope "$(az acr show --name "$ACR_NAME" --query id --output tsv)" --assignee "$(az containerapp show --name "$APP_NAME" --resource-group "$RG" --query identity.principalId --output tsv)" --output table
```

- Confirm managed identity exists and has `AcrPull` role on the registry scope.
- Failure patterns: no principal ID, missing `AcrPull`, ACR firewall blocks environment egress.
- If failed → go to [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md) and [Image Pull Failure](../playbooks/startup-and-provisioning/image-pull-failure.md).

## 8) Secrets and Config

```bash
az containerapp secret list --name "$APP_NAME" --resource-group "$RG"
az containerapp show --name "$APP_NAME" --resource-group "$RG" --query "properties.template.containers[0].env" --output json
```

- Confirm secret references exist and expected environment variables are present.
- Failure patterns: `secretRef` points to missing secret, null env var values, stale revision after secret update.
- If failed → go to [Secret and Key Vault Reference Failure](../playbooks/identity-and-configuration/secret-and-key-vault-reference-failure.md) and [Revision Provisioning Failure](../playbooks/startup-and-provisioning/revision-provisioning-failure.md).

## 9) Environment and Network

```bash
az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RG" --output json
az network private-endpoint list --resource-group "$RG" --output table
```

- Confirm environment is healthy and network dependencies (private DNS/private endpoints) are correctly configured.
- Failure patterns: DNS resolution failures, blocked NSG outbound rules, missing private DNS link.
- If failed → go to [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

## 10) Dependencies

```bash
az containerapp exec --name "$APP_NAME" --resource-group "$RG" --command "python -c 'import socket; print(socket.gethostbyname(\"example.database.windows.net\"))'"
```

- Confirm the app can resolve and reach critical services (database, storage, API endpoints).
- Failure patterns: DNS timeout, TLS handshake errors, outbound firewall denials.
- If failed → go to [Service-to-Service Connectivity Failure](../playbooks/ingress-and-networking/service-to-service-connectivity-failure.md), [Managed Identity Auth Failure](../playbooks/identity-and-configuration/managed-identity-auth-failure.md), or [Internal DNS and Private Endpoint Failure](../playbooks/ingress-and-networking/internal-dns-and-private-endpoint-failure.md).

## Escalate with Context

If the checklist does not isolate root cause, continue with [Troubleshooting Methodology](../methodology/index.md) and include:

- failing revision name
- exact error text from system/console logs
- ingress mode and target port
- dependency endpoint(s) that failed
