#!/usr/bin/env bash
# Per-tool installer adapter for Codex's ~/.codex/hooks.json.
#
# Codex's hook schema nests one level deeper than Claude's: each event
# (Stop, SessionStart, …) holds an array of *groups*, and each group has its
# own nested `.hooks[]` of {type, command, timeout} entries. So our merge
# target is .hooks.Stop[0].hooks[] — not .hooks.Stop[].hooks[] (Claude).
#
# Subcommands:
#   install    backup once, strip spike-001 entries, jq-merge our Stop +
#              SessionStart commands into group [0] of each event (creating
#              the wrapper if the outer array is empty); warn about Codex's
#              trust-hash prompt on first run.
#   uninstall  restore byte-for-byte from today's dated backup if present;
#              otherwise jq-strip just our commands and drop any group whose
#              .hooks array ends up empty.
#   status     0 + "codex: installed" if both Stop and SessionStart contain
#              our commands; 1 otherwise.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../state.sh"
. "$HERE/common.sh"

JQ="${JQ:-/opt/homebrew/bin/jq}"
HOOKS_JSON="$HOME/.codex/hooks.json"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"
SESSION_START_CMD="$SCRIPTS_DIR/session-start.sh"
STOP_CMD="$SCRIPTS_DIR/turn-end.sh codex"

cmd_install() {
  adapter_detect codex || { agent_hooks_log adapter_codex "codex not installed (no $HOOKS_JSON), skipping"; echo "codex: not installed (no $HOOKS_JSON)"; return 0; }
  adapter_backup_once "$HOOKS_JSON" codex-hooks.json
  adapter_strip_spike_entries "$HOOKS_JSON" || {
    echo "codex: failed to clean legacy spike hooks in $HOOKS_JSON" >&2
    return 1
  }

  local tmp; tmp="$(mktemp)"
  # Codex shape: .hooks.{Stop,SessionStart}[0].hooks[]
  # If the outer array is empty, create the [0] wrapper as well.
  if ! "$JQ" --arg stop "$STOP_CMD" --arg start "$SESSION_START_CMD" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    (if (.hooks.Stop | length) == 0
      then .hooks.Stop = [{hooks: []}]
      else . end) |
    .hooks.Stop[0].hooks = (
      ((.hooks.Stop[0].hooks // []) | map(select(.command != $stop)))
      + [{type: "command", command: $stop, timeout: 5}]
    ) |
    .hooks.SessionStart //= [] |
    (if (.hooks.SessionStart | length) == 0
      then .hooks.SessionStart = [{hooks: []}]
      else . end) |
    .hooks.SessionStart[0].hooks = (
      ((.hooks.SessionStart[0].hooks // []) | map(select(.command != $start)))
      + [{type: "command", command: $start, timeout: 5}]
    )
  ' "$HOOKS_JSON" > "$tmp"; then
    rm -f "$tmp"
    echo "codex: failed to rewrite $HOOKS_JSON" >&2
    return 1
  fi
  if ! mv "$tmp" "$HOOKS_JSON"; then
    rm -f "$tmp"
    echo "codex: failed to replace $HOOKS_JSON" >&2
    return 1
  fi
  agent_hooks_log adapter_codex "wired Stop=$STOP_CMD SessionStart=$SESSION_START_CMD"

  cat <<EOF
codex: installed (Stop + SessionStart wired → $SCRIPTS_DIR)
  Note: first Codex turn after install may prompt for trust on these new hooks.
        Allow them to proceed (or set codex_hooks = true in config.toml to
        bypass the prompt entirely).
EOF
}

cmd_uninstall() {
  adapter_detect codex || { echo "codex: not installed"; return 0; }
  local backup; backup="$(agent_hooks_backups_dir)/$(date +%Y-%m-%d)/codex-hooks.json"
  if [ -f "$backup" ]; then
    cp "$backup" "$HOOKS_JSON"
    agent_hooks_log adapter_codex "restored $HOOKS_JSON from $backup"
    echo "codex: uninstalled (restored from $backup)"
    return 0
  fi
  # Fallback: jq-strip our commands
  local tmp; tmp="$(mktemp)"
  if ! "$JQ" --arg stop "$STOP_CMD" --arg start "$SESSION_START_CMD" '
    if .hooks.Stop then
      .hooks.Stop = (.hooks.Stop | map(
        .hooks = ((.hooks // []) | map(select(.command != $stop)))
      ) | map(select((.hooks | length) > 0)))
    else . end |
    if .hooks.SessionStart then
      .hooks.SessionStart = (.hooks.SessionStart | map(
        .hooks = ((.hooks // []) | map(select(.command != $start)))
      ) | map(select((.hooks | length) > 0)))
    else . end
  ' "$HOOKS_JSON" > "$tmp"; then
    rm -f "$tmp"
    echo "codex: failed to rewrite $HOOKS_JSON" >&2
    return 1
  fi
  if ! mv "$tmp" "$HOOKS_JSON"; then
    rm -f "$tmp"
    echo "codex: failed to replace $HOOKS_JSON" >&2
    return 1
  fi
  agent_hooks_log adapter_codex "stripped Stop + SessionStart entries from $HOOKS_JSON"
  echo "codex: uninstalled (stripped entries; no backup found)"
}

cmd_status() {
  if ! adapter_detect codex; then echo "codex: not installed (no $HOOKS_JSON)"; return 1; fi
  local has_stop has_start
  has_stop=$("$JQ" --arg c "$STOP_CMD" '[.hooks.Stop[0].hooks[]? | select(.command == $c)] | length' "$HOOKS_JSON" 2>/dev/null)
  has_start=$("$JQ" --arg c "$SESSION_START_CMD" '[.hooks.SessionStart[0].hooks[]? | select(.command == $c)] | length' "$HOOKS_JSON" 2>/dev/null)
  if [ "${has_stop:-0}" -ge 1 ] && [ "${has_start:-0}" -ge 1 ]; then
    echo "codex: installed"
    return 0
  fi
  echo "codex: not installed"
  return 1
}

case "${1:-status}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *) echo "usage: $0 {install|uninstall|status}" >&2; exit 2 ;;
esac
