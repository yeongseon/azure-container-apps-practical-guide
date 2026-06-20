#!/usr/bin/env bash
set -euo pipefail

# Verify the lab's failure -> recovery flow. If the latest revision is not
# Healthy we apply a YAML recovery patch that pins the Startup probe to "/" on
# nginx:alpine, then re-check health. The CLI does not expose a flag to remove
# a probe, so recovery must go through the YAML API.

: "${APP_NAME:?APP_NAME must be set}"
: "${RG:?RG must be set}"

get_latest_health() {
    az containerapp revision list \
        --name "$APP_NAME" \
        --resource-group "$RG" \
        --query "sort_by([].{created:properties.createdTime,health:properties.healthState}, &created)[-1].health" \
        --output tsv
}

echo "Checking current revision health..."
HEALTH="$(get_latest_health)"
echo "Current revision health: $HEALTH"

if [ "$HEALTH" = "Healthy" ]; then
    echo "PASS: Latest revision is Healthy"
    exit 0
fi

echo "INFO: Latest revision is '$HEALTH' - applying recovery YAML (good probe path '/')..."

RECOVERY_TIMESTAMP="$(date +%s)"
REVISION_SUFFIX="healthy${RECOVERY_TIMESTAMP}"
PATCH_FILE="$(mktemp -t revprov-recovery-XXXXXX.yaml)"
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
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 3
        timeoutSeconds: 2
EOF

az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --yaml "$PATCH_FILE" \
    --output none

echo "Waiting for new revision to stabilize..."
sleep 30

POST_FIX_HEALTH="$(get_latest_health)"
echo "After fix: Revision health is '$POST_FIX_HEALTH'"

if [ "$POST_FIX_HEALTH" = "Healthy" ]; then
    echo "PASS: Recovery successful - Startup probe now targets a valid path"
else
    echo "FAIL: Recovery unsuccessful"
    exit 1
fi
