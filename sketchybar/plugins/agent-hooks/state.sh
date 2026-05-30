#!/usr/bin/env bash
# Shared state helpers for the agent-hooks plugin. Sourced by session-start.sh,
# turn-end.sh, install.sh, doctor.sh, etc. Defines paths under the spacetag
# state dir, a forensic logger (ISO-8601 + tag, append-only), a 7-day TTL prune
# for session files, and an idempotent mkdir helper.
#
# Source: . "$(dirname "$0")/state.sh"
#
# Env overrides:
#   SPACETAG_STATE_DIR  override the base state dir (default
#                       "$HOME/Library/Application Support/spacetag")
#   SPACETAG_LOG        override the forensic log path (default
#                       /tmp/agent-hooks.log)

agent_hooks_state_dir() {
  printf '%s\n' "${SPACETAG_STATE_DIR:-$HOME/Library/Application Support/spacetag}"
}

agent_hooks_sessions_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/sessions"
}

agent_hooks_backups_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/backups"
}

agent_hooks_log() {
  local tag="$1"; shift
  local log="${SPACETAG_LOG:-/tmp/agent-hooks.log}"
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$tag" "$*" >> "$log"
}

agent_hooks_prune_sessions() {
  find "$(agent_hooks_sessions_dir)" -type f -mtime +7 -delete 2>/dev/null || true
}

agent_hooks_ensure_dirs() {
  mkdir -p "$(agent_hooks_sessions_dir)" "$(agent_hooks_backups_dir)"
}
