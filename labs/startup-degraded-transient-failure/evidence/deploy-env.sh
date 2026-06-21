#!/usr/bin/env bash
# Source this file in a fresh shell to re-establish the lab working context.
# Usage: source labs/startup-degraded-transient-failure/evidence/deploy-env.sh

export RG="rg-aca-sdlab-260612125433"
export LOCATION="koreacentral"
export ACR_NAME="acrsdlab260612125433"
export SUFFIX="260612125433"
export BASE_NAME="sdlab"
export SUBJECT_STARTUP_DELAY_SECONDS=25
export EXPIRY_HOURS=48

# Image references (built by az acr build during deploy phase)
export SUBJECT_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/subject:latest"
export AUDIT_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/audit:latest"
export PERTURBATION_SAMPLER_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/perturbation-sampler:latest"
export LOADGEN_IMAGE="${ACR_NAME}.azurecr.io/startup-degraded/loadgen:latest"

# Subject app endpoint (populated after first deployment; trigger.sh re-queries
# this at runtime, so the value here is informational for ad-hoc curl checks)
export SUBJECT_FQDN="subject-app.niceglacier-27358013.koreacentral.azurecontainerapps.io"
export SUBJECT_URL="https://${SUBJECT_FQDN}/"
export SUBJECT_HEALTHZ_URL="https://${SUBJECT_FQDN}/healthz"

# Container Apps environment (informational)
export ENV_NAME="cae-sdlab-wxxzoc"
export LAW_NAME="log-sdlab-wxxzoc"
export UAMI_NAME="id-sdlab-wxxzoc"

# Expected expiry tag (deployment time + EXPIRY_HOURS)
export EXPIRES_AT="2026-06-14T12:58:11Z"
