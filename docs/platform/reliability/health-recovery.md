# Health and Recovery Operations

This guide covers production health checks and recovery operations: probe tuning, restart behavior, and incident response patterns.

## Prerequisites

- Application exposes a reliable health endpoint (for example, `/health`)
- SRE runbook defines recovery time objective (RTO)

```bash
export RG="rg-aca-prod"
export APP_NAME="app-python-api-prod"
export ENVIRONMENT_NAME="aca-env-prod"
```

## Health Probe Configuration

Configure startup, liveness, and readiness probes in your Container App template:

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --yaml "./infra/containerapp-health.yaml"
```

Validate environment and platform-level status:

```bash
az resource show \
  --resource-group "$RG" \
  --resource-type "Microsoft.App/managedEnvironments" \
  --name "$ENVIRONMENT_NAME" \
  --output json
```

## Restart and Recovery Workflows

Restart a revision when transient faults occur:

```bash
az containerapp revision restart \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "${APP_NAME}--stable"
```

For persistent failures, roll traffic back to a healthy revision (see revisions guide).

## Verification Steps

Check revision states and recent failures:

```bash
az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output table
```

Review system logs for probe failures:

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system \
  --follow false
```

Example output (PII masked):

```text
2026-04-02T09:10:21Z Probe failed: readiness check returned HTTP 503
2026-04-02T09:10:31Z Restarting container due to failed liveness probe
```

## Troubleshooting

### Frequent restarts

- Increase `initialDelaySeconds` for slow startup workloads.
- Confirm probe path and port match the application listener.
- Check downstream dependency outages causing readiness failures.

### App never becomes ready

- Inspect app logs for startup exceptions.
- Verify secrets and configuration are available at startup.

## Advanced Topics

- Separate startup and readiness logic to reduce false positives.
- Add synthetic probes from outside the environment for end-to-end health.
- Trigger automated recovery playbooks from alert rules.

## See Also
- [Revisions](../../operations/revision-management/index.md)
- [Observability](../../operations/monitoring/index.md)

## References
- [Azure Container Apps health probes](https://learn.microsoft.com/azure/container-apps/health-probes)
- [Azure Container Apps revisions (Microsoft Learn)](https://learn.microsoft.com/azure/container-apps/revisions)
