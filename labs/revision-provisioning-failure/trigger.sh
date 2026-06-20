#!/usr/bin/env bash
set -euo pipefail

# Trigger revision provisioning failure by applying a YAML patch that swaps the
# image to nginx:alpine (which returns 404 on unknown paths) and configures a
# Startup probe against a non-existent path. The CLI does not expose
# --startup-probe-* flags, so probes must be configured through the YAML API.

: "${APP_NAME:?APP_NAME must be set}"
: "${RG:?RG must be set}"

PROBE_TIMESTAMP="$(date +%s)"
REVISION_SUFFIX="badpath${PROBE_TIMESTAMP}"
PATCH_FILE="$(mktemp -t revprov-trigger-XXXXXX.yaml)"
trap 'rm -f "$PATCH_FILE"' EXIT

cat > "$PATCH_FILE" <<EOF
properties:
  template:
    revisionSuffix: ${REVISION_SUFFIX}
    containers:
    - name: app
      image: nginx:alpine
      resources:
        cpu: 0.5
        memory: 1Gi
      probes:
      - type: Startup
        httpGet:
          path: /nonexistent-health-endpoint
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
        timeoutSeconds: 2
EOF

echo "Triggering revision failure by applying YAML patch (revision suffix: ${REVISION_SUFFIX})..."
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --yaml "$PATCH_FILE" \
    --output none

echo ""
echo "Waiting for revision update..."
sleep 30

echo ""
echo "Checking revision status..."
az containerapp revision list --name "$APP_NAME" --resource-group "$RG" --output table

echo ""
echo "Checking system logs for probe failures..."
az containerapp logs show --name "$APP_NAME" --resource-group "$RG" --type system --tail 30 2>/dev/null || echo "Logs may take a moment to appear"
