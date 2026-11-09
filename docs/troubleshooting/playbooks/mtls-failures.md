---
content_sources:
  diagrams:
    - id: aca-mtls-troubleshooting-flow
      type: flowchart
      source: mslearn-adapted
      based_on:
        - https://learn.microsoft.com/en-us/azure/container-apps/client-certificate-authorization
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
        - https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration
        - https://learn.microsoft.com/en-us/azure/container-apps/connect-apps
content_validation:
  status: verified
  last_reviewed: 2026-09-11
  reviewer: ai-agent
  core_claims:
    - claim: Ingress forwards the client certificate in X-Forwarded-Client-Cert when clientCertificateMode is set to require or accept.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview
      verified: true
    - claim: Azure Container Apps supports peer-to-peer TLS encryption within the environment.
      source: https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration
      verified: true
    - claim: Dapr service invocation in Azure Container Apps includes built-in mutual TLS.
      source: https://learn.microsoft.com/en-us/azure/container-apps/connect-apps
      verified: true
---
# mTLS Failures

## Symptom

- The app never sees `X-Forwarded-Client-Cert`.
- Ingress returns `403` when `clientCertificateMode=require`.
- App code reports certificate parsing or chain validation failures.
- Dapr sidecar logs show mTLS handshake or invocation failures.
- Traffic inside the environment appears unencrypted after peer encryption was expected.

<!-- diagram-id: aca-mtls-troubleshooting-flow -->
```mermaid
flowchart TD
    accTitle: Classify a Container Apps mutual TLS symptom
    accDescr: Separate client-certificate ingress, application certificate validation, Dapr service invocation, and environment peer-to-peer encryption before applying a fix.

    SYMPTOM[mTLS-related symptom]
    SURFACE{Which security surface failed?}
    CLIENT{Client sends a certificate during the TLS handshake?}
    MODE{Client certificate mode is Accept or Require?}
    HEADER{Application receives X-Forwarded-Client-Cert?}
    VALIDATION{Application validates the forwarded certificate as required?}
    DAPR{Dapr enabled and correct app ID used?}
    PEER{Peer-to-peer encryption enabled on the intended environment?}
    CLIENT_FIX[Correct client certificate presentation]
    MODE_FIX[Correct client certificate mode]
    APP_FIX[Correct XFCC parsing and certificate validation]
    DAPR_FIX[Correct Dapr enablement, app ID, or sidecar call]
    PEER_FIX[Correct the environment encryption setting]
    VERIFY[Retest the same security surface]

    SYMPTOM --> SURFACE
    SURFACE -->|Ingress client certificate| CLIENT
    SURFACE -->|Dapr service invocation| DAPR
    SURFACE -->|Peer-to-peer encryption| PEER
    CLIENT -->|No| CLIENT_FIX
    CLIENT -->|Yes| MODE
    MODE -->|No| MODE_FIX
    MODE -->|Yes| HEADER
    HEADER -->|No| MODE_FIX
    HEADER -->|Yes| VALIDATION
    VALIDATION -->|No| APP_FIX
    VALIDATION -->|Yes| VERIFY
    DAPR -->|No| DAPR_FIX
    DAPR -->|Yes| VERIFY
    PEER -->|No| PEER_FIX
    PEER -->|Yes| VERIFY

    LEGEND["Arrow key<br/>solid = diagnostic progression"]
```

*Figure: Certificate presentation, forwarded-certificate validation, Dapr mTLS, and peer-to-peer encryption are distinct controls.*

## Possible Causes

- `clientCertificateMode` is `ignore`, so ingress never forwards the header.
- The client does not actually send a certificate during the TLS handshake.
- App code parses the entire XFCC header instead of the leaf `Cert=` segment.
- The Dapr caller uses the wrong App ID or bypasses the sidecar.
- Environment peer encryption was never enabled or was enabled in a different environment than expected.

## Diagnosis Steps

### 1. Missing `X-Forwarded-Client-Cert` header at the app

Check ingress mode first:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.ingress.clientCertificateMode" \
  --output tsv
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App configuration to evaluate client-certificate enforcement and forwarding. |
| `--name` (`az containerapp show`) | Selects `$APP_NAME`, the resource whose state contributes to client-certificate enforcement and forwarding. |
| `--resource-group` (`az containerapp show`) | Resolves the target from the resource group used by the 1. missing `x-forwarded-client-cert` header at the app workflow. |
| `--query` (`az containerapp show`) | Isolates `clientCertificateMode` to establish whether ingress requests a client certificate before investigating the forwarded header. |
| `--output` (`az containerapp show`) | Emits the certificate mode without JSON quoting so the shell variable contains only the configured mode. |


If the value is `ignore`, the absence of the header is expected.

### 2. `403` from ingress with `clientCertificateMode=require`

Test the endpoint with and without a client certificate:

```bash
curl --include "https://${FQDN}/cert-info"

curl --include \
  --cert "./client.pem" \
  --key "./client.key" \
  "https://${FQDN}/cert-info"
```

If only the second call succeeds, ingress enforcement is working and the first caller simply lacked a certificate.

### 3. Chain validation or parsing failure in app code

Look for these anti-patterns:

- Parsing the whole header instead of `Cert=`.
- Treating escaped newlines as literal text.
- Comparing the wrong thumbprint algorithm.
- Validating only CN when your policy actually depends on issuer or SAN.

### 4. Dapr sidecar mTLS handshake issues

Check Dapr configuration and app identity:

```bash
az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --query "properties.configuration.dapr" \
  --output json

az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --type system
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp show` | Reads the selected Container App configuration to evaluate Dapr enablement and sidecar failure signals. |
| `--name` (`az containerapp show`) | Selects `$APP_NAME`, the resource whose state contributes to Dapr enablement and sidecar failure signals. |
| `--resource-group` (`az containerapp show`) | Finds `$APP_NAME` in `$RG` before reading its Dapr sidecar configuration. |
| `--query` (`az containerapp show`) | Projects the Dapr configuration used to check whether the sidecar is enabled and participating in the failing service call. |
| `--output` (`az containerapp show`) | Keeps the nested Dapr configuration as JSON for sidecar enablement and app-ID inspection. |
| `az containerapp logs show` | Retrieves the requested Container Apps log stream to evaluate Dapr enablement and sidecar failure signals. |
| `--name` (`az containerapp logs show`) | Selects `$APP_NAME`, the resource whose state contributes to Dapr enablement and sidecar failure signals. |
| `--resource-group` (`az containerapp logs show`) | Retrieves the app's log stream from `$RG`, matching the resource inspected immediately above. |
| `--type` (`az containerapp logs show`) | Chooses system logs because Dapr sidecar startup and handshake failures are emitted there. |


Confirm that:

- Dapr is enabled on both caller and callee.
- The caller uses the correct Dapr App ID.
- The app is calling `localhost:3500` and not bypassing the sidecar by accident.

### 5. Environment-internal traffic still looks unencrypted

Review the managed environment:

```bash
az containerapp env show \
  --name "$ACA_ENV_NAME" \
  --resource-group "$RG" \
  --query "properties.peerTrafficConfiguration" \
  --output json
```

| Command/Parameter | Purpose |
|---|---|
| `az containerapp env show` | Reads the selected managed environment configuration to evaluate the Azure state that distinguishes this hypothesis. |
| `--name` (`az containerapp env show`) | Selects `$ACA_ENV_NAME`, whose peer-traffic setting governs internal app-to-app encryption. |
| `--resource-group` (`az containerapp env show`) | Locates the managed environment in `$RG` before reading its peer-traffic policy. |
| `--query` (`az containerapp env show`) | Narrows the environment response to peer-traffic settings that determine encryption between apps in the environment. |
| `--output` (`az containerapp env show`) | Preserves the peer-traffic configuration as JSON so encryption settings remain visible. |


If the property is empty or encryption is disabled, peer encryption was never turned on for that environment.

## Resolution

- Set `clientCertificateMode` to `require` or `accept` when the app needs XFCC.
- Ensure testing clients provide both `--cert` and `--key`.
- Parse only the leaf `Cert=` element from `X-Forwarded-Client-Cert`.
- Correct Dapr App IDs and force all Dapr traffic through the sidecar endpoint.
- Enable `peerTrafficConfiguration.encryption.enabled` on the managed environment when direct internal traffic must be encrypted.

## Prevention

- Keep ingress mode, certificate policy, and route ownership documented together.
- Add a `/cert-info` or equivalent diagnostics endpoint in lower environments.
- Monitor Dapr system logs during rollout of new App IDs or sidecar config.
- Validate managed environment encryption settings as part of environment provisioning.

## See Also

- [Ingress Client Certificates](../../platform/security/ingress-client-certificates.md)
- [mTLS Architecture in Azure Container Apps](../../platform/security/mtls.md)
- [Service-to-Service Connectivity Failure](ingress-and-networking/service-to-service-connectivity-failure.md)

## Sources

- [Configure client certificate authentication in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/client-certificate-authorization)
- [Ingress overview in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Ingress environment configuration in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/ingress-environment-configuration)
- [Communicate between container apps in Azure Container Apps (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/container-apps/connect-apps)
