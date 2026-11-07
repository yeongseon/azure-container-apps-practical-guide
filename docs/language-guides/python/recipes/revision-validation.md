---
content_sources:
  diagrams:
    - id: validate-new-revisions-with-direct-testing
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/revisions
        - https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting
        - https://learn.microsoft.com/en-us/azure/container-apps/health-probes
---
# Recipe: Revision Validation Before Production Traffic

Validate new revisions with direct testing and controlled traffic movement so you can release safely without impacting all users at once.

<!-- diagram-id: validate-new-revisions-with-direct-testing -->
```mermaid
flowchart TD
    accTitle: Validate a candidate revision before promotion
    accDescr: Deploy a uniquely tagged image as a new revision in multiple revision mode, keep its production traffic weight at zero, assign a label URL for direct smoke tests, and promote or return traffic to the stable revision based on the result.

    IMAGE[Uniquely tagged image]
    CANDIDATE[Candidate revision<br/>0 percent production traffic]
    LABEL[Label URL<br/>direct revision endpoint]
    TEST[Smoke and dependency tests]
    DECISION[Evaluate release criteria]
    CANARY[Shift a small traffic weight]
    PROMOTE[Promote candidate]
    ROLLBACK[Keep or return traffic<br/>to stable revision]

    IMAGE -->|Creates| CANDIDATE
    CANDIDATE -->|Assign label| LABEL
    LABEL ==>|Direct test requests| TEST
    TEST --> DECISION
    DECISION -->|Criteria pass| CANARY
    CANARY -->|Telemetry remains healthy| PROMOTE
    DECISION -->|Criteria fail| ROLLBACK
    CANARY -->|Regression| ROLLBACK
```

Thick arrows show direct test traffic. Thin arrows show release-control decisions; a zero traffic weight does not deactivate the labeled candidate revision.

## Prerequisites

- Existing Container App with multiple revision mode enabled
- Azure CLI 2.57+ with Container Apps extension
- Smoke tests for your key endpoints

```bash
az containerapp revision set-mode \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --mode multiple
```

| Command | Why it is used |
|---|---|
| `az containerapp revision set-mode` | Enables multiple revision mode for controlled traffic testing. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--mode` | Selects multiple revision mode for controlled promotion. |


## Deploy a new revision at 0% traffic

```bash
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:$IMAGE_TAG" \
  --revision-suffix "canary"

export NEW_REVISION=$(az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[?contains(name, 'canary')].name | [0]" \
  --output tsv)

az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$NEW_REVISION=0"
```

| Command | Why it is used |
|---|---|
| `az containerapp update` | Updates the selected Container App with this step's image or configuration. |
| `az containerapp revision list` | Finds the newly created candidate revision. |
| `az containerapp ingress traffic set` | Applies the specified revision traffic weights. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--image` | Selects or tags the container image used by this recipe step. |
| `--revision-suffix` | Gives the candidate revision a recognizable immutable suffix. |
| `--query` | Extracts the exact resource property consumed by the next command. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |
| `--revision-weight` | Applies the documented production traffic percentage to each revision. |


## Revision labels and direct URL testing

Assign a label so testers can call the candidate revision directly.

```bash
az containerapp revision label add \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --label "canary" \
  --revision "$NEW_REVISION"

export LABEL_URL=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

curl --fail "https://canary---$LABEL_URL/health"
```

| Command | Why it is used |
|---|---|
| `az containerapp revision label add` | Assigns a stable label URL to the candidate revision. |
| `az containerapp show` | Reads the Container App property needed by the next recipe step. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--label` | Names the stable direct URL assigned to the candidate revision. |
| `--revision` | Selects the candidate revision used for labels, logs, or verification. |
| `--query` | Extracts the exact resource property consumed by the next command. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |
| `--fail` | Makes the smoke test fail on an HTTP error response. |


## Health check validation before traffic shift

Confirm:

1. `/health` returns 200.
2. Dependency checks (database/cache/API) pass.
3. Error rate and latency are within baseline.

```bash
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision "$NEW_REVISION" \
  --follow false
```

| Command | Why it is used |
|---|---|
| `az containerapp logs show` | Streams or retrieves logs from the selected app or revision for verification. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--revision` | Selects the candidate revision used for labels, logs, or verification. |
| `--follow` | Continues streaming new log records during verification. |


## Weighted traffic splitting (canary)

Shift traffic gradually while watching telemetry.

```bash
export STABLE_REVISION=$(az containerapp revision list \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "[?properties.active==\`true\` && name!=\`$NEW_REVISION\`].name | [0]" \
  --output tsv)

# 10% canary
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$STABLE_REVISION=90" "$NEW_REVISION=10"

# Promote to 100% after validation window
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$NEW_REVISION=100"
```

| Command | Why it is used |
|---|---|
| `az containerapp revision list` | Finds the newly created candidate revision. |
| `az containerapp ingress traffic set` | Applies the specified revision traffic weights. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--query` | Extracts the exact resource property consumed by the next command. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |
| `--revision-weight` | Applies the documented production traffic percentage to each revision. |


## Automated revision validation script

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="$1"
RG="$2"
LABEL="canary"

FQDN=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

for path in /health /ready /version; do
  echo "Testing ${path}"
  curl --silent --show-error --fail "https://${LABEL}---${FQDN}${path}" > /dev/null
done

echo "Revision validation passed"
```

| Command | Why it is used |
|---|---|
| `az containerapp show` | Reads the Container App property needed by the next recipe step. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--query` | Extracts the exact resource property consumed by the next command. |
| `--output` | Returns the result in the format consumed by the shell or verification table. |
| `--silent` | Suppresses progress output so the smoke-test result stays concise. |
| `--show-error` | Prints the HTTP error when the otherwise-silent smoke test fails. |
| `--fail` | Makes the smoke test fail on an HTTP error response. |


## Rollback patterns

- **Fast rollback**: route 100% back to last stable revision.
- **Safe rollback**: keep canary alive at 0% for postmortem testing.
- **Operational rollback**: disable bad revision if it causes repeated probe failures.

```bash
az containerapp ingress traffic set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --revision-weight "$STABLE_REVISION=100" "$NEW_REVISION=0"
```

| Command | Why it is used |
|---|---|
| `az containerapp ingress traffic set` | Applies the specified revision traffic weights. |
| `--name` | Selects the named resource operated on in this recipe step. |
| `--resource-group` | Selects the resource group that contains this step's target resource. |
| `--revision-weight` | Applies the documented production traffic percentage to each revision. |


## Advanced Topics

- Integrate validation into CI/CD gates before promotion.
- Use synthetic transactions instead of health-only checks.
- Add automatic rollback triggers from error-budget policies.

## See Also

- [Container Registry](container-registry.md)
- [Custom Container](custom-container.md)
- [Revisions](../../../platform/revisions/index.md)
- [Microsoft Learn: Revisions in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/revisions)

## Sources

- [Microsoft Learn source 1](https://learn.microsoft.com/en-us/azure/container-apps/revisions)
- [Microsoft Learn source 2](https://learn.microsoft.com/en-us/azure/container-apps/traffic-splitting)
- [Microsoft Learn source 3](https://learn.microsoft.com/en-us/azure/container-apps/health-probes)
