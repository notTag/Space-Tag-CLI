#!/usr/bin/env bash

set -u

. "$HOME/.config/sketchybar/theme.sh"
STATE_SH="$HOME/.config/sketchybar/plugins/agent-hooks/state.sh"
if [ -f "$STATE_SH" ]; then
  . "$STATE_SH"
else
  agent_hooks_pending_dir() {
    printf '%s\n' "$HOME/Library/Application Support/spacetag/pending-flash"
  }
fi

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
YABAI="${YABAI:-/opt/homebrew/bin/yabai}"

log() {
  printf '%s flash_listener %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$*" \
    >> "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
}

log "fired SENDER=${SENDER:-?} SID=${SID:-?} TOOL=${TOOL:-?}"

if [ -z "${SID:-}" ]; then
  log "ERROR no SID in trigger env"
  exit 0
fi

PILL="space.$SID"

PILL_QUERY="$("$SKETCHYBAR" --query "$PILL" 2>/dev/null)"
if [ -z "$PILL_QUERY" ] || [ "$PILL_QUERY" = "null" ]; then
  log "ERROR pill $PILL not found"
  exit 0
fi

case "${TOOL:-}" in
  claude) FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;
  codex)  FLASH_COLOR="$COLOR_FLASH_CODEX"  ;;
  hermes) FLASH_COLOR="$COLOR_FLASH_HERMES" ;;
  *)      FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;
esac

FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null \
  | "$JQ" -r '.index // empty')"
FOCUSED_WIN="$("$YABAI" -m query --windows --window 2>/dev/null \
  | "$JQ" -r '.id // empty')"

if [ -n "${WIN:-}" ]; then
  [ "$WIN" = "$FOCUSED_WIN" ] && ON_TRIGGER=1 || ON_TRIGGER=0
else
  [ "$SID" = "$FOCUSED_SID" ] && ON_TRIGGER=1 || ON_TRIGGER=0
fi

PENDING_DIR="$(agent_hooks_pending_dir)"
mkdir -p "$PENDING_DIR" 2>/dev/null

if [ "$ON_TRIGGER" = "1" ]; then
  rm -f "$PENDING_DIR/$SID" 2>/dev/null
  REVERT_BG="$COLOR_PILL_BG_FOCUSED"
  N="${FLASH_COUNT:-5}"
  log "active flash: $PILL ${N}x to $FLASH_COLOR, settle $REVERT_BG (win=${WIN:-?})"

  # Do not block SketchyBar's event loop for the duration of the animation.
  (
    i=0
    while [ "$i" -lt "$N" ]; do
      "$SKETCHYBAR" --animate sin_in_out 10 \
        --set "$PILL" background.color="$FLASH_COLOR"
      sleep 0.35
      "$SKETCHYBAR" --animate sin_in_out 10 \
        --set "$PILL" background.color="$REVERT_BG"
      sleep 0.35
      i=$((i + 1))
    done
    # Re-derive focus after the animation in case the user changed spaces.
    "$SKETCHYBAR" --trigger space_change >/dev/null 2>&1 || true
    log "active flash done $PILL ($N cycles)"
  ) &
else
  printf '%s %s\n' "${TOOL:-claude}" "${WIN:-}" > "$PENDING_DIR/$SID" 2>/dev/null
  "$SKETCHYBAR" --animate sin_in_out 15 \
    --set "$PILL" background.color="$FLASH_COLOR"
  log "held flash: $PILL to $FLASH_COLOR (pending until win=${WIN:-?} focused, tool=${TOOL:-claude})"
fi

exit 0
