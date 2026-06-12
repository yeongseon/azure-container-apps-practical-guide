# Phase 1 Deploy Configuration

Generated: 2026-06-12T11:39:16Z
Branch: lab/zone-redundancy-best-effort-reproduce
Commit: 222151f2b40fb8f726b24e52066210bebe708556
Tracked issue: #204
Oracle session: ses_144f3ce9cffeyOLLgO8doWTal3

## Resource names (Oracle decision #9: fresh isolated RG)

| Parameter | Value |
|---|---|
| RG | `rg-aca-zr-lab-260612113916` |
| LOCATION | `koreacentral` |
| BASE_NAME | `zrlab` |
| EXPIRY_HOURS | 48 |
| ACR_NAME | `acrzrlab260612113916` |
| Subscription | ASM Kustodian Corp (`a178425c-491a-416c-b313-39dce68d9b86`) |
| Tenant | `72f988bf-86f1-41af-91ab-2d7cd011db47` |
| Azure CLI | 2.79.0 |
| containerapp ext | 1.3.0b4 |

## Bicep parameter overrides

| Param | Value | Why |
|---|---|---|
| baseName | `zrlab` | Default |
| expiryHours | 48 | Default — 48h auto-cleanup window |
| auditImage | `acrzrlab260612113916.azurecr.io/zr-lab/audit:latest` | Custom audit image required for ReplicaInventorySample emission |
| auditAcrName | `acrzrlab260612113916` | Grants UAMI AcrPull on this registry per Bicep wiring |

## Bicep-derived names (computed from RG ID + baseName)

The Bicep template derives a 6-char unique suffix internally using `take(uniqueString(resourceGroup().id, baseName), 6)`. Sub-resource names will follow the pattern `vnet-zrlab-XXXXXX`, `cae-zrlab-XXXXXX`, etc. These will appear in the deployment outputs below.

## Subject apps (from Bicep)

- `app-min2` (minReplicas=2)
- `app-min3` (minReplicas=3)
- `app-min6` (minReplicas=6)

Total 11 replicas, 0.5 vCPU + 1 GiB per replica = 5.5 vCPU + 11 GiB env load.

## Audit Job (from Bicep)

- Name: `audit-sampler`
- Cron: `*/5 * * * *` (every 5 min)
- Image: `acrzrlab260612113916.azurecr.io/zr-lab/audit:latest`
- Emits one ReplicaInventorySample JSON per subject app per tick to stdout → Log Analytics
