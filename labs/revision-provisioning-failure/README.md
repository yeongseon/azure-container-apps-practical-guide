# Lab: Revision Provisioning Failure

Reproducible bounded-falsification lab for Azure Container Apps revisions that are accepted by the control plane but never become ready because the startup probe contract is violated at runtime.

The reusable Jun 20 / Jun 21 cohort in `evidence/` captures the wrong-path (`404`) variant on `ca-labrevprov-e2upm2` in `rg-aca-lab-revprov`. H1 shows `ca-labrevprov-e2upm2--badpath2` failing because `nginx:alpine` returns `404` on `/nonexistent-health-endpoint`; H2 shows `ca-labrevprov-e2upm2--badpath3` recovering when the probe path is corrected to `/`.

The lab tests two hypotheses:

1. **H1 — Trigger produces failure.** A startup probe that targets `/nonexistent-health-endpoint` on `nginx:alpine` produces repeated `ProbeFailed` events, `ContainerTerminated(ProbeFailure)` restarts, and a Failed / Unhealthy revision.
2. **H2 — Fix restores recovery.** Replacing the startup probe path with `/` produces a new Healthy / Provisioned revision with zero post-fix `ProbeFailed` rows on the recovered revision.

This evidence pack falsifies the hypothesis within a bounded scope. Gate 17 demonstrates that probe path reachability is the mechanically observable trigger field. The pack does NOT prove: image byte-identity (the H1/H2 tag remains `nginx:alpine`, but digests were not captured); pod reuse (revisions have different replica pods); socket listening port (inferred from spec, not directly captured); probe field delta minus path (H1 vs H2 also differ in `httpGet.scheme`, `initialDelaySeconds`, `timeoutSeconds`, and `successThreshold` — these confounders are documented in `cohort_binding_note.explicit_drops`, not bounded).

## Structure

```text
labs/revision-provisioning-failure/
├── infra/main.bicep        # Baseline environment + app deployment
├── fix-and-capture.sh      # Phase A live reproduction: deploy/reuse RG, trigger H1, capture 12 raw files, apply H2, call verify.sh
├── verify.sh               # Phase B offline verifier: 17 gates total, 4 derived gate JSONs emitted
├── workload/               # Original Flask workload retained for historical context
├── evidence/               # 12 raw files + 4 derived gate JSONs + evidence README
└── README.md               # This lab overview and claim-ceiling disclosure
```

## Cohort summary

- **Resource group:** `rg-aca-lab-revprov`
- **Container app:** `ca-labrevprov-e2upm2`
- **Region:** `koreacentral`
- **Revision lineage:** `ca-labrevprov-e2upm2--badpath` → `ca-labrevprov-e2upm2--badpath2` → `ca-labrevprov-e2upm2--badpath3` (the pre-trigger baseline `badpath` revision still used `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`; the bounded H1↔H2 comparison begins at `badpath2` → `badpath3`)
- **Bounded trigger field:** startup-probe `httpGet.path`
- **Held constant fields:** image tag `nginx:alpine`, CPU `0.5`, memory `1Gi`, probe type `Startup`, probe port `80`, `failureThreshold=3`, `periodSeconds=5`

## Evidence pack

See [`evidence/README.md`](evidence/README.md) for the 16-file index, capture purposes, and gate descriptions.

## File index

| File | Size | Purpose |
|---|---:|---|
| `infra/main.bicep` | 2.2 KB | Baseline lab infrastructure for reproducible redeploys |
| `fix-and-capture.sh` | 7.3 KB | Live Phase A trigger + fix + raw evidence capture workflow |
| `verify.sh` | 49.7 KB | Offline 17-gate verifier that emits Gate 14-17 JSONs |
| `evidence/README.md` | 4.7 KB | Evidence tour and 16-file index |
| `README.md` | 3.9 KB | Lab overview and bounded-falsification framing |

## Reproducibility

The committed Phase B verifier is hermetic:

| Command | Why it is used |
|---|---|
| `cd labs/revision-provisioning-failure/` | Enters the lab directory so the relative evidence paths resolve correctly. |
| `bash verify.sh` | Recomputes Gate 14 through Gate 17 from the committed evidence cohort without touching Azure. |

```bash
cd labs/revision-provisioning-failure/
bash verify.sh
```

The live script exists for future reproductions but is not required for this Phase B pack:

| Command | Why it is used |
|---|---|
| `cd labs/revision-provisioning-failure/` | Enters the lab directory for the live capture workflow. |
| `bash fix-and-capture.sh` | Recreates the raw H1/H2 evidence cohort from Azure and then runs the offline verifier. |

```bash
cd labs/revision-provisioning-failure/
bash fix-and-capture.sh
```

## Documentation cross-reference

- Lab guide: [`docs/troubleshooting/lab-guides/revision-provisioning-failure.md`](../../docs/troubleshooting/lab-guides/revision-provisioning-failure.md)
- Evidence tour: [`evidence/README.md`](evidence/README.md)
