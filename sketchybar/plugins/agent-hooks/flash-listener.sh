#!/usr/bin/env bash
# Sketchybar event handler — runs when `flash_space` is triggered.
# Receives SID + TOOL via env from `sketchybar --trigger flash_space SID=N TOOL=...`.
# Animates the matching pill's background to the tool color, holds, then reverts
# to the theme-correct steady-state color for the pill (focused vs unfocused).
#
# Wired by sketchybarrc:
#   sketchybar --add event flash_space
#   sketchybar --add item flash_watcher right \
#     --set flash_watcher drawing=off updates=on script=<this script> \
#     --subscribe flash_watcher flash_space
#
# Production port of .planning/spikes/001-e2e-claude-flash/flash-listener.sh
# with two changes:
#   1. Per-tool color map (claude / codex / hermes) sourced from theme.sh.
#   2. Inlined log helper (no state.sh dep) so it stays runnable from
#      sketchybar's exec env, which doesn't carry SPACETAG_STATE_DIR.

set -u

# Source theme first so $COLOR_FLASH_* and $COLOR_PILL_BG{,_FOCUSED} are in
# scope. theme.sh's tail sources theme.local.sh, so user overrides apply
# automatically (e.g. custom flash colors).
. "$HOME/.config/sketchybar/theme.sh"

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
YABAI="${YABAI:-/opt/homebrew/bin/yabai}"

# Inlined forensic log helper — kept self-contained so this script runs cleanly
# under sketchybar's minimal exec env (no SPACETAG_STATE_DIR, no PATH to state.sh).
log() {
  printf '%s flash_listener %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$*" \
    >> "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
}

# Sketchybar passes the triggering event name as $SENDER and the custom kv args
# (SID, TOOL) as plain env vars.
log "fired SENDER=${SENDER:-?} SID=${SID:-?} TOOL=${TOOL:-?}"

if [ -z "${SID:-}" ]; then
  log "ERROR no SID in trigger env"
  exit 0
fi

PILL="space.$SID"

# Bail loud if the pill doesn't exist (wrong space, rename race).
PILL_QUERY="$("$SKETCHYBAR" --query "$PILL" 2>/dev/null)"
if [ -z "$PILL_QUERY" ] || [ "$PILL_QUERY" = "null" ]; then
  log "ERROR pill $PILL not found"
  exit 0
fi

# Per-tool flash color — theme.sh owns the values.
case "${TOOL:-}" in
  claude) FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;
  codex)  FLASH_COLOR="$COLOR_FLASH_CODEX"  ;;
  hermes) FLASH_COLOR="$COLOR_FLASH_HERMES" ;;
  *)      FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;  # default → orange
esac

# Resolve revert color from theme.sh, NOT raw queried bg. Raw query returns
# the transparent default (alpha 00) for pills that never had bg explicitly
# set, which would leave the pill looking broken after the flash. space.sh
# repaints on every focus change with $COLOR_PILL_BG{_FOCUSED}, so we revert
# to those values to match its steady state. (Spike iteration 2 finding.)
FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null \
  | "$JQ" -r '.index // empty')"

if [ "$SID" = "$FOCUSED_SID" ]; then
  REVERT_BG="$COLOR_PILL_BG_FOCUSED"
  STATE=focused
else
  REVERT_BG="$COLOR_PILL_BG"
  STATE=unfocused
fi
log "revert plan: $PILL state=$STATE revert_bg=$REVERT_BG"

# Animate flash in (15 frames ~ 250ms at 60fps).
"$SKETCHYBAR" --animate sin_in_out 15 \
  --set "$PILL" background.color="$FLASH_COLOR"
log "flashed $PILL to $FLASH_COLOR"

# Hold briefly, then revert. Background subshell so the trigger returns
# immediately and doesn't block sketchybar's event loop.
(
  sleep 0.6
  "$SKETCHYBAR" --animate sin_in_out 20 \
    --set "$PILL" background.color="$REVERT_BG"
  log "reverted $PILL to $REVERT_BG ($STATE)"
) &

exit 0
