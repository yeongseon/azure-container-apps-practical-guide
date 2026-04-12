---
hide:
  - toc
content_sources:
  diagrams:
    - id: troubleshooting-decision-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/azure/container-apps/containers#container-registries
        - https://learn.microsoft.com/azure/container-apps/managed-identity
        - https://learn.microsoft.com/azure/container-apps/troubleshooting
        - https://learn.microsoft.com/azure/container-registry/container-registry-authentication
content_validation:
  status: verified
  last_reviewed: "2026-04-12"
  reviewer: ai-agent
  core_claims:
    - claim: "Azure Container Apps can pull container images from public and private registries, including Azure Container Registry."
      source: "https://learn.microsoft.com/azure/container-apps/containers"
      verified: true
    - claim: "Azure Container Apps supports both system-assigned and user-assigned managed identities."
      source: "https://learn.microsoft.com/azure/container-apps/managed-identity"
      verified: true
---

# Image Pull Failure

## 1. Summary

### Symptom

Revision remains stuck in `Failed` or `Provisioning` state and never becomes healthy. The container never starts because the platform cannot pull the configured image. Application logs are empty because no code ever executes.

### Why this scenario is confusing

Image pull failures look similar to app crashes at first glance—both result in unhealthy revisions. However, the root cause is entirely different: networking, authentication, or image reference issues rather than application code. Without checking system logs, you might waste time debugging code that never ran.

### Troubleshooting decision flow

<!-- diagram-id: troubleshooting-decision-flow -->
```mermaid
graph TD
    A[Symptom: Revision never starts] --> B{System log shows error?}
    B -->|unauthorized/denied| H1[H1: Registry authentication failure]
    B -->|manifest unknown| H2[H2: Image tag doesn't exist]
    B -->|timeout/connection refused| H3[H3: Network path blocked]
    B -->|No clear error| C{Image reference format correct?}
    C -->|No| H4[H4: Malformed image reference]
    C -->|Yes| D[Check DNS and private endpoint]
```

## 2. Common Misreadings

- "The app code is crashing" — If image pull fails, your app code never executes. No point debugging application logic.
- "ACR is down" — Most incidents are identity scope issues, wrong tag, or registry URL mismatch, not ACR outages.
- "I just pushed the image, it should be there" — Push succeeded to wrong repository, wrong registry, or tag was overwritten.
- "Managed identity is configured" — Identity exists but lacks `AcrPull` role on the specific registry.
- "It worked yesterday" — Image tag was overwritten with broken image, or RBAC was modified.

## 3. Competing Hypotheses

| Hypothesis | Typical Evidence For | Typical Evidence Against |
|---|---|---|
| **H1: Registry authentication failure** | `unauthorized`, `denied`, `403`, missing role assignment | Same identity pulls successfully elsewhere |
| **H2: Image tag doesn't exist** | `manifest unknown`, `not found`, tag missing from ACR | Tag exists and digest is resolvable |
| **H3: Network path blocked** | Timeout, connection refused, DNS resolution failure | Same environment pulls other images successfully |
| **H4: Malformed image reference** | Invalid format errors, empty image field | Image reference parses correctly |

## 4. What to Check First

### Metrics

- Failed revision count in Azure Portal
- Provisioning duration (stuck revisions show extended duration)
- No replica metrics (replicas never created)

### Logs

```kusto
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where TimeGenerated > ago(1h)
| where Reason_s has_any ("ImagePullBackOff", "ErrImagePull", "Failed")
   or Log_s has_any ("pull", "manifest", "unauthorized", "denied", "timeout", "connection refused")
| project TimeGenerated, RevisionName_s, Reason_s, Log_s
| order by TimeGenerated desc
```

### Platform Signals

```bash
# Check configured image
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.template.containers[0].image" --output tsv

# Check revision status
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" \
  --query "[].{name:name,health:properties.healthState,created:properties.createdTime}" \
  --output table

# Check system logs for pull errors
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system
```

## 5. Evidence to Collect

### Required Evidence

| Evidence | Command/Query | Purpose |
|---|---|---|
| Configured image | `az containerapp show ... --query containers[0].image` | Verify image reference |
| Revision health | `az containerapp revision list` | Confirm stuck/failed state |
| System logs | KQL for pull errors | Find specific error message |
| Identity config | `az containerapp show ... --query identity` | Check managed identity |
| ACR role assignment | `az role assignment list --scope <acr-id>` | Verify AcrPull role |
| ACR tag existence | `az acr repository show-tags` | Confirm tag exists |

### Useful Context

- Registry type (ACR, Docker Hub, private registry)
- Authentication method (managed identity, admin credentials, service principal)
- Network configuration (public ACR, private endpoint, firewall)
- Recent changes (new image push, RBAC modification, network change)

## 6. Validation and Disproof by Hypothesis

### H1: Registry authentication failure

**Signals that support:**

- System logs show `unauthorized`, `denied`, `403`
- Managed identity exists but no `AcrPull` role assignment
- ACR admin credentials disabled but app expects them
- Different registry used than expected

**Signals that weaken:**

- Same identity successfully pulls other images
- Role assignment exists and is correct
- Using public image that doesn't require auth

**What to verify:**

```bash
# Check managed identity
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "identity" --output json

# Get identity principal ID
PRINCIPAL_ID=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "identity.principalId" --output tsv)

# Check AcrPull role assignment
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query "id" --output tsv)
az role assignment list --scope "$ACR_ID" --assignee "$PRINCIPAL_ID" --output table
```

```kusto
// Find auth errors
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where TimeGenerated > ago(2h)
| where Log_s has_any ("unauthorized", "denied", "403", "authentication", "credential")
| project TimeGenerated, Log_s
| order by TimeGenerated desc
```

**Fix:**

```bash
# Assign AcrPull role
az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role "AcrPull" \
  --scope "$ACR_ID"

# Or configure registry credentials
az containerapp registry set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --server "$ACR_NAME.azurecr.io" \
  --identity system
```

### H2: Image tag doesn't exist

**Signals that support:**

- System logs show `manifest unknown`, `not found`
- Tag not listed in ACR repository
- Typo in image reference

**Signals that weaken:**

- Tag exists in ACR and digest matches
- Auth errors appear instead of manifest errors

**What to verify:**

```bash
# Check if tag exists
az acr repository show-tags --name "$ACR_NAME" --repository "myapp" --output table

# Check manifest
az acr manifest show --registry "$ACR_NAME" --name "myapp:v1.0.0"

# Verify exact image reference in app
az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.template.containers[0].image" --output tsv
```

```kusto
// Find manifest errors
let AppName = "ca-myapp";
ContainerAppSystemLogs_CL
| where ContainerAppName_s == AppName
| where TimeGenerated > ago(2h)
| where Log_s has_any ("manifest unknown", "not found", "does not exist")
| project TimeGenerated, Log_s
```

**Fix:**

```bash
# Push correct image
az acr build --registry "$ACR_NAME" --image "myapp:v1.0.0" .

# Or update app to use existing tag
az containerapp update --name "$APP_NAME" --resource-group "$RG" \
  --image "$ACR_NAME.azurecr.io/myapp:existing-tag"
```

### H3: Network path blocked

**Signals that support:**

- System logs show timeout, connection refused, DNS failure
- ACR is private but environment not VNet-integrated
- Private endpoint exists but DNS not configured
- Firewall blocking outbound to ACR

**Signals that weaken:**

- Same environment successfully pulls other ACR images
- Public ACR with no network restrictions

**What to verify:**

```bash
# Check if ACR is public or private
az acr show --name "$ACR_NAME" --query "publicNetworkAccess" --output tsv

# Check environment VNet integration
az containerapp env show --name "$ENVIRONMENT_NAME" --resource-group "$RG" \
  --query "properties.vnetConfiguration" --output json

# Check ACR private endpoint (if applicable)
az network private-endpoint list --resource-group "$RG" \
  --query "[?contains(name, 'acr')]" --output table
```

**Fix:**

```bash
# For private ACR, ensure private DNS zone is linked
az network private-dns zone list --resource-group "$RG" --output table

# Or allow Container Apps environment subnet in ACR firewall
az acr network-rule add --name "$ACR_NAME" --subnet "<subnet-id>"
```

### H4: Malformed image reference

**Signals that support:**

- Image field empty or malformed
- Missing registry prefix
- Invalid characters in image name

**Signals that weaken:**

- Image reference parses correctly
- Same reference works in docker pull locally

**What to verify:**

```bash
# Check image format
IMAGE=$(az containerapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "properties.template.containers[0].image" --output tsv)
echo "Configured image: $IMAGE"

# Validate format: registry/repository:tag
# Examples:
# ✅ myacr.azurecr.io/myapp:v1.0.0
# ✅ docker.io/library/nginx:latest
# ❌ myapp:v1.0.0 (missing registry)
# ❌ myacr.azurecr.io/myapp (missing tag)
```

## 7. Likely Root Cause Patterns

| Pattern | Frequency | First Signal | Typical Resolution |
|---|---|---|---|
| Missing AcrPull role | Very common | `unauthorized` in logs | Add role assignment |
| Wrong image tag | Common | `manifest unknown` | Fix tag or push image |
| System identity not enabled | Common | `unauthorized` | Enable system identity |
| Private ACR without VNet | Occasional | Timeout | Configure VNet or private endpoint |
| Typo in registry name | Occasional | DNS failure | Fix registry URL |

## 8. Immediate Mitigations

1. **If auth failure:** Assign AcrPull role
   ```bash
   az role assignment create --assignee "$PRINCIPAL_ID" --role "AcrPull" --scope "$ACR_ID"
   ```

2. **If tag missing:** Use known good tag
   ```bash
   az containerapp update --name "$APP_NAME" --resource-group "$RG" \
     --image "$ACR_NAME.azurecr.io/myapp:known-good-tag"
   ```

3. **If private ACR issues:** Temporarily enable public access (for debugging only)
   ```bash
   az acr update --name "$ACR_NAME" --public-network-enabled true
   ```

4. **Force new revision after fix:**
   ```bash
   az containerapp update --name "$APP_NAME" --resource-group "$RG" \
     --revision-suffix "fix-$(date +%s)"
   ```

## 9. Prevention

- Use immutable image tags (commit SHA) to prevent tag overwrites
- Add CI validation that checks image existence before deployment
- Keep ACR RBAC in Infrastructure as Code to avoid drift
- Use digest references for critical deployments: `image@sha256:...`
- Automate image build + deploy in single pipeline to ensure consistency
- Set up ACR webhook to trigger deployment only after successful push

## See Also

- [Revision Provisioning Failure](revision-provisioning-failure.md)
- [Container Start Failure](container-start-failure.md)
- [Managed Identity Auth Failure](../identity-and-configuration/managed-identity-auth-failure.md)
- [Image Pull and Auth Errors KQL](../../kql/system-and-revisions/image-pull-and-auth-errors.md)
- [ACR Pull Failure Lab](../../lab-guides/acr-pull-failure.md)

## Sources

- [Manage container registries in Azure Container Apps](https://learn.microsoft.com/azure/container-apps/containers#container-registries)
- [Managed identities in Azure Container Apps](https://learn.microsoft.com/azure/container-apps/managed-identity)
- [Troubleshoot Azure Container Apps](https://learn.microsoft.com/azure/container-apps/troubleshooting)
- [Azure Container Registry authentication](https://learn.microsoft.com/azure/container-registry/container-registry-authentication)
