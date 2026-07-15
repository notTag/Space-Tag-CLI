#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../state.sh"
. "$HERE/common.sh"

YQ="${YQ:-$(command -v yq)}"
CONFIG="$HOME/.hermes/config.yaml"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"
SESSION_START_CMD="$SCRIPTS_DIR/session-start.sh"
TURN_END_CMD="$SCRIPTS_DIR/turn-end.sh hermes"

require_yq() {
  if [ -z "$YQ" ] || ! command -v "$YQ" >/dev/null 2>&1; then
    echo "ERROR: yq is required for hermes adapter. Install: brew install yq" >&2
    return 1
  fi
}

cmd_install() {
  adapter_detect hermes || { agent_hooks_log adapter_hermes "hermes not installed (no $CONFIG), skipping"; echo "hermes: not installed (no $CONFIG)"; return 0; }
  require_yq || return 1
  adapter_backup_once "$CONFIG" hermes-config.yaml

  if ! "$YQ" -i '
    .hooks.on_session_start = ((.hooks.on_session_start // []) | map(select(.command != "'"$SESSION_START_CMD"'"))) + [{"command": "'"$SESSION_START_CMD"'", "timeout": 5}] |
    .hooks.post_llm_call = ((.hooks.post_llm_call // []) | map(select(.command != "'"$TURN_END_CMD"'"))) + [{"command": "'"$TURN_END_CMD"'", "timeout": 5}]
  ' "$CONFIG"; then
    echo "hermes: failed to rewrite $CONFIG" >&2
    return 1
  fi

  agent_hooks_log adapter_hermes "wired on_session_start=$SESSION_START_CMD post_llm_call=$TURN_END_CMD"

  cat <<EOF
hermes: installed (on_session_start + post_llm_call wired → $SCRIPTS_DIR)
  Note: next interactive 'hermes' invocation will prompt one time to allow
        these new hooks. Bypass with --accept-hooks flag, HERMES_ACCEPT_HOOKS=1
        env, or set hooks_auto_accept: true in config.yaml.
EOF

  if command -v hermes >/dev/null 2>&1; then
    hermes hooks doctor 2>&1 | while IFS= read -r line; do
      agent_hooks_log adapter_hermes "doctor: $line"
    done || true
  fi
}

cmd_uninstall() {
  adapter_detect hermes || { echo "hermes: not installed"; return 0; }
  require_yq || return 1
  local backup
  backup="$(agent_hooks_backups_dir)/$(date +%Y-%m-%d)/hermes-config.yaml"
  if [ -f "$backup" ]; then
    cp "$backup" "$CONFIG"
    agent_hooks_log adapter_hermes "restored $CONFIG from $backup"
    echo "hermes: uninstalled (restored from $backup)"
    return 0
  fi
  if ! "$YQ" -i '
    .hooks.on_session_start = ((.hooks.on_session_start // []) | map(select(.command != "'"$SESSION_START_CMD"'"))) |
    .hooks.post_llm_call = ((.hooks.post_llm_call // []) | map(select(.command != "'"$TURN_END_CMD"'")))
  ' "$CONFIG"; then
    echo "hermes: failed to rewrite $CONFIG" >&2
    return 1
  fi
  agent_hooks_log adapter_hermes "stripped entries from $CONFIG (no backup found)"
  echo "hermes: uninstalled (stripped entries; no backup found)"
}

cmd_status() {
  if ! adapter_detect hermes; then echo "hermes: not installed (no $CONFIG)"; return 1; fi
  require_yq || return 1
  local has_start has_end
  has_start=$("$YQ" '[.hooks.on_session_start[]? | select(.command == "'"$SESSION_START_CMD"'")] | length' "$CONFIG" 2>/dev/null)
  has_end=$("$YQ" '[.hooks.post_llm_call[]? | select(.command == "'"$TURN_END_CMD"'")] | length' "$CONFIG" 2>/dev/null)
  if [ "${has_start:-0}" -ge 1 ] && [ "${has_end:-0}" -ge 1 ]; then
    echo "hermes: installed"
    return 0
  fi
  echo "hermes: not installed"
  return 1
}

case "${1:-status}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *) echo "usage: $0 {install|uninstall|status}" >&2; exit 2 ;;
esac
