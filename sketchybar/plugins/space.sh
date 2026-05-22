#!/usr/bin/env bash
# Render a space pill. NAME is set by sketchybar to "space.<sid>".
# Reads the yabai-stored label for that space and highlights if focused.

. "$HOME/.config/sketchybar/theme.sh"

SID="${NAME#space.}"
INFO=$("$YABAI" -m query --spaces --space "$SID" 2>/dev/null)

if [ -z "$INFO" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

LABEL=$(printf '%s' "$INFO" | "$JQ" -r '.label // ""')
FOCUSED=$(printf '%s' "$INFO" | "$JQ" -r '."has-focus" // false')

# Two visual modes:
#   • No label → show the space number centered (icon on, label off).
#   • Has label → show the label only (icon off), centered.
if [ -z "$LABEL" ]; then
  ICON_DRAW=on  ICON_PL=10 ICON_PR=10
  LABEL_DRAW=off LABEL_PL=0  LABEL_PR=0
else
  ICON_DRAW=off ICON_PL=0  ICON_PR=0
  LABEL_DRAW=on  LABEL_PL=10 LABEL_PR=10
fi

if [ "$FOCUSED" = "true" ]; then
  BG="$COLOR_PILL_BG_FOCUSED"
  FG="$COLOR_PILL_FG_FOCUSED"
else
  BG="$COLOR_PILL_BG"
  FG="$COLOR_PILL_FG"
fi

# Tween color transitions so focus changes feel like a fade rather than
# a hard swap. Geometry props (drawing/padding/label text) snap instantly;
# only colors animate.
sketchybar --set "$NAME" \
  icon="$SID" \
  icon.drawing="$ICON_DRAW" \
  icon.padding_left="$ICON_PL" \
  icon.padding_right="$ICON_PR" \
  label="$LABEL" \
  label.drawing="$LABEL_DRAW" \
  label.padding_left="$LABEL_PL" \
  label.padding_right="$LABEL_PR" \
  drawing=on \
  --animate "$ANIM_CURVE" "$ANIM_FRAMES_FOCUS" --set "$NAME" \
    icon.color="$FG" \
    label.color="$FG" \
    background.color="$BG"
