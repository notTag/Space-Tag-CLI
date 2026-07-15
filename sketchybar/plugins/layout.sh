#!/usr/bin/env bash

. "$HOME/.config/sketchybar/theme.sh"

IFS=: read -r active_index kind menu_h screen_w notch_left notch_right clip_h active_uuid <<<"$(space_tag_probe)"
: "${kind:=FLAT}" "${menu_h:=24}" "${screen_w:=0}" "${notch_left:=0}" "${notch_right:=0}" "${clip_h:=22}"
if [ -z "$active_index" ] || [ "$screen_w" -le 0 ]; then
  # topmost=on makes the transparent bar swallow clicks; if we can't place it, demote it.
  sketchybar --bar topmost=off >/dev/null 2>&1
  exit 0
fi

POS_FILE="$HOME/.config/sketchybar/position"
POS_DIR="$HOME/.config/sketchybar/position.d"
if [ -n "$active_uuid" ] && [ -f "$POS_DIR/$active_uuid" ]; then
  MODE="$(cat "$POS_DIR/$active_uuid" 2>/dev/null)"
else
  MODE="$(cat "$POS_FILE" 2>/dev/null || echo center)"
fi
case "$MODE" in center|notch-left|notch-right|left|right) ;; *) MODE=center ;; esac

case "$kind:$MODE" in
  FLAT:notch-left)  MODE=left  ;;
  FLAT:notch-right) MODE=right ;;
esac

row_w=0
# SketchyBar applies item geometry asynchronously, so wait for every pill width.
# Using --update here would recursively invoke this script.
for _ in $(seq 1 10); do
  row_w=0; missing=0
  for it in $(sketchybar --query bar 2>/dev/null \
              | "$JQ" -r '.items[]? | select(startswith("space."))' 2>/dev/null); do
    iw=$(sketchybar --query "$it" 2>/dev/null \
         | "$JQ" -r 'first(.bounding_rects[]?.size[0]) // 0' 2>/dev/null)
    iw=${iw%.*}; iw=${iw:-0}
    [ "$iw" -le 0 ] && missing=1
    row_w=$(( row_w + iw + 2 * PILL_PAD ))
  done
  [ "$missing" -eq 0 ] && break
  sleep 0.02
done

margin=0
x_off=0
pill_h="$PILL_HEIGHT"
calibrate_below=0

if [ "$row_w" -gt 0 ]; then
  notch_room=$(( row_w + NOTCH_SIDE_GAP + 2 * BAR_PAD ))
else
  notch_room="$NOTCH_PILL_ROOM"
fi

case "$MODE" in
  left|right)
    topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
    case "$kind" in
      NOTCH) y=1 ;;
      *)     y="$BELOW_BAR_GAP"; calibrate_below=1 ;;
    esac
    ;;
  notch-left|notch-right)
    y=$(( (menu_h - PILL_HEIGHT) / 2 )); [ "$y" -lt 1 ] && y=1
    # Limit the topmost bar to the notch strip so native menu items stay clickable.
    topmost=on; height="$PILL_HEIGHT"
    margin=$(( notch_left - notch_room )); [ "$margin" -lt 0 ] && margin=0
    ;;
  *)
    case "$kind" in
      NOTCH)
        y=1; topmost=off; height=$(( PILL_HEIGHT + 2 * NOTCH_GAP ))
        ;;
      *)
        # macOS clips topmost menu-bar windows to NSStatusBar thickness.
        band="$clip_h"; [ "$band" -lt 1 ] && band="$menu_h"
        pill_h=$(( band - 2 * FLAT_PILL_INSET ))
        [ "$pill_h" -gt "$PILL_HEIGHT" ] && pill_h="$PILL_HEIGHT"
        [ "$pill_h" -lt 1 ] && pill_h="$band"
        y=$(( (band - pill_h) / 2 + Y_OFFSET_FLAT )); [ "$y" -lt 0 ] && y=0
        topmost=on; height="$pill_h"
        if [ "$row_w" -gt 0 ] && [ "$screen_w" -gt 0 ]; then
          margin=$(( screen_w / 2 - (row_w / 2 + BAR_PAD) ))
          [ "$margin" -lt 0 ] && margin=0
        fi
        ;;
    esac
    ;;
esac

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

SPACE_ITEMS=$(sketchybar --query bar 2>/dev/null \
              | "$JQ" -r '.items[]?' 2>/dev/null \
              | /usr/bin/sed -n 's/^space\.//p' \
              | /usr/bin/sort -n \
              | /usr/bin/sed 's/^/space./')
[ -z "$SPACE_ITEMS" ] && exit 0

if [ "$group" = right ]; then
  order=$(printf '%s\n' "$SPACE_ITEMS" \
          | /usr/bin/sed -n 's/^space\.//p' | /usr/bin/sort -rn | /usr/bin/sed 's/^/space./')
else
  order="$SPACE_ITEMS"
fi
anchor=$(printf '%s\n' "$order" | /usr/bin/sed -n '1p')

SPACES_JSON=$("$YABAI" -m query --spaces 2>/dev/null)

for item in $order; do
  sketchybar --set "$item" \
    icon.color="$COLOR_PILL_FG_HIDDEN" \
    label.color="$COLOR_PILL_FG_HIDDEN" \
    background.color="$COLOR_PILL_BG_HIDDEN" >/dev/null
done

if [ "$calibrate_below" = 1 ]; then
  # SketchyBar's menu-bar estimate can differ from the display's real geometry.
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

sleep 0.05

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
