#!/usr/bin/env bash
# space_click.sh — pill click dispatcher (wired as each pill's click_script).
#
#   left / other button → focus the space (the original behaviour)
#   right button        → inline rename: the pill turns into an editable text
#                         field IN PLACE (no menu pops up). Enter or clicking
#                         away commits; Escape cancels. An empty name clears the
#                         label, so the pill falls back to showing the space
#                         number (handled by space.sh's empty-label branch).
#
# SketchyBar runs click_script with $BUTTON ∈ {left,right,other}. Older builds
# may not set it — then this falls through to "focus", preserving old behaviour.
#
# Wired up in spaces.sh:  click_script="$PLUGIN_DIR/space_click.sh <sid>"

. "$HOME/.config/sketchybar/theme.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

SID="${1:-${NAME#space.}}"

if [ "$BUTTON" != "right" ]; then
  exec "$YABAI" -m space --focus "$SID"
fi

# ─── right-click → inline rename ──────────────────────────────────────────
CUR_LABEL=$("$YABAI" -m query --spaces --space "$SID" 2>/dev/null | "$JQ" -r '.label // ""')

# The pill's on-screen rect. SketchyBar reports one rect per display; inactive
# displays carry a -9999 sentinel origin, so take the first real one.
RECT=$(sketchybar --query "space.$SID" 2>/dev/null | "$JQ" -r '
  [.bounding_rects[] | select(.origin[0] > -9000)][0]
  | "\(.origin[0]) \(.origin[1]) \(.size[0]) \(.size[1])"' 2>/dev/null)
[ -z "$RECT" ] || [ "$RECT" = "null" ] && exit 0
read -r SX SY PW PH <<<"$RECT"

# Active display's left edge (yabai CG global x) so the overlay maps SketchyBar's
# per-display rect onto the correct NSScreen on multi-monitor setups.
DISP_X=$("$YABAI" -m query --displays --display 2>/dev/null | "$JQ" -r '.frame.x // 0')

# AppKit overlay prints "COMMIT\t<text>" or "CANCEL". Editing colors = focused
# pill palette so the field reads as "active". Single source of truth = theme.sh.
RESULT=$(/usr/bin/swift "$PLUGIN_DIR/rename-overlay.swift" \
  "$CUR_LABEL" "$SX" "$SY" "$PW" "$PH" "$DISP_X" \
  "$COLOR_PILL_BG_FOCUSED" "$COLOR_PILL_FG_FOCUSED" "$PILL_CORNER_RADIUS" 2>/dev/null)

case "$RESULT" in
  COMMIT*)
    NEW=${RESULT#COMMIT$'\t'}
    "$YABAI" -m space "$SID" --label "$NEW" >/dev/null 2>&1
    sketchybar --trigger space_change >/dev/null 2>&1
    ;;
esac
