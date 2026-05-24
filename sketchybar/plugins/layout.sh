#!/usr/bin/env bash
# layout.sh — single source of truth for the bar's geometry AND the pill
# layout. Runs on display_change / position_change (and once at boot).
#
# Probes the active display's geometry ONCE (space_labels_probe, from
# theme.sh), then:
#   1. moves/resizes the bar onto the active display for the current mode
#      (center | notch-left | notch-right | left | right);
#   2. re-anchors the space pills (group + notch boundary padding + order);
# all folded into a transparent → move → reposition → fade-in sequence so the
# reflow is hidden.
#
# Replaces the older split plugins/y_offset.sh + plugins/position.sh: one
# probe per event instead of two, and one shared mode decision.

. "$HOME/.config/sketchybar/theme.sh"

POS_FILE="$HOME/.config/sketchybar/position"
MODE="$(cat "$POS_FILE" 2>/dev/null || echo center)"
case "$MODE" in center|notch-left|notch-right|left|right) ;; *) MODE=center ;; esac

# ─── probe the active display ONCE ───────────────────────────────────────
# <index>:<kind>:<menu_h>:<screen_w>:<notch_left>:<notch_right>
IFS=: read -r active_index kind menu_h screen_w notch_left notch_right <<<"$(space_labels_probe)"
: "${kind:=FLAT}" "${menu_h:=24}" "${screen_w:=0}" "${notch_left:=0}" "${notch_right:=0}"
[ -z "$active_index" ] && exit 0

# notch-* on a flat display has nothing to anchor against — collapse to center
# (one decision, shared by both the bar geometry and the pill layout below).
case "$kind:$MODE" in
  FLAT:notch-left|FLAT:notch-right) MODE=center ;;
esac

# ─── 1. bar geometry (was y_offset.sh) ───────────────────────────────────
margin=0
x_off=0

case "$MODE" in
  left|right)
    # Below the OS menu bar with a 2pt gap.
    y=1; topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
    ;;
  notch-left|notch-right)
    # Pills in the menu bar row beside the notch. topmost=on keeps them
    # clickable; margin shrinks the bar to a strip CENTERED on the notch so it
    # doesn't eat clicks across the whole menu bar. (No x_offset: it moves the
    # frame but not the items.) See theme.sh / NOTCH_PILL_ROOM.
    y=$(( (menu_h - PILL_HEIGHT) / 2 )); [ "$y" -lt 1 ] && y=1
    topmost=on; height="$PILL_HEIGHT"
    margin=$(( notch_left - NOTCH_PILL_ROOM )); [ "$margin" -lt 0 ] && margin=0
    ;;
  *)
    case "$kind" in
      NOTCH)
        # Centered on a notched display: grow height by 2*NOTCH_GAP so pills
        # drop NOTCH_GAP below the safe-area edge. topmost=off → click-through.
        y=1; topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
        ;;
      *)
        # Flat: bar tracks the OS menu bar thickness.
        y="$Y_OFFSET_FLAT"; topmost=on; height="$menu_h"
        ;;
    esac
    ;;
esac

# ─── 2. pill layout (was position.sh) ────────────────────────────────────
# Strip margin M (left edge = M, right edge = screen_w - M) is where the
# notch-side boundary padding is measured from. BAR_PAD from theme.sh.
M=$(( notch_left - NOTCH_PILL_ROOM )); [ "$M" -lt 0 ] && M=0

group=center
boundary_padding_side=
boundary_padding=0
case "$MODE" in
  center) group=center ;;
  left)   group=left   ;;
  right)  group=right  ;;
  notch-right)
    group=left;  boundary_padding_side=left
    boundary_padding=$(( notch_right - M + NOTCH_SIDE_GAP - BAR_PAD ))
    ;;
  notch-left)
    group=right; boundary_padding_side=right
    boundary_padding=$(( (screen_w - M) - notch_left + NOTCH_SIDE_GAP - BAR_PAD ))
    ;;
esac
[ "$boundary_padding" -lt 0 ] && boundary_padding=0

# Space items, numerically sorted ascending.
SPACE_ITEMS=$(sketchybar --query bar 2>/dev/null \
              | "$JQ" -r '.items[]?' 2>/dev/null \
              | /usr/bin/sed -n 's/^space\.//p' \
              | /usr/bin/sort -n \
              | /usr/bin/sed 's/^/space./')
[ -z "$SPACE_ITEMS" ] && exit 0

# Right groups pack from the right edge (reversing visual order) → reverse the
# list so pills always read ascending left→right. The first item of `order`
# sits at the group's anchored (notch-side) edge, so it carries the padding.
if [ "$group" = right ]; then
  order=$(printf '%s\n' "$SPACE_ITEMS" \
          | /usr/bin/sed -n 's/^space\.//p' | /usr/bin/sort -rn | /usr/bin/sed 's/^/space./')
else
  order="$SPACE_ITEMS"
fi
anchor=$(printf '%s\n' "$order" | /usr/bin/sed -n '1p')

# ─── 3. apply, hiding the reflow under a fade ────────────────────────────
SPACES_JSON=$("$YABAI" -m query --spaces 2>/dev/null)

# Phase 1: snap pills transparent BEFORE anything moves (no flash on the new
# display / during repositioning).
for item in $order; do
  sketchybar --set "$item" \
    icon.color="$COLOR_PILL_FG_HIDDEN" \
    label.color="$COLOR_PILL_FG_HIDDEN" \
    background.color="$COLOR_PILL_BG_HIDDEN" >/dev/null
done

# Phase 2: move/resize the bar onto the active display.
sketchybar --bar display="$active_index" y_offset="$y" topmost="$topmost" \
  height="$height" margin="$margin" x_offset="$x_off"

# Phase 2b: re-anchor the pills (group, boundary padding, order) while hidden.
for item in $order; do
  pl="$PILL_PAD"; pr="$PILL_PAD"
  if [ "$item" = "$anchor" ]; then
    case "$boundary_padding_side" in
      left)  pl="$boundary_padding" ;;
      right) pr="$boundary_padding" ;;
    esac
  fi
  sketchybar --set "$item" position="$group" padding_left="$pl" padding_right="$pr" >/dev/null
done
# shellcheck disable=SC2086
sketchybar --reorder $order >/dev/null 2>&1

# Phase 3: let the transparent, repositioned frame paint.
sleep 0.05

# Phase 4: animate pills back to their real focused/unfocused colors.
for item in $order; do
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
