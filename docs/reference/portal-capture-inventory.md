---
description: Current Azure Container Apps Portal capture inventory, including manifest coverage, legacy image reuse, lab gaps, and manual review queues.
---
# Portal Capture Inventory

This inventory is generated from tracked repository files at `9cbf725392ae262dadf3553005172d7eda88c6a0`. It records file and reference presence only; no image was opened, captured, changed, or independently re-verified.

The scan reads `docs/**` and `scripts/capture/manifest.yaml` directly from that pinned commit. The current generator rules classify Portal instructions with these phrases: `azure portal`, `in the portal`, `portal blade`, `portal evidence`, `portal view`, `portal screenshot`, `portal capture`. The vocabulary intentionally uses specific phrases rather than the bare word `portal` to avoid classifying incidental mentions as capture instructions.

## Reproduce the inventory

```bash
python3 scripts/portal_capture_inventory.py --check
```

The detailed machine-readable inventory is [`portal-capture-inventory.json`](portal-capture-inventory.json). Regenerate both files with `--write --base-commit <sha>` only when intentionally pinning a new baseline.

## Current counts

| Measure | Count |
|---|---:|
| Markdown pages scanned | 394 |
| Portal-instruction pages | 184 |
| Raster assets | 435 |
| Legacy assets outside the manifest | 435 |
| Manifest IDs | 0 |
| `shot()` references | 0 |
| Raw local image references | 457 |
| Assets reused across pages | 13 |
| Caption/alt review candidates | 13 |
| Lab guides with Portal evidence | 24 |
| Lab guides without Portal evidence | 37 |

| Page state | Count |
|---|---:|
| `captured` | 0 |
| `missing` | 59 |
| `stale` | 0 |
| `manual-blocked` | 125 |
| `excluded` | 210 |

`manual-blocked` means legacy bytes exist but final-image PII and caption accuracy were **not collected**. `missing` means a Portal-instruction page has no local capture, or has a broken reference. `stale` applies to `shot()` and direct image references backed by manifest entries whose `verified` date is absent or older than 180 days. `excluded` means no Portal-instruction term matched or an explicit rule excluded the page. The JSON includes the same five states for every page and a separate Portal-only state count.

## Legacy image reuse

These are deterministic reuse candidates, not proof that a caption is wrong.

| Asset | Pages | Referenced by |
|---|---:|---|
| `docs/assets/platform/architecture/02-resource-group-overview.png` | 2 | `docs/platform/architecture/index.md`<br>`docs/platform/architecture/resource-relationships.md` |
| `docs/assets/platform/architecture/04-revisions-and-replicas.png` | 2 | `docs/platform/architecture/index.md`<br>`docs/platform/reliability/health-recovery.md` |
| `docs/assets/platform/architecture/06-scale-blade.png` | 2 | `docs/platform/architecture/index.md`<br>`docs/platform/reliability/cost-optimization.md` |
| `docs/assets/platform/environments/02-workload-profiles.png` | 5 | `docs/platform/environments/dedicated-gpu-profiles.md`<br>`docs/platform/environments/index.md`<br>`docs/platform/environments/limits-and-quotas.md`<br>`docs/platform/environments/plans-and-workload-profiles.md`<br>`docs/platform/environments/workload-profiles.md` |
| `docs/assets/platform/environments/03-networking.png` | 6 | `docs/platform/environments/index.md`<br>`docs/platform/environments/migration.md`<br>`docs/platform/environments/networking-and-cidr.md`<br>`docs/platform/networking/egress-control.md`<br>`docs/platform/networking/private-endpoints.md`<br>`docs/platform/networking/vnet-integration.md` |
| `docs/assets/platform/identity-and-secrets/01-identity-blade.png` | 2 | `docs/platform/identity-and-secrets/managed-identity.md`<br>`docs/platform/security/image-security.md` |
| `docs/assets/platform/identity-and-secrets/03-secrets-blade.png` | 3 | `docs/platform/identity-and-secrets/key-vault.md`<br>`docs/platform/security/customer-managed-keys.md`<br>`docs/platform/security/secrets.md` |
| `docs/assets/platform/identity-and-secrets/04-iam-blade.png` | 2 | `docs/platform/identity-and-secrets/security-operations.md`<br>`docs/platform/security/index.md` |
| `docs/assets/platform/jobs/01-job-overview.png` | 3 | `docs/platform/jobs/index.md`<br>`docs/platform/jobs/jobs-vs-apps.md`<br>`docs/platform/jobs/manual-jobs.md` |
| `docs/assets/platform/networking/01-ingress-blade.png` | 2 | `docs/platform/networking/ingress.md`<br>`docs/platform/networking/service-to-service.md` |
| `docs/assets/platform/networking/02-environment-networking.png` | 4 | `docs/platform/networking/index.md`<br>`docs/platform/security/ingress-client-certificates.md`<br>`docs/platform/security/mtls.md`<br>`docs/platform/security/network-isolation.md` |
| `docs/assets/platform/revisions/01-revisions-replicas-blade.png` | 3 | `docs/platform/revisions/lifecycle.md`<br>`docs/platform/revisions/revision-modes.md`<br>`docs/platform/revisions/traffic-split.md` |
| `docs/assets/platform/scaling/01-scale-blade.png` | 5 | `docs/platform/scaling/cpu-memory-scaler.md`<br>`docs/platform/scaling/custom-scalers.md`<br>`docs/platform/scaling/event-scalers.md`<br>`docs/platform/scaling/http-scaler.md`<br>`docs/platform/scaling/scaling-rules-reference.md` |

## Caption and alt-text review queue

The script flags reuse, inconsistent alt text, and empty or generic alt text. Actual caption-to-image verification was **not collected** because this task did not open images.

| Asset | Review reason |
|---|---|
| `docs/assets/platform/architecture/02-resource-group-overview.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/architecture/04-revisions-and-replicas.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/architecture/06-scale-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/environments/02-workload-profiles.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/environments/03-networking.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/identity-and-secrets/01-identity-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/identity-and-secrets/03-secrets-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/identity-and-secrets/04-iam-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/jobs/01-job-overview.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/networking/01-ingress-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/networking/02-environment-networking.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/revisions/01-revisions-replicas-blade.png` | reused_across_pages, inconsistent_alt_text |
| `docs/assets/platform/scaling/01-scale-blade.png` | reused_across_pages, inconsistent_alt_text |

## Labs without Portal evidence

The table covers every tracked Markdown file under `docs/troubleshooting/lab-guides/` except the index. Existing issue assignments are shown so a future capture batch is not duplicated.

| Lab | Existing batch |
|---|---|
| `aca-secret-kv-ref-mi-network-path-h4b` | #362 (OPEN) |
| `aca-secret-kv-ref-mi-network-path-h4c` | #368 (OPEN) |
| `aca-secret-kv-ref-mi-network-path-h4d` | #366 (OPEN) |
| `aca-secret-kv-ref-mi-network-path-h4e` | #364 (OPEN) |
| `aca-secret-kv-ref-mi-network-path-h4f` | #372 (OPEN) |
| `aca-secret-kv-ref-mi-network-path-h4g` | #370 (OPEN) |
| `aca-secret-kv-ref-mi-network-path` | #308 (OPEN) |
| `appinsights-connection-string-missing` | unassigned |
| `azure-files-mount-failure` | unassigned |
| `bicep-deployment-timeout` | unassigned |
| `cpu-throttling` | unassigned |
| `custom-domain-tls-renewal` | unassigned |
| `dapr-pubsub-failure` | unassigned |
| `dapr-state-store-failure` | unassigned |
| `diagnostic-settings-missing` | unassigned |
| `docker-hub-rate-limit` | unassigned |
| `easyauth-entra-id-failure` | unassigned |
| `egress-ip-change` | unassigned |
| `emptydir-disk-full` | unassigned |
| `event-job-storm` | unassigned |
| `github-actions-oidc-failure` | unassigned |
| `image-size-startup-delay` | unassigned |
| `log-analytics-ingestion-gap` | unassigned |
| `min-replicas-cost-surprise` | unassigned |
| `multi-arch-image-mismatch` | unassigned |
| `multi-region-failover` | unassigned |
| `private-endpoint-dns-failure` | unassigned |
| `replica-load-imbalance` | unassigned |
| `revision-history-limit` | unassigned |
| `scheduled-job-missed` | unassigned |
| `session-affinity-failure` | unassigned |
| `subnet-cidr-exhaustion` | unassigned |
| `subscription-quota-exceeded` | unassigned |
| `udr-nsg-egress-blocked` | unassigned |
| `volume-permission-denied` | unassigned |
| `websocket-grpc-ingress` | unassigned |
| `workload-profile-mismatch` | unassigned |

Cross-repo issue `yeongseon/azure-functions-practical-guide#389` was checked directly: it is closed, covers Queue-trigger retry and poison-message assertions, and names no ACA Portal capture path or batch. It therefore creates no duplicate ACA assignment.

## State and verification limits

- Existing PNG or WebP bytes are not treated as independently verified final images.
- Legacy raw image links are inventoried as `manual-blocked`, not migrated or renamed.
- The report does not claim that a heuristic caption/alt candidate is a confirmed mismatch.
- Capture dates, live Azure reproduction, resource cleanup, and visual PII review were not collected.
- The seven ACA lab batches already tracked by #308, #362, #364, #366, #368, #370, and #372 are recorded in the JSON and are not reassigned here.

## See Also

- [Lab Portal Capture Briefs](../contributing/lab-portal-capture-briefs.md)
- [Troubleshooting Labs](../troubleshooting/lab-guides/index.md)

## Sources

- [Capture manifest workflow](https://github.com/yeongseon/azure-container-apps-practical-guide/blob/9cbf725392ae262dadf3553005172d7eda88c6a0/scripts/capture/README.md)
- [Issue #570 acceptance checklist](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/570)
