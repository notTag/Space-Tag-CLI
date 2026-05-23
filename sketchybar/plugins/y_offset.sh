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

# Ask AppKit for two live values:
#   • safeAreaInsets.top — non-zero on notched MBPs (~37–38pt). Used to
#     branch NOTCH vs FLAT (and we don't actually need the value, just the
#     sign).
#   • NSStatusBar.system.thickness — the OS's current menu bar thickness.
#     ~24pt on flat displays, ~38pt on notched, and changes if the user
#     enables "Larger Text" accessibility. Pulling it live means we don't
#     hardcode 24 and the pill row tracks system-wide menu bar changes.
# Output format: NOTCH:<thickness> or FLAT:<thickness>
active_state=$(TARGET="$active_dims" /usr/bin/swift -e '
import AppKit
let target = ProcessInfo.processInfo.environment["TARGET"] ?? ""
let thickness = Int(NSStatusBar.system.thickness)
for s in NSScreen.screens {
  let dims = "\(Int(s.frame.size.width))x\(Int(s.frame.size.height))"
  if dims == target {
    let kind = s.safeAreaInsets.top > 0 ? "NOTCH" : "FLAT"
    print("\(kind):\(thickness)")
    exit(0)
  }
}
print("FLAT:\(thickness)")
' 2>/dev/null)

# Split "<kind>:<thickness>"
kind="${active_state%%:*}"
menu_h="${active_state##*:}"

case "$kind" in
  NOTCH)
    # On notched displays macOS clamps sketchybar's bar to either screen
    # top (y_offset=0, behind the notch) or the safe-area edge (y_offset≥1,
    # snug under the notch). Intermediate y_offset values get clipped, AND
    # item.y_offset is squeezed by the bar's vertical bounds, so neither
    # axis alone can add a gap. Instead, grow the bar height by 2*NOTCH_GAP
    # — items stay centered, so pills shift down by NOTCH_GAP relative to
    # the safe-area edge. Base height = PILL_HEIGHT (so NOTCH_GAP=0 means
    # pills flush at the safe-area edge). topmost=off so windows can cover
    # and click through the pills.
    y=1
    topmost=off
    height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
    ;;
  *)
    # Flat displays render the bar inside the menu bar region; height
    # tracks the OS menu bar thickness so pills always fit native height.
    # Without topmost the menu bar intercepts clicks and pills become inert.
    y="$Y_OFFSET_FLAT"
    topmost=on
    height="$menu_h"
    ;;
esac

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
sketchybar --bar display="$active_index" y_offset="$y" topmost="$topmost" height="$height"

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
