#!/usr/bin/env bash
# Spike 001 installer — wires the Stop hook into ~/.claude/settings.json and
# adds the flash_watcher item to the live sketchybar. Reversible via uninstall.sh.
#
# Idempotent: re-running upgrades the hook path and re-adds the item.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/forensic-log.sh"

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
SETTINGS="$HOME/.claude/settings.json"
BACKUP="$HOME/.claude/settings.json.spike-001.bak"
STOP_HOOK="$HERE/stop-hook.sh"
SESSION_START_HOOK="$HERE/session-start-hook.sh"
LISTENER="$HERE/flash-listener.sh"
STATE_DIR="${SPIKE_001_STATE_DIR:-/tmp/spike-001-sessions}"
mkdir -p "$STATE_DIR"

# Ensure scripts are executable (Write tool does not set +x).
chmod +x "$HERE"/*.sh

log install "starting"

# ── 1. Back up ~/.claude/settings.json (once) ─────────────────────────────
mkdir -p "$HOME/.claude"
if [ ! -f "$BACKUP" ] && [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUP"
  log install "backed up $SETTINGS to $BACKUP"
fi

# ── 2. Patch settings.json to register the Stop hook ──────────────────────
# If the file doesn't exist, create a minimal one. If it exists, merge in the
# Stop hook entry — replace any existing entry whose command points at our
# spike (so re-runs upgrade cleanly). Leaves unrelated hooks intact.
if [ ! -f "$SETTINGS" ]; then
  printf '{}\n' > "$SETTINGS"
fi

TMP="$(mktemp)"
"$JQ" --arg stop "$STOP_HOOK" --arg start "$SESSION_START_HOOK" '
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
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
log install "wired Stop hook → $STOP_HOOK"
log install "wired SessionStart hook → $SESSION_START_HOOK"

# ── 3. Wire sketchybar event + flash_watcher item ─────────────────────────
# Idempotent: --add event no-ops if it exists; we remove the item first if it
# already exists so the script path can be upgraded.
"$SKETCHYBAR" --add event flash_space 2>/dev/null || true

# Remove the watcher if it's already there (otherwise --add fails).
if "$SKETCHYBAR" --query flash_watcher >/dev/null 2>&1; then
  "$SKETCHYBAR" --remove flash_watcher 2>/dev/null || true
fi

"$SKETCHYBAR" --add item flash_watcher right \
              --set flash_watcher drawing=off updates=on script="$LISTENER" \
              --subscribe flash_watcher flash_space

log install "wired flash_watcher → $LISTENER"

cat <<EOF

✓ Spike 001 installed (Stop + SessionStart + flash listener).

Test path A — PRIMARY (SessionStart-captured window id):
  1. Open a NEW terminal window on the space you want to test.
  2. Launch \`claude\` there. The SessionStart hook captures that window's
     yabai id.
  3. Send any message. On turn-end, the Stop hook looks up the captured
     window id and flashes that window's CURRENT space — even if you've
     moved the window between spaces mid-session.

Test path B — FALLBACK (PPID walk + is-visible heuristic):
  Already-running Claude sessions (started before install) hit this path.
  Look for "strategy=fallback" in the log; for multi-window terminal apps
  it can pick the wrong window.

Tail the log:
  tail -f /tmp/spike-001-flash.log

Teardown: ./uninstall.sh

EOF
