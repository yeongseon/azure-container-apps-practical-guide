#!/usr/bin/env bash
# Audit sampler for startup-degraded-transient-failure lab.
#
# Acquires an IMDS token using the user-assigned managed identity, then
# polls the ARM REST API every SAMPLE_INTERVAL_SECONDS (default 30s) for
# the duration of the job execution and emits two event types as JSON
# lines on stdout (which Container Apps ships to Log Analytics):
#
#   ReplicaInventorySample - one line per (revision, replica) pair.
#   RevisionStateSample    - one line per revision with traffic weight,
#                            provisioning state, and active flag.
#
# Mirrors labs/zone-redundancy-best-effort/audit/sample.sh but adds the
# RevisionStateSample event type per lab design D7.
#
# Required environment:
#   SUBSCRIPTION_ID          ARM subscription GUID.
#   RESOURCE_GROUP           ARM resource group name.
#   CONTAINER_APP_NAMES      Comma-separated list of subject app names.
#   MANAGED_IDENTITY_CLIENT_ID  Client ID of the user-assigned identity
#                            (used to disambiguate when the pod is bound
#                            to multiple identities).
#   SAMPLE_INTERVAL_SECONDS  Optional, default 30 seconds.
#   RUN_LABEL                Optional free-form tag emitted in every line.

set -euo pipefail

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID is required}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
: "${CONTAINER_APP_NAMES:?CONTAINER_APP_NAMES is required (comma-separated)}"
: "${MANAGED_IDENTITY_CLIENT_ID:?MANAGED_IDENTITY_CLIENT_ID is required}"

SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-30}"
RUN_LABEL="${RUN_LABEL:-lab-audit}"

ARM_RESOURCE="https://management.azure.com/"

# Container Apps does NOT expose IMDS at 169.254.169.254. It uses the
# App Service-style identity endpoint exposed via the IDENTITY_ENDPOINT
# and IDENTITY_HEADER environment variables, which the platform injects
# into every container bound to a managed identity. The endpoint is
# typically http://localhost:42356/msi/token and rejects requests
# without the X-IDENTITY-HEADER token.
#
# Mirrors labs/zone-redundancy-best-effort/audit/sample.sh which uses
# the same pattern and is proven to work in this environment.
acquire_token() {
  local endpoint header
  endpoint="${IDENTITY_ENDPOINT:-}"
  header="${IDENTITY_HEADER:-}"

  if [[ -z "$endpoint" || -z "$header" ]]; then
    echo "ERROR: IDENTITY_ENDPOINT / IDENTITY_HEADER not set inside container; managed identity not bound or platform did not inject env vars" >&2
    return 1
  fi

  curl --silent --show-error --fail \
    --header "X-IDENTITY-HEADER: ${header}" \
    "${endpoint}?api-version=2019-08-01&resource=${ARM_RESOURCE}&client_id=${MANAGED_IDENTITY_CLIENT_ID}" \
    | jq --raw-output '.access_token'
}

emit() {
  jq --null-input --compact-output \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg run_label "${RUN_LABEL}" \
    --argjson body "$1" \
    '$body + {ts: $ts, run_label: $run_label}'
}

sample_replicas() {
  local app_name="$1"
  local token="$2"

  local replicas_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app_name}/revisions?api-version=2024-03-01"

  local revisions
  revisions=$(curl --silent --fail \
    --header "Authorization: Bearer ${token}" \
    "${replicas_url}") || return 0

  echo "${revisions}" | jq --compact-output \
    --arg app "${app_name}" \
    '.value[] | {kind: "RevisionStateSample", app: $app, revision: .name, active: .properties.active, replicas: .properties.replicas, traffic_weight: (.properties.trafficWeight // null), provisioning_state: .properties.provisioningState, created_time: .properties.createdTime, last_active_time: .properties.lastActiveTime}' \
    | while read -r rev_line; do
        emit "${rev_line}"
      done

  echo "${revisions}" | jq --raw-output --arg app "${app_name}" \
    '.value[] | .name' | while read -r rev_name; do
      local replicas_detail_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/${app_name}/revisions/${rev_name}/replicas?api-version=2024-03-01"
      local detail
      detail=$(curl --silent --fail \
        --header "Authorization: Bearer ${token}" \
        "${replicas_detail_url}") || continue

      echo "${detail}" | jq --compact-output \
        --arg app "${app_name}" \
        --arg rev "${rev_name}" \
        '.value[] | {kind: "ReplicaInventorySample", app: $app, revision: $rev, replica: .name, running_state: (.properties.runningState // null), created_time: (.properties.createdTime // null), containers: (.properties.containers // []) | length}' \
        | while read -r line; do
            emit "${line}"
          done
    done
}

main() {
  local token
  token=$(acquire_token)

  IFS=',' read -ra APPS <<< "${CONTAINER_APP_NAMES}"

  while true; do
    for app in "${APPS[@]}"; do
      sample_replicas "${app}" "${token}"
    done
    sleep "${SAMPLE_INTERVAL_SECONDS}"
  done
}

main "$@"
