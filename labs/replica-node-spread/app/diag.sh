#!/usr/bin/env bash
# diag.sh — emit one JSON object describing this replica's kernel
# context. Invoked via `az containerapp exec --command "/usr/local/bin/diag.sh"`.
#
# Fields:
#   replica_hostname        Container hostname (replica name fragment)
#   boot_id                 /proc/sys/kernel/random/boot_id — primary
#                           proxy signal for "shared kernel context"
#   uptime_seconds          Seconds since the kernel booted
#   machine_id              /etc/machine-id, often empty inside containers
#   kernel_release          uname -r — kernel version of the host
#   microcode               First /proc/cpuinfo `microcode` value
#   cpu_model               CPU model from /proc/cpuinfo
#   container_app_name      $CONTAINER_APP_NAME env var (set by ACA)
#   container_app_revision  $CONTAINER_APP_REVISION env var
#   container_app_replica   $CONTAINER_APP_REPLICA_NAME env var
#   inner_timestamp_ms      Wall-clock at sample time inside container
#
# NO sample-time anchor for boot_time_estimate is computed here. The
# caller (sample.sh) records the local timestamp at the moment of the
# exec call and computes boot_time_estimate = local_sample_ts - uptime
# during analysis. This avoids depending on clock alignment between
# the container and the operator's workstation (in practice they share
# the same kernel clock, but the analysis is more defensible when the
# anchor is a single source of truth).

set -uo pipefail

# Pure-bash field extractor; avoids dependency on awk/gawk inside the
# container. cbl-mariner base does not ship awk by default and pulling
# gawk in just for two `awk -F:` calls is wasteful.

read_or_default() {
  local path="$1" default="$2"
  if [[ -r "$path" ]]; then
    head -n1 "$path" | tr -d '\r\n'
  else
    printf '%s' "$default"
  fi
}

# Extract the value after `<key>:` from /proc/cpuinfo for the first
# matching line. Returns "unknown" if the key is missing.
proc_cpuinfo_field() {
  local key="$1"
  local line
  line=$(grep -m1 "^${key}" /proc/cpuinfo 2>/dev/null || true)
  if [[ -z "$line" ]]; then
    printf 'unknown'
    return
  fi
  local value="${line#*:}"
  # Strip leading/trailing whitespace via bash parameter expansion.
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ -z "$value" ]]; then
    printf 'unknown'
  else
    printf '%s' "$value"
  fi
}

boot_id=$(read_or_default /proc/sys/kernel/random/boot_id "unknown")
machine_id=$(read_or_default /etc/machine-id "")
kernel_release=$(uname -r 2>/dev/null || printf 'unknown')

# /proc/uptime first field is seconds since boot, as a float.
# Read the whole line, then split on whitespace.
if [[ -r /proc/uptime ]]; then
  read -r uptime_first _ </proc/uptime
  uptime_seconds="${uptime_first:-0}"
else
  uptime_seconds="0"
fi

# microcode is per-CPU; the first occurrence is representative for our
# experiment (host nodes are homogeneous within a workload profile).
microcode=$(proc_cpuinfo_field "microcode")
cpu_model=$(proc_cpuinfo_field "model name")

# Millisecond-precision wall clock. Containers share the host's clock,
# but we still capture it for cross-check against the operator-side
# stamp recorded by sample.sh.
inner_ts_ms=$(date -u +%s%3N 2>/dev/null || date -u +%s000)

# Prefer /etc/hostname (always present) over `hostname` binary, which
# is not installed in the cbl-mariner base.
hostname_val=$(read_or_default /etc/hostname "${HOSTNAME:-unknown}")

jq -cn \
  --arg event "ReplicaDiagSample" \
  --arg replica_hostname "$hostname_val" \
  --arg boot_id "$boot_id" \
  --arg uptime_seconds "$uptime_seconds" \
  --arg machine_id "$machine_id" \
  --arg kernel_release "$kernel_release" \
  --arg microcode "$microcode" \
  --arg cpu_model "$cpu_model" \
  --arg container_app_name "${CONTAINER_APP_NAME:-}" \
  --arg container_app_revision "${CONTAINER_APP_REVISION:-}" \
  --arg container_app_replica "${CONTAINER_APP_REPLICA_NAME:-}" \
  --arg inner_timestamp_ms "$inner_ts_ms" \
  '{
    event: $event,
    replica_hostname: $replica_hostname,
    boot_id: $boot_id,
    uptime_seconds: ($uptime_seconds | tonumber),
    machine_id: $machine_id,
    kernel_release: $kernel_release,
    microcode: $microcode,
    cpu_model: $cpu_model,
    container_app_name: $container_app_name,
    container_app_revision: $container_app_revision,
    container_app_replica: $container_app_replica,
    inner_timestamp_ms: ($inner_timestamp_ms | tonumber)
  }'
