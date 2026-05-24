#!/usr/bin/env bash
# position.sh — apply the user-selected pill layout to every space.* item.
#
# Mode is persisted in ~/.config/sketchybar/position (one of:
#   center | notch-left | notch-right | left | right).
# Runs on display_change, position_change, and at boot.
#
# For the notch-* layouts y_offset.sh shrinks the bar to a strip CENTERED on
# the notch (width = 2*NOTCH_PILL_ROOM, via margin = notch_left-NOTCH_PILL_ROOM).
# Items lay out inside that strip, so to push the notch-side pill flush against
# the notch we add boundary padding to the first item, measured from the STRIP
# edge (subtract the margin M) rather than the screen edge. On a flat display
# the notch layouts collapse to center (matching y_offset.sh's full-width bar).

. "$HOME/.config/sketchybar/theme.sh"

POS_FILE="$HOME/.config/sketchybar/position"
MODE="$(cat "$POS_FILE" 2>/dev/null || echo center)"
case "$MODE" in center|notch-left|notch-right|left|right) ;; *) MODE=center ;; esac

active_dims=$("$YABAI" -m query --displays --display 2>/dev/null \
             | "$JQ" -r '"\(.frame.w|floor)x\(.frame.h|floor)"' 2>/dev/null)

# <kind>:<screen_w>:<notch_left>:<notch_right>
geom=$(TARGET="$active_dims" /usr/bin/swift -e '
import AppKit
let target = ProcessInfo.processInfo.environment["TARGET"] ?? ""
for s in NSScreen.screens {
  let w = Int(s.frame.size.width)
  if "\(w)x\(Int(s.frame.size.height))" == target {
    if s.safeAreaInsets.top > 0 {
      let l = Int((s.auxiliaryTopLeftArea  ?? .zero).size.width)
      let r = Int(CGFloat(w) - (s.auxiliaryTopRightArea ?? .zero).size.width)
      print("NOTCH:\(w):\(l):\(r)")
    } else {
      print("FLAT:\(w):0:0")
    }
    exit(0)
  }
}
print("FLAT:0:0:0")
' 2>/dev/null)

IFS=: read -r kind screen_w notch_left notch_right <<<"$geom"
: "${kind:=FLAT}" "${screen_w:=0}" "${notch_left:=0}" "${notch_right:=0}"

# notch-* against a flat display: collapse to plain center (no notch to hug).
case "$kind:$MODE" in
  FLAT:notch-left|FLAT:notch-right) MODE=center ;;
esac

# Bar padding is 8 on each side (see sketchybarrc). M is the notch strip's
# margin — the strip's left edge sits at M, its right edge at screen_w - M —
# so boundary padding is measured from there, not from the screen edge.
BAR_PAD=8
M=$(( notch_left - NOTCH_PILL_ROOM ))
[ "$M" -lt 0 ] && M=0

group=center
boundary_padding_side=
boundary_padding=0

case "$MODE" in
  center) group=center ;;
  left)   group=left   ;;
  right)  group=right  ;;
  notch-right)
    # Items packed from the strip's left edge → push the leftmost one flush to
    # the notch's right edge.
    group=left
    boundary_padding_side=left
    boundary_padding=$(( notch_right - M + NOTCH_SIDE_GAP - BAR_PAD ))
    ;;
  notch-left)
    # Items packed from the strip's right edge → push the rightmost one flush
    # to the notch's left edge.
    group=right
    boundary_padding_side=right
    boundary_padding=$(( (screen_w - M) - notch_left + NOTCH_SIDE_GAP - BAR_PAD ))
    ;;
esac

[ "$boundary_padding" -lt 0 ] && boundary_padding=0

# Numeric sort by sid so "first" matches sketchybar's add-order, which is
# what anchors the right/left group's boundary item.
SPACE_ITEMS=$(sketchybar --query bar 2>/dev/null \
              | "$JQ" -r '.items[]?' 2>/dev/null \
              | /usr/bin/sed -n 's/^space\.//p' \
              | /usr/bin/sort -n \
              | /usr/bin/sed 's/^/space./')

[ -z "$SPACE_ITEMS" ] && exit 0

# Pills should always read ascending (space.1 … space.N) left→right. A `right`
# group packs from the right edge, so its first item lands rightmost — which
# reverses the visual order. Reverse the item order for right groups to cancel
# that out (left/center groups keep ascending order). SketchyBar's first
# internal item sits at the group's anchored edge (left edge for left groups,
# right edge for right groups) — which for the notch layouts is the notch side
# — so the boundary-padded anchor pill is always the first item in this order.
if [ "$group" = right ]; then
  order=$(printf '%s\n' "$SPACE_ITEMS" \
          | /usr/bin/sed -n 's/^space\.//p' \
          | /usr/bin/sort -rn \
          | /usr/bin/sed 's/^/space./')
else
  order="$SPACE_ITEMS"
fi
anchor=$(printf '%s\n' "$order" | /usr/bin/sed -n '1p')

for item in $order; do
  pl=4; pr=4
  if [ "$item" = "$anchor" ]; then
    case "$boundary_padding_side" in
      left)  pl="$boundary_padding" ;;
      right) pr="$boundary_padding" ;;
    esac
  fi
  sketchybar --set "$item" position="$group" padding_left="$pl" padding_right="$pr" >/dev/null
done

# Apply the visual order: no-op for left/center, un-reverses right groups.
# shellcheck disable=SC2086
sketchybar --reorder $order >/dev/null 2>&1
