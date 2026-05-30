#!/usr/bin/env bash
# Spike 001 teardown — restores ~/.claude/settings.json from backup and removes
# the flash_watcher sketchybar item + flash_space event subscription.
#
# Safe to run even if install.sh was never run.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/forensic-log.sh"

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.spike-001.bak"
STOP_HOOK="$HERE/stop-hook.sh"
SESSION_START_HOOK="$HERE/session-start-hook.sh"
STATE_DIR="${SPIKE_001_STATE_DIR:-/tmp/spike-001-sessions}"

log uninstall "starting"

# ── 1. Restore settings.json ───────────────────────────────────────────────
if [ -f "$BACKUP" ]; then
  cp "$BACKUP" "$SETTINGS"
  rm "$BACKUP"
  log uninstall "restored $SETTINGS from backup"
else
  # No backup → just strip our hook entry from the current file (in case the
  # user installed atop a missing file and we created one).
  if [ -f "$SETTINGS" ]; then
    TMP="$(mktemp)"
    "$JQ" --arg stop "$STOP_HOOK" --arg start "$SESSION_START_HOOK" '
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
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    log uninstall "stripped Stop + SessionStart hook entries from $SETTINGS"
  fi
fi

# ── 1b. Clean session-start state dir ──────────────────────────────────────
if [ -d "$STATE_DIR" ]; then
  rm -rf "$STATE_DIR"
  log uninstall "removed state dir $STATE_DIR"
fi

# ── 2. Remove sketchybar item ──────────────────────────────────────────────
if "$SKETCHYBAR" --query flash_watcher >/dev/null 2>&1; then
  "$SKETCHYBAR" --remove flash_watcher 2>/dev/null || true
  log uninstall "removed flash_watcher item"
fi

# Note: sketchybar doesn't support --remove event. The custom event sticks
# until next --reload, which is fine (no subscriber = no-op).

cat <<EOF

✓ Spike 001 uninstalled. Forensic log preserved at /tmp/spike-001-flash.log.

EOF
