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

# notch-* on a flat display has no notch to anchor a centered strip against.
# A true in-menu-bar left/right-aligned strip isn't possible (margin is
# symmetric, so the bar frame can only center — the same constraint that forces
# the notch strip to center on the notch). So fall back to the left/right modes,
# which drop the pills below the menu bar at the requested edge. One decision,
# shared by both the bar geometry and the pill layout below.
case "$kind:$MODE" in
  FLAT:notch-left)  MODE=left  ;;
  FLAT:notch-right) MODE=right ;;
esac

# ─── measure the live pill row (sum of space-item widths) ─────────────────
# Flat center mode sizes its clickable strip to the actual pills (see below),
# so we need the row's pixel width. Each item's bounding_rect width already
# includes its paddings, so summing them gives the full row width — gaps and
# all. Read live → adapts as spaces/labels change. 0 until the pills have been
# drawn (boot's first pass); the flat-center branch falls back to full width
# in that case and self-corrects on the next display/position event.
row_w=0
for it in $(sketchybar --query bar 2>/dev/null \
            | "$JQ" -r '.items[]? | select(startswith("space."))' 2>/dev/null); do
  iw=$(sketchybar --query "$it" 2>/dev/null \
       | "$JQ" -r 'first(.bounding_rects[]?.size[0]) // 0' 2>/dev/null)
  iw=${iw%.*}; row_w=$(( row_w + ${iw:-0} ))
done

# ─── 1. bar geometry (was y_offset.sh) ───────────────────────────────────
margin=0
x_off=0
pill_h="$PILL_HEIGHT"   # per-pill background height; capped to fit in flat center
calibrate_below=0       # flat left/right: measure sketchybar's topmost=off base in Phase 2

# Notch strip room: reserve space for the pills DYNAMICALLY (measured row width
# + clearance for the notch gap and the bar's own edge paddings), so the strip
# always fits the whole row and never strands a pill when labels are long. A
# fixed reserve (NOTCH_PILL_ROOM) can't track label length — it's only the
# fallback for boot, before any pill has been drawn/measured.
if [ "$row_w" -gt 0 ]; then
  notch_room=$(( row_w + NOTCH_SIDE_GAP + 2 * BAR_PAD ))
else
  notch_room="$NOTCH_PILL_ROOM"
fi

case "$MODE" in
  left|right)
    # Below the OS menu bar (topmost=off → native bar stays on top / clickable).
    # Sketchybar positions a topmost=off bar against ITS OWN menu-bar estimate
    # (NSStatusBar.thickness), which under-reports the real bar on some displays
    # — so a small y leaves pills hidden under the real menu bar (looks flush).
    # On notched displays macOS honors the safe area, so y=1 already clears it;
    # on flat displays we calibrate sketchybar's base live (Phase 2) and offset
    # to clear the REAL menu bar by BELOW_BAR_GAP.
    topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
    case "$kind" in
      NOTCH) y=1 ;;                              # safe area already clears the bar
      *)     y="$BELOW_BAR_GAP"; calibrate_below=1 ;;   # refined in Phase 2
    esac
    ;;
  notch-left|notch-right)
    # Pills in the menu bar row beside the notch. topmost=on keeps them
    # clickable; margin shrinks the bar to a strip CENTERED on the notch so it
    # doesn't eat clicks across the whole menu bar. (No x_offset: it moves the
    # frame but not the items.) Strip half-width = notch_room (dynamic).
    y=$(( (menu_h - PILL_HEIGHT) / 2 )); [ "$y" -lt 1 ] && y=1
    topmost=on; height="$PILL_HEIGHT"
    margin=$(( notch_left - notch_room )); [ "$margin" -lt 0 ] && margin=0
    ;;
  *)
    case "$kind" in
      NOTCH)
        # Centered on a notched display: grow height by 2*NOTCH_GAP so pills
        # drop NOTCH_GAP below the safe-area edge. topmost=off → click-through.
        y=1; topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
        ;;
      *)
        # Flat: pills sit IN the menu bar row, so topmost=on is required to
        # paint above it — but with topmost=on y is SCREEN-ABSOLUTE (y=0 = the
        # very top), and a full-width topmost bar eats clicks across the whole
        # menu bar (native status items included). Two fixes:
        #   • width — shrink to a strip CENTERED on screen, sized to the live
        #     pill row (row_w + 2*BAR_PAD), so only the pills' span is blocked
        #     and both far sides stay clickable.
        #   • height — center the pill in the REAL menu bar (menu_h from the
        #     probe, not NSStatusBar.thickness which under-reports it). If
        #     PILL_HEIGHT would exceed the bar it can't be centered (its top
        #     clamps to y=0, flush with the screen top), so cap it to fit with
        #     a small inset (FLAT_PILL_INSET); otherwise it stays PILL_HEIGHT.
        #     Y_OFFSET_FLAT nudges the centered result.
        pill_h=$(( menu_h - 2 * FLAT_PILL_INSET ))
        [ "$pill_h" -gt "$PILL_HEIGHT" ] && pill_h="$PILL_HEIGHT"
        [ "$pill_h" -lt 1 ] && pill_h="$PILL_HEIGHT"
        y=$(( (menu_h - pill_h) / 2 + Y_OFFSET_FLAT )); [ "$y" -lt 0 ] && y=0
        topmost=on; height="$pill_h"
        if [ "$row_w" -gt 0 ] && [ "$screen_w" -gt 0 ]; then
          margin=$(( screen_w / 2 - (row_w / 2 + BAR_PAD) ))
          [ "$margin" -lt 0 ] && margin=0
        fi
        ;;
    esac
    ;;
esac

# ─── 2. pill layout (was position.sh) ────────────────────────────────────
# Strip margin M (left edge = M, right edge = screen_w - M) is where the
# notch-side boundary padding is measured from. Must match the bar margin set
# above for notch modes — both use the dynamic notch_room. BAR_PAD from theme.sh.
M=$(( notch_left - notch_room )); [ "$M" -lt 0 ] && M=0

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
# Flat left/right calibration: sketchybar places a topmost=off bar against its
# own (under-reported) menu-bar height, so park at y_offset=0, read where a pill
# actually lands (C = sketchybar's base, in screen px), then offset to put the
# pill BELOW the real menu bar (menu_h) by BELOW_BAR_GAP. Pills are transparent
# here (Phase 1), so the intermediate move is invisible.
if [ "$calibrate_below" = 1 ]; then
  sketchybar --bar display="$active_index" y_offset=0 topmost="$topmost" \
    height="$height" margin="$margin" x_offset="$x_off" >/dev/null
  sleep 0.05
  C=$(sketchybar --query "$anchor" 2>/dev/null \
      | "$JQ" -r 'first(.bounding_rects[]?.origin[1]) // 0' 2>/dev/null)
  C=${C%.*}
  yc=$(( menu_h + BELOW_BAR_GAP - ${C:-0} ))
  [ "$yc" -ge 0 ] && y="$yc"
fi
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
  sketchybar --set "$item" position="$group" padding_left="$pl" padding_right="$pr" \
    background.height="$pill_h" >/dev/null
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
