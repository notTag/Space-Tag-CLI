#!/usr/bin/env bash
# Pin sketchybar to the active display, set the correct y_offset for it,
# and fade the space pills in on the new display.
#
# yabai's has-notch field is unreliable across versions, so we ask AppKit
# directly via a tiny swift one-liner: any screen whose safeAreaInsets.top
# > 0 is notched. We match the active yabai display by width+height.

. "$HOME/.config/sketchybar/theme.sh"

active=$("$YABAI" -m query --displays --display 2>/dev/null)
active_index=$(printf '%s' "$active" | "$JQ" -r '.index' 2>/dev/null)
active_dims=$(printf '%s' "$active"  | "$JQ" -r '"\(.frame.w|floor)x\(.frame.h|floor)"' 2>/dev/null)

[ -z "$active_index" ] && exit 0

active_state=$(TARGET="$active_dims" /usr/bin/swift -e '
import AppKit
let target = ProcessInfo.processInfo.environment["TARGET"] ?? ""
for s in NSScreen.screens {
  let dims = "\(Int(s.frame.size.width))x\(Int(s.frame.size.height))"
  if dims == target {
    print(s.safeAreaInsets.top > 0 ? "NOTCH" : "FLAT")
    exit(0)
  }
}
print("FLAT")
' 2>/dev/null)

if [ "$active_state" = "NOTCH" ]; then
  y="$Y_OFFSET_NOTCH"
else
  y="$Y_OFFSET_FLAT"
fi

# ─── fade-in pills on the new display ────────────────────────────────────
# Order matters:
#   1. Snap pills transparent BEFORE the bar moves, so when it arrives on
#      the new display the pills are already invisible (no "flash" of the
#      pre-move visible state).
#   2. Move the bar (pin to active display + y_offset).
#   3. Pause one render tick so the transparent frame paints.
#   4. Animate each pill back to its real focused/unfocused target colors.
SPACE_ITEMS=$(sketchybar --query bar 2>/dev/null \
              | "$JQ" -r '.items[]?' 2>/dev/null \
              | /usr/bin/grep '^space\.' || true)

SPACES_JSON=$("$YABAI" -m query --spaces 2>/dev/null)

# Phase 1: invisible (before bar moves)
for item in $SPACE_ITEMS; do
  sketchybar --set "$item" \
    icon.color="$COLOR_PILL_FG_HIDDEN" \
    label.color="$COLOR_PILL_FG_HIDDEN" \
    background.color="$COLOR_PILL_BG_HIDDEN" >/dev/null
done

# Phase 2: move the bar to the active display with the correct offset
sketchybar --bar display="$active_index" y_offset="$y"

# Phase 3: let the transparent frame paint on the new display
sleep 0.05

# Phase 4: animate each pill to its real target color
for item in $SPACE_ITEMS; do
  sid="${item#space.}"
  focused=$(printf '%s' "$SPACES_JSON" \
            | "$JQ" -r --argjson s "$sid" '.[] | select(.index == $s) | ."has-focus" // false')
  if [ "$focused" = "true" ]; then
    bg="$COLOR_PILL_BG_FOCUSED"; fg="$COLOR_PILL_FG_FOCUSED"
  else
    bg="$COLOR_PILL_BG"; fg="$COLOR_PILL_FG"
  fi
  sketchybar --animate "$ANIM_CURVE" "$ANIM_FRAMES_DISPLAY_FADE" --set "$item" \
    icon.color="$fg" label.color="$fg" background.color="$bg" >/dev/null
done
