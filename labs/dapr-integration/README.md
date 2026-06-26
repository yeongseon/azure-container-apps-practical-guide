# Lab: Dapr Integration

Reproducible bounded-falsification lab for Azure Container Apps workloads that use Dapr sidecar service invocation with an application that really binds `0.0.0.0:8000`.

This Phase B pack preserves the historical 2026-06-03 `containerapps-helloworld` Portal captures while adding a live Flask-on-8000 cohort that makes the Dapr `appPort` `8000 -> 8081 -> 8000` arc cleanly falsifiable. The bounded claim is narrow: with Dapr kept enabled and ingress still targeting `8000`, changing only `properties.configuration.dapr.appPort` to `8081` breaks sidecar-to-app invocation while the ingress root endpoint can still return HTTP 200.

## Structure

```text
labs/dapr-integration/
├── infra/main.bicep        # Shared infra + ACR + conditional app deployment
├── workload/               # Flask + Gunicorn workload that really listens on 8000
├── fix-and-capture.sh      # Phase A live reproduction: deploy, capture 12 raw files, restore, verify, clean up
├── verify.sh               # Phase B offline verifier: 17 gates total, 4 derived gate JSONs emitted
├── trigger.sh              # Manual trigger helper
├── cleanup.sh              # Manual cleanup helper
├── evidence/               # 12 raw files + 4 derived gate JSONs + evidence README
└── README.md               # This lab overview and claim-ceiling disclosure
```

## Hypotheses

1. **H1 — Trigger produces failure.** If Dapr stays enabled but `appPort` changes from the app's real listener `8000` to `8081`, ingress to `/` can still return HTTP 200 while the observed pre-fix failure surface appears on the loopback Dapr probe path and in the sidecar `ProbeFailed` logs.
2. **H2 — Fix restores recovery.** Restoring `appPort` to `8000` with `az containerapp dapr enable --dapr-app-port 8000` restores the healthy/running post-fix state and returns the Dapr config to the real listener.

## Evidence pack

See [`evidence/README.md`](evidence/README.md) for the file-by-file tour and Gate 14-17 summary.

## Reproducibility

| Command | Why it is used |
|---|---|
| `cd labs/dapr-integration/` | Enters the lab directory so relative evidence paths resolve correctly. |
| `bash verify.sh` | Recomputes Gate 14 through Gate 17 from committed evidence without touching Azure. |

```bash
cd labs/dapr-integration/
bash verify.sh
```

The live capture workflow exists for future reproductions:

| Command | Why it is used |
|---|---|
| `cd labs/dapr-integration/` | Enters the lab directory for the live capture workflow. |
| `bash fix-and-capture.sh` | Provisions the shared infra, builds and pushes the Flask-on-8000 image, captures the H1/H2 cohort, sanitizes evidence, runs the offline verifier, and starts RG cleanup. |

```bash
cd labs/dapr-integration/
bash fix-and-capture.sh
```

## Documentation cross-reference

- Lab guide: [`docs/troubleshooting/lab-guides/dapr-integration.md`](../../docs/troubleshooting/lab-guides/dapr-integration.md)
- Evidence tour: [`evidence/README.md`](evidence/README.md)
