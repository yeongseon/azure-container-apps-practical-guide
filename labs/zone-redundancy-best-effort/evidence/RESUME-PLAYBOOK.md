# Phase 2-7 Resume Playbook — zone-redundancy-best-effort

This document is the **resume runbook** for completing the Hybrid A reproduction
of [Issue #204](https://github.com/yeongseon/azure-container-apps-practical-guide/issues/204).
Phase 0 (honesty fix) and Phase 1 (Azure deploy + verify) are complete.

Phases 2-7 require either (a) a wall-clock 24 hour baseline window to elapse or
(b) hands-on perturbation, analysis, and lab guide updates by the next session.

## Phase status

| Phase | Description | Status | Output location |
|---|---|---|---|
| 0 | Honesty fix on existing lab guide | Done | commit `222151f` on `lab/zone-redundancy-best-effort-reproduce` |
| 1 | Azure deploy + verify (11/11 replicas Running) | Done | `evidence/*.log`, `evidence/*.json` |
| 2 | 24 hour baseline observation | In progress (passive, cron-driven) | `evidence/baseline-window.txt` |
| 3 | Perturbation tests (3 variants on app-min3) | Pending | `evidence/perturbation-*.log` |
| 4 | KQL Q1-Q4, Q6, Q7 + CSV export | Pending | `evidence/kql-*.csv` |
| 5 | Lab guide update (Section 12 + frontmatter flip) | Pending | `docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md` |
| 6 | PII scan + mkdocs strict + Oracle final review | Pending | inline |
| 7 | Cleanup + PR with `Closes #204` | Pending | branch push + PR |

## Environment recap (after Phase 1)

- **Subscription**: Visual Studio Enterprise Subscription (personal MSDN sub)
- **Tenant**: personal (NOT corp `microsoft.com`)
- **Resource group**: `rg-aca-zr-lab-260612114313` (`koreacentral`)
- **Container Apps env**: `cae-zrlab-5yi4px` (zone-redundant, workload profile)
- **Subject apps**: `app-min2` (min=max=2), `app-min3` (min=max=3), `app-min6` (min=max=6)
- **Audit job**: `audit-sampler` (cron `*/5 * * * *`, emits `ReplicaInventorySample` JSON to stdout)
- **Log Analytics**: `log-zrlab-5yi4px` (ingestion confirmed `2026-06-12T11:54Z`)
- **Baseline window start**: `2026-06-12T11:51:46Z`
- **Baseline window end**: `2026-06-13T11:51:46Z`
- **Resource expiry**: `2026-06-14T11:45:48Z` (48 hours from deploy — `expiryHours` tag)

## Resume workflow

### Step 1: Restore env vars

```bash
source labs/zone-redundancy-best-effort/evidence/deploy-env.sh
az account set --subscription "$SUBSCRIPTION_NAME"
LAW_CUSTOMER_ID=$(az monitor log-analytics workspace show --resource-group "$RG" --workspace-name "$LAW_NAME" --query customerId --output tsv)
echo "LAW: $LAW_CUSTOMER_ID"
```

### Step 2: Verify baseline window has completed (or is far enough along)

```bash
NOW=$(date -u +%s)
START=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$(cat labs/zone-redundancy-best-effort/evidence/baseline-window-start.txt)" +%s 2>/dev/null || date -u -d "$(cat labs/zone-redundancy-best-effort/evidence/baseline-window-start.txt)" +%s)
ELAPSED_HOURS=$(( (NOW - START) / 3600 ))
echo "Baseline elapsed: ${ELAPSED_HOURS}h (target: 24h)"
```

If `ELAPSED_HOURS >= 24` → proceed to Step 3.
If `ELAPSED_HOURS < 24` → wait, or accept a shorter window and document.

### Step 3: Run KQL Q1 (audit completeness)

```bash
az monitor log-analytics query --workspace "$LAW_CUSTOMER_ID" --analytics-query "
ContainerAppConsoleLogs_CL
| where TimeGenerated between (todatetime('$(cat labs/zone-redundancy-best-effort/evidence/baseline-window-start.txt)') .. now())
| where ContainerName_s == 'audit'
| where Log_s contains 'ReplicaInventorySample'
| extend parsed = parse_json(Log_s)
| project TimeGenerated, App=tostring(parsed.app), Observed=tolong(parsed.observedReplicaCount), MinConfigured=tolong(parsed.configuredMinReplicas)
| summarize SampleCount=count(), MinObserved=min(Observed), MaxObserved=max(Observed), MissingSamples=288 - count() by App
" --output table | tee labs/zone-redundancy-best-effort/evidence/q1-audit-completeness.log
```

288 expected = 24h × 12 samples/hour (every 5min).

### Step 4: Run perturbation tests (after baseline)

```bash
cd labs/zone-redundancy-best-effort

# Variant A: restart-only on app-min3 (single-app clustered churn — core Claim 3 signal)
RG="$RG" APP="app-min3" ./trigger.sh --perturb restart 2>&1 | tee evidence/perturbation-variant-a-restart-only.log

# Wait 10 min between variants for recovery + LAW ingestion latency
sleep 600

# Variant B: restart + load (no-retry client surfaces raw 503s)
RG="$RG" APP="app-min3" ./trigger.sh --combined --client no-retry --duration 180 2>&1 | tee evidence/perturbation-variant-b-restart-load.log

sleep 600

# Variant C: restart + load + retry-backoff client (quantifies L2 mitigation)
RG="$RG" APP="app-min3" ./trigger.sh --combined --client retry-backoff --duration 180 2>&1 | tee evidence/perturbation-variant-c-retry-backoff.log
```

### Step 5: Run remaining KQL queries

See `docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md`
for Q1-Q7 with column projections. Pipe each query to `evidence/q{N}-{description}.csv`.

### Step 6: Update lab guide (Section 12)

- Replace `[Strongly Suggested]` H0a row with `[Measured]` once 24h baseline yields zero clustered churn events
- Add new section "Mapping to ACA Non-Guarantee Claims" with Claim 2 + Claim 3 caveats
- Flip frontmatter `status: reproduced_partial` → `status: reproduced`
- Update `tested_date` to actual end-of-Phase-4 date

### Step 7: Validation + Oracle review

```bash
python3 scripts/normalize_yaml_frontmatter.py --check
python3 scripts/validate_content_sources.py
mkdocs build --strict
# Then resume Oracle session ses_144f3ce9cffeyOLLgO8doWTal3 with final review prompt
```

### Step 8: Cleanup + PR

```bash
# Verify all evidence committed
git status

# Cleanup Azure resources
cd labs/zone-redundancy-best-effort
./cleanup.sh  # interactive confirmation

# Push and open PR
git push origin lab/zone-redundancy-best-effort-reproduce
gh pr create --title "feat(labs): zone-redundancy-best-effort full 24h reproduction (Hybrid A)" --body "Closes #204..."
```

## Sanity checklist for resume session

- [ ] Baseline window has elapsed at least 23 hours (per `evidence/baseline-window-start.txt`)
- [ ] Audit job has not failed (`az containerapp job execution list --resource-group "$RG" --name audit-sampler --query "[?properties.status!='Succeeded']" --output table` returns empty)
- [ ] Resource group has NOT been auto-cleaned by `expires-hours` tag (manual check; the tag is informational, not enforced)
- [ ] Log Analytics ingestion still flowing (sanity Q1 returns >250 samples per app)

## If Phase 1 needs re-deployment

The audit image, Bicep template, and verify script live under
`labs/zone-redundancy-best-effort/`. To redeploy from scratch in a new RG:

```bash
NEW_SUFFIX=$(date -u +%y%m%d%H%M%S)
export RG="rg-aca-zr-lab-${NEW_SUFFIX}"
export ACR_NAME="acrzrlab${NEW_SUFFIX}"
export LOCATION="koreacentral"
az group create --name "$RG" --location "$LOCATION" --tags owner=lab purpose=zone-redundancy-best-effort issue=204 expires-hours=48 --output table
az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic --output table
az acr build --registry "$ACR_NAME" --image zr-lab/audit:latest labs/zone-redundancy-best-effort/audit
az deployment group create --resource-group "$RG" --name "zrlab-$(date -u +%Y%m%d%H%M%S)" --template-file labs/zone-redundancy-best-effort/infra/main.bicep --parameters labs/zone-redundancy-best-effort/infra/main.parameters.json --parameters baseName=zrlab expiryHours=48 auditImage="${ACR_NAME}.azurecr.io/zr-lab/audit:latest" auditAcrName="$ACR_NAME"
RG="$RG" labs/zone-redundancy-best-effort/verify.sh
```

## See also

- Lab guide: [`docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md`](../../../docs/troubleshooting/lab-guides/zone-redundancy-best-effort.md)
- KQL pack: [`docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md`](../../../docs/troubleshooting/kql/scaling-and-replicas/zone-redundancy-mass-reschedule.md)
- Playbook: [`docs/troubleshooting/playbooks/platform-features/zone-redundancy-best-effort.md`](../../../docs/troubleshooting/playbooks/platform-features/zone-redundancy-best-effort.md)
- Oracle session: `ses_144f3ce9cffeyOLLgO8doWTal3` (resume for Phase 6 final review)
