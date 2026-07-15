#!/usr/bin/env bash

set -u

STATE_SH="$HOME/.config/sketchybar/plugins/agent-hooks/state.sh"
if [ -f "$STATE_SH" ]; then
  . "$STATE_SH"
else
  agent_hooks_pending_dir() {
    printf '%s\n' "$HOME/Library/Application Support/spacetag/pending-flash"
  }
fi

SKETCHYBAR="${SKETCHYBAR:-$(command -v sketchybar || echo /opt/homebrew/bin/sketchybar)}"
YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
JQ="${JQ:-$(command -v jq || echo /opt/homebrew/bin/jq)}"

log() {
  printf '%s flash_reconcile %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$*" \
    >> "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
}

PENDING_DIR="$(agent_hooks_pending_dir)"
[ -d "$PENDING_DIR" ] || exit 0

FOCUSED_WIN="$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty')"
FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null | "$JQ" -r '.index // empty')"

LIVE_WINS=" $("$YABAI" -m query --windows 2>/dev/null | "$JQ" -r '.[].id' | tr '\n' ' ')"

changed=0

if [ "${SENDER:-}" = "window_destroyed" ] && [ -n "${WIN:-}" ]; then
  for f in "$PENDING_DIR"/*; do
    [ -e "$f" ] || continue
    IFS=' ' read -r _t w < "$f" 2>/dev/null
    if [ -n "${w:-}" ] && [ "$w" = "$WIN" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared ${f##*/} (win=$WIN destroyed)"
    fi
  done
fi

for f in "$PENDING_DIR"/*; do
  [ -e "$f" ] || continue
  sid="${f##*/}"
  IFS=' ' read -r _tool win < "$f" 2>/dev/null
  [ -n "${_tool:-}" ] || continue

  if [ -n "${win:-}" ]; then
    if [ -n "$FOCUSED_WIN" ] && [ "$win" = "$FOCUSED_WIN" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (win=$win focused)"
    # An empty snapshot means yabai was unreachable, not that every window closed.
    elif [ "$LIVE_WINS" != " " ] && [ "${LIVE_WINS#* $win }" = "$LIVE_WINS" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (win=$win closed)"
    fi
  else
    if [ -n "$FOCUSED_SID" ] && [ "$sid" = "$FOCUSED_SID" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (space focused, no win)"
    fi
  fi
done

if [ "$changed" = "1" ]; then
  "$SKETCHYBAR" --trigger space_change >/dev/null 2>&1 || true
fi

exit 0
