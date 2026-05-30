#!/usr/bin/env bash
# Append-only forensic logger for spike 001. Every script in this spike sources
# this and uses `log <tag> <message>` so we can reconstruct what happened on
# any given completion. ISO-8601 + category tag = grep/awk friendly.
#
# Source: . "$(dirname "$0")/forensic-log.sh"

SPIKE_LOG="${SPIKE_LOG:-/tmp/spike-001-flash.log}"

log() {
  local tag="$1"; shift
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$tag" "$*" >> "$SPIKE_LOG"
}
