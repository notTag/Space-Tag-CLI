#!/usr/bin/env bash

. "$HOME/.config/sketchybar/theme.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

SID="${1:-${NAME#space.}}"

if [ "$BUTTON" != "right" ]; then
  exec "$YABAI" -m space --focus "$SID"
fi

CUR_LABEL=$("$YABAI" -m query --spaces --space "$SID" 2>/dev/null | "$JQ" -r '.label // ""')

RECT=$(sketchybar --query "space.$SID" 2>/dev/null | "$JQ" -r '
  [.bounding_rects[] | select(.origin[0] > -9000)][0]
  | "\(.origin[0]) \(.origin[1]) \(.size[0]) \(.size[1])"' 2>/dev/null)
[ -z "$RECT" ] || [ "$RECT" = "null" ] && exit 0
read -r SX SY PW PH <<<"$RECT"

DISP_X=$("$YABAI" -m query --displays --display 2>/dev/null | "$JQ" -r '.frame.x // 0')

SRC="$PLUGIN_DIR/rename-overlay.swift"
CACHE_DIR="$HOME/.config/sketchybar/cache"
BIN="$CACHE_DIR/rename-overlay"
# Interpreted Swift adds visible latency to every right-click.
if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  mkdir -p "$CACHE_DIR"
  command -v swiftc >/dev/null 2>&1 && swiftc -o "$BIN" "$SRC" 2>/dev/null
fi

if [ -x "$BIN" ]; then
  RESULT=$("$BIN" \
    "$CUR_LABEL" "$SX" "$SY" "$PW" "$PH" "$DISP_X" \
    "$COLOR_PILL_BG" "$COLOR_PILL_FG" "$COLOR_PILL_BG_FOCUSED" "$PILL_CORNER_RADIUS" 2>/dev/null)
else
  RESULT=$(/usr/bin/swift "$SRC" \
    "$CUR_LABEL" "$SX" "$SY" "$PW" "$PH" "$DISP_X" \
    "$COLOR_PILL_BG" "$COLOR_PILL_FG" "$COLOR_PILL_BG_FOCUSED" "$PILL_CORNER_RADIUS" 2>/dev/null)
fi

case "$RESULT" in
  COMMIT*)
    NEW=${RESULT#COMMIT$'\t'}
    "$YABAI" -m space "$SID" --label "$NEW" >/dev/null 2>&1
    sketchybar --trigger space_change >/dev/null 2>&1
    ;;
esac
