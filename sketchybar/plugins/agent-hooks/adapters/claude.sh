#!/usr/bin/env bash
#
# adapters/claude.sh — Claude Code installer for the SpaceTag agent-hooks plugin.
#
# Wires two hooks into ~/.claude/settings.json:
#   .hooks.Stop[]         → turn-end.sh claude       (flash on turn end)
#   .hooks.SessionStart[] → session-start.sh         (capture window id)
#
# Subcommands: install | uninstall | status
#
# Idempotent jq-merge mirrors the proven spike-001 install pattern: per event,
# strip any existing entry whose .command matches our cmd, drop empty matcher
# groups, then append our entry under matcher "". Preserves all unrelated user
# hooks (sfx-play.sh, gsd-*, context-mode, etc.).
#
# Uninstall prefers byte-for-byte restore from the dated backup created by
# adapter_backup_once; falls back to jq-strip if the backup is missing.
#
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../state.sh"
. "$HERE/common.sh"

JQ="${JQ:-/opt/homebrew/bin/jq}"
SETTINGS="$HOME/.claude/settings.json"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"
SESSION_START_CMD="$SCRIPTS_DIR/session-start.sh"
STOP_CMD="$SCRIPTS_DIR/turn-end.sh claude"
BACKUP_NAME="claude-settings.json"

cmd_install() {
  if ! adapter_detect claude; then
    agent_hooks_log adapter_claude "skip install: ~/.claude/settings.json absent"
    echo "claude: skipped (settings.json absent)"
    return 0
  fi

  adapter_backup_once "$SETTINGS" "$BACKUP_NAME" \
    || { echo "claude: backup failed for $SETTINGS" >&2; return 1; }

  adapter_strip_spike_entries "$SETTINGS" || {
    echo "claude: failed to clean legacy spike hooks in $SETTINGS" >&2
    return 1
  }

  local tmp; tmp="$(mktemp)"
  if ! "$JQ" --arg stop "$STOP_CMD" --arg start "$SESSION_START_CMD" '
    .hooks //= {} |
    # Stop
    .hooks.Stop //= [] |
    .hooks.Stop = (
      (.hooks.Stop | map(
        .hooks = ((.hooks // []) | map(select(.command != $stop)))
      ) | map(select((.hooks | length) > 0)))
      + [{matcher: "", hooks: [{type: "command", command: $stop}]}]
    ) |
    # SessionStart
    .hooks.SessionStart //= [] |
    .hooks.SessionStart = (
      (.hooks.SessionStart | map(
        .hooks = ((.hooks // []) | map(select(.command != $start)))
      ) | map(select((.hooks | length) > 0)))
      + [{matcher: "", hooks: [{type: "command", command: $start}]}]
    )
  ' "$SETTINGS" > "$tmp"; then
    rm -f "$tmp"
    echo "claude: failed to rewrite $SETTINGS" >&2
    return 1
  fi
  if ! mv "$tmp" "$SETTINGS"; then
    rm -f "$tmp"
    echo "claude: failed to replace $SETTINGS" >&2
    return 1
  fi

  agent_hooks_log adapter_claude "wired Stop=$STOP_CMD SessionStart=$SESSION_START_CMD"
  echo "claude: installed (hooks Stop + SessionStart wired → $SCRIPTS_DIR)"
}

cmd_uninstall() {
  local today; today="$(date +%Y-%m-%d)"
  local backup; backup="$(agent_hooks_backups_dir)/$today/$BACKUP_NAME"

  if [ -f "$backup" ]; then
    cp "$backup" "$SETTINGS"
    agent_hooks_log adapter_claude "uninstalled: restored $SETTINGS from $backup"
    echo "claude: uninstalled (restored from backup $backup)"
    return 0
  fi

  if [ ! -f "$SETTINGS" ]; then
    agent_hooks_log adapter_claude "uninstall: nothing to do, $SETTINGS missing"
    echo "claude: uninstalled (no settings.json present)"
    return 0
  fi

  local tmp; tmp="$(mktemp)"
  if ! "$JQ" --arg stop "$STOP_CMD" --arg start "$SESSION_START_CMD" '
    if .hooks.Stop then
      .hooks.Stop = (
        (.hooks.Stop | map(
          .hooks = ((.hooks // []) | map(select(.command != $stop)))
        ) | map(select((.hooks | length) > 0)))
      )
    else . end |
    if .hooks.SessionStart then
      .hooks.SessionStart = (
        (.hooks.SessionStart | map(
          .hooks = ((.hooks // []) | map(select(.command != $start)))
        ) | map(select((.hooks | length) > 0)))
      )
    else . end
  ' "$SETTINGS" > "$tmp"; then
    rm -f "$tmp"
    echo "claude: failed to rewrite $SETTINGS" >&2
    return 1
  fi
  if ! mv "$tmp" "$SETTINGS"; then
    rm -f "$tmp"
    echo "claude: failed to replace $SETTINGS" >&2
    return 1
  fi

  agent_hooks_log adapter_claude "uninstalled: stripped Stop + SessionStart entries from $SETTINGS"
  echo "claude: uninstalled (stripped entries; no backup found for today)"
}

cmd_status() {
  if [ ! -f "$SETTINGS" ]; then
    echo "claude: not installed"
    return 1
  fi

  local has_stop has_start
  has_stop=$("$JQ" --arg c "$STOP_CMD" \
    '[.hooks.Stop[]?.hooks[]?.command // empty | select(. == $c)] | length' \
    "$SETTINGS" 2>/dev/null)
  has_start=$("$JQ" --arg c "$SESSION_START_CMD" \
    '[.hooks.SessionStart[]?.hooks[]?.command // empty | select(. == $c)] | length' \
    "$SETTINGS" 2>/dev/null)

  if [ "${has_stop:-0}" -ge 1 ] && [ "${has_start:-0}" -ge 1 ]; then
    echo "claude: installed"
    return 0
  fi
  echo "claude: not installed"
  return 1
}

case "${1:-status}" in
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  *) echo "usage: $0 {install|uninstall|status}" >&2; exit 2 ;;
esac
