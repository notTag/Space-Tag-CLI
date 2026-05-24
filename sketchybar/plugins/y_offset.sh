#!/usr/bin/env bash
# Pin sketchybar to the active display, set the correct y_offset for it,
# and fade the space pills in on the new display.
#
# yabai's has-notch field is unreliable across versions, so we ask AppKit
# directly via a tiny swift one-liner: any screen whose safeAreaInsets.top
# > 0 is notched. We match the active yabai display by width+height.

. "$HOME/.config/sketchybar/theme.sh"

POS_FILE="$HOME/.config/sketchybar/position"
POS_MODE="$(cat "$POS_FILE" 2>/dev/null || echo center)"
case "$POS_MODE" in center|notch-left|notch-right|left|right) ;; *) POS_MODE=center ;; esac

active=$("$YABAI" -m query --displays --display 2>/dev/null)
active_index=$(printf '%s' "$active" | "$JQ" -r '.index' 2>/dev/null)
active_dims=$(printf '%s' "$active"  | "$JQ" -r '"\(.frame.w|floor)x\(.frame.h|floor)"' 2>/dev/null)

[ -z "$active_index" ] && exit 0

# Ask AppKit for live, per-display values:
#   • safeAreaInsets.top — non-zero on notched MBPs (~37–38pt) and ALSO the
#     active display's actual menu bar height (notch row). Branch NOTCH/FLAT
#     on the sign, then reuse the magnitude as menu_h on notched displays.
#   • NSStatusBar.system.thickness — system-wide menu bar thickness; only
#     correct for flat displays (it reads from the primary screen).
# Per-display matters because NSStatusBar.thickness reports SYSTEM thickness
# (taken from primary). On a mixed setup (flat primary + notched secondary)
# the secondary's real menu bar height differs from system thickness.
# Notch bounds (notch_left / notch_right) come from the same probe so the
# notch-* layouts can shrink the bar to a thin strip beside the notch.
# Output format: <kind>:<menu_h>:<screen_w>:<notch_left>:<notch_right>
#   notch_left  = x of the notch's left edge  (width of the left aux area)
#   notch_right = x of the notch's right edge  (screen_w - right aux width)
# FLAT displays report 0:0 for the notch bounds.
active_state=$(TARGET="$active_dims" /usr/bin/swift -e '
import AppKit
let target = ProcessInfo.processInfo.environment["TARGET"] ?? ""
let thickness = Int(NSStatusBar.system.thickness)
for s in NSScreen.screens {
  let w = Int(s.frame.size.width)
  let dims = "\(w)x\(Int(s.frame.size.height))"
  if dims == target {
    let safeTop = Int(s.safeAreaInsets.top)
    if safeTop > 0 {
      let l = Int((s.auxiliaryTopLeftArea  ?? .zero).size.width)
      let r = Int(CGFloat(w) - (s.auxiliaryTopRightArea ?? .zero).size.width)
      print("NOTCH:\(safeTop):\(w):\(l):\(r)")
    } else {
      print("FLAT:\(thickness):\(w):0:0")
    }
    exit(0)
  }
}
print("FLAT:\(thickness):0:0:0")
' 2>/dev/null)

# Split "<kind>:<menu_h>:<screen_w>:<notch_left>:<notch_right>"
IFS=: read -r kind menu_h screen_w notch_left notch_right <<<"$active_state"
: "${kind:=FLAT}" "${menu_h:=24}" "${screen_w:=0}" "${notch_left:=0}" "${notch_right:=0}"

# notch-* on a flat display has nothing to anchor against — collapse to
# `center` so bar geometry matches what position.sh will do for items.
mode="$POS_MODE"
case "$kind:$mode" in
  FLAT:notch-left|FLAT:notch-right) mode=center ;;
esac

# Bar-shrink params for the notch-* layouts; every other mode leaves them at
# 0 so switching away from a notch layout restores the full-width bar.
margin=0
x_off=0

case "$mode" in
  left|right)
    # Bar sits below the OS menu bar with a 2pt visual gap. menu_h is the
    # active display's actual menu bar height (notch row on notched, status
    # bar thickness on flat), so this lands correctly on mixed setups.
    y=$(( menu_h + 2 ))
    topmost=on
    height="$PILL_HEIGHT"
    ;;
  notch-left|notch-right)
    # Pills sit in the OS menu bar row beside the notch, vertically centered:
    # the notch row spans 0..menu_h, so a PILL_HEIGHT pill centers at
    # (menu_h - PILL_HEIGHT)/2 — adapts to Larger Text and to MBP models with
    # differing safe-area heights.
    #
    # topmost=on keeps pills CLICKABLE (above the menu bar). The catch: a
    # *full-width* topmost bar eats clicks across the ENTIRE menu bar strip,
    # killing Apple/File AND clock/wifi/battery. Fix: shrink the bar with
    # `margin` to a strip CENTERED on the notch — topmost then only blocks that
    # strip and the native clusters on both far sides stay live.
    #
    # NOT x_offset: it shifts the bar's frame but leaves items laid out in the
    # centered margin window, so an off-center frame and its pills diverge
    # (pills end up under the notch). The notch is itself screen-centered, so a
    # margin-only strip is naturally centered on it; position.sh then pushes the
    # pills flush to either side of the notch via item padding, all inside the
    # clickable strip. margin = notch_left - NOTCH_PILL_ROOM reserves
    # NOTCH_PILL_ROOM points for pills on each side of the notch.
    y=$(( (menu_h - PILL_HEIGHT) / 2 ))
    [ "$y" -lt 1 ] && y=1
    topmost=on
    height="$PILL_HEIGHT"
    margin=$(( notch_left - NOTCH_PILL_ROOM ))
    [ "$margin" -lt 0 ] && margin=0
    ;;
  *)
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

# Phase 2: move the bar to the active display with the correct offset.
# margin + x_offset shrink/park the bar beside the notch in notch-* modes
# (both 0 otherwise → full-width bar).
sketchybar --bar display="$active_index" y_offset="$y" topmost="$topmost" \
  height="$height" margin="$margin" x_offset="$x_off"

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
