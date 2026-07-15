#!/usr/bin/env bash

agent_hooks_state_dir() {
  printf '%s\n' "${SPACETAG_STATE_DIR:-$HOME/Library/Application Support/spacetag}"
}

agent_hooks_sessions_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/sessions"
}

agent_hooks_backups_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/backups"
}

agent_hooks_pending_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/pending-flash"
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
  mkdir -p "$(agent_hooks_sessions_dir)" "$(agent_hooks_backups_dir)" "$(agent_hooks_pending_dir)"
}
