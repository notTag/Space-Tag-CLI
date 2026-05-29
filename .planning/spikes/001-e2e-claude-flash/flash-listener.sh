#!/usr/bin/env bash
# Sketchybar event handler — runs when `flash_space` is triggered.
# Receives SID + TOOL via env from `sketchybar --trigger flash_space SID=N TOOL=...`.
# Animates the matching pill's background to the tool color, holds, then reverts
# to the pill's pre-flash background.
#
# Wired by install.sh:
#   sketchybar --add event flash_space
#   sketchybar --add item flash_watcher right \
#     --set flash_watcher drawing=off updates=on script=<this script> \
#     --subscribe flash_watcher flash_space

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/forensic-log.sh"

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"

# Sketchybar passes the triggering event name as $SENDER and the custom kv args
# (SID, TOOL) as plain env vars.
log flash_listener "fired SENDER=${SENDER:-?} SID=${SID:-?} TOOL=${TOOL:-?}"

if [ -z "${SID:-}" ]; then
  log flash_listener "ERROR no SID in trigger env"
  exit 0
fi

PILL="space.$SID"

# Hardcoded spike colors (per discuss-phase decisions):
#   claude=orange, codex=periwinkle. Default → orange.
case "${TOOL:-}" in
  codex)  FLASH_COLOR=0xffb6a8e8 ;;  # periwinkle
  *)      FLASH_COLOR=0xffff8800 ;;  # orange (claude + default)
esac

# Bail loud if the pill doesn't exist (wrong space, rename race).
PILL_QUERY="$("$SKETCHYBAR" --query "$PILL" 2>/dev/null)"
if [ -z "$PILL_QUERY" ] || [ "$PILL_QUERY" = "null" ]; then
  log flash_listener "ERROR pill $PILL not found"
  exit 0
fi

# Determine the *correct* revert color from theme.sh, not the raw queried bg.
# A queried bg can be transparent (0x00000000) if no one ever set it explicitly,
# and reverting to that leaves the pill looking broken. Source theme + ask
# yabai whether this SID is the currently-focused space, then choose
# COLOR_PILL_BG_FOCUSED vs COLOR_PILL_BG accordingly.
. "$HOME/.config/sketchybar/theme.sh"

YABAI="${YABAI:-/opt/homebrew/bin/yabai}"
FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null \
  | "$JQ" -r '.index // empty')"

if [ "$SID" = "$FOCUSED_SID" ]; then
  REVERT_BG="$COLOR_PILL_BG_FOCUSED"
  STATE=focused
else
  REVERT_BG="$COLOR_PILL_BG"
  STATE=unfocused
fi
log flash_listener "revert plan: $PILL state=$STATE revert_bg=$REVERT_BG"

# Animate flash in (15 frames ~ 250ms at 60fps).
"$SKETCHYBAR" --animate sin_in_out 15 \
  --set "$PILL" background.color="$FLASH_COLOR"
log flash_listener "flashed $PILL to $FLASH_COLOR"

# Hold briefly, then revert to the proper theme color. Background subshell so
# the trigger returns immediately and doesn't block sketchybar's event loop.
(
  sleep 0.6
  "$SKETCHYBAR" --animate sin_in_out 20 \
    --set "$PILL" background.color="$REVERT_BG"
  log flash_listener "reverted $PILL to $REVERT_BG ($STATE)"
) &

exit 0
