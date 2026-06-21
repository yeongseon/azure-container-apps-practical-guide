# Phase 1 Deploy Configuration

Generated: 2026-06-12T11:39:16Z (initial), updated 2026-06-12T11:43:13Z (final, after sub switch)
Branch: lab/zone-redundancy-best-effort-reproduce
Commit (Phase 0): 222151f2b40fb8f726b24e52066210bebe708556
Tracked issue: #204

## Sub switch note

The initial deploy attempt at 2026-06-12T11:39:16Z targeted a corp-managed
subscription on the corp tenant and failed with `AuthorizationFailed`
(no `resourcegroups/write` permission for the deploying user). The
successful retry at 2026-06-12T11:43:13Z used the personal MSDN sub
(`Visual Studio Enterprise Subscription`) on a personal tenant. The
"Resource names" table below reflects the **actual successful deploy**
(suffix `260612114313`), not the failed initial attempt
(suffix `260612113916`). See [`phase-1-complete.md`](phase-1-complete.md)
"Subscription / tenant note" for the full sub-selection trace.

## Resource names (fresh isolated RG)

| Parameter | Value |
|---|---|
| RG | `rg-aca-zr-lab-260612114313` |
| LOCATION | `koreacentral` |
| BASE_NAME | `zrlab` |
| EXPIRY_HOURS | 48 |
| ACR_NAME | `acrzrlab260612114313` |
| Subscription | `Visual Studio Enterprise Subscription` (personal MSDN, GUID redacted) |
| Tenant | Personal MSDN tenant (GUID redacted; real value lives in gitignored `.local/deploy-env.local.sh`) |
| Azure CLI | 2.79.0 |
| containerapp ext | 1.3.0b4 |

Real subscription / tenant GUIDs are re-fetchable via `az account show`
once the operator is signed in to the same sub; they are intentionally not
committed to keep the evidence corpus shareable.

## Bicep parameter overrides

| Param | Value | Why |
|---|---|---|
| baseName | `zrlab` | Default |
| expiryHours | 48 | Default — 48h auto-cleanup window |
| auditImage | `acrzrlab260612114313.azurecr.io/zr-lab/audit:latest` | Custom audit image required for ReplicaInventorySample emission |
| auditAcrName | `acrzrlab260612114313` | Grants UAMI AcrPull on this registry per Bicep wiring |

## Bicep-derived names (computed from RG ID + baseName)

The Bicep template derives a 6-char unique suffix internally using
`take(uniqueString(resourceGroup().id, baseName), 6)`. Sub-resource names
follow the pattern `vnet-zrlab-XXXXXX`, `cae-zrlab-XXXXXX`, etc. The
actual suffix on this deploy is `5yi4px`; see
[`deployment-outputs.json`](deployment-outputs.json) for the full output
map.

## Subject apps (from Bicep)

- `app-min2` (minReplicas=2)
- `app-min3` (minReplicas=3)
- `app-min6` (minReplicas=6)

Total 11 replicas, 0.5 vCPU + 1 GiB per replica = 5.5 vCPU + 11 GiB env load.

## Audit Job (from Bicep)

- Name: `audit-sampler`
- Cron: `*/5 * * * *` (every 5 min)
- Image: `acrzrlab260612114313.azurecr.io/zr-lab/audit:latest`
- Emits one ReplicaInventorySample JSON per subject app per tick to stdout → Log Analytics
