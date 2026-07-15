#!/usr/bin/env bash

. "$HOME/.config/sketchybar/theme.sh"
STATE_SH="$HOME/.config/sketchybar/plugins/agent-hooks/state.sh"
if [ -f "$STATE_SH" ]; then
  . "$STATE_SH"
else
  agent_hooks_pending_dir() {
    printf '%s\n' "$HOME/Library/Application Support/spacetag/pending-flash"
  }
fi

SID="${NAME#space.}"
INFO=$("$YABAI" -m query --spaces --space "$SID" 2>/dev/null)

if [ -z "$INFO" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

LABEL=$(printf '%s' "$INFO" | "$JQ" -r '.label // ""')
FOCUSED=$(printf '%s' "$INFO" | "$JQ" -r '."has-focus" // false')

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

PENDING_FILE="$(agent_hooks_pending_dir)/$SID"
if [ -f "$PENDING_FILE" ]; then
  read -r PEND_TOOL _ < "$PENDING_FILE"
  case "$PEND_TOOL" in
    codex)  BG="$COLOR_FLASH_CODEX"  ;;
    hermes) BG="$COLOR_FLASH_HERMES" ;;
    *)      BG="$COLOR_FLASH_CLAUDE" ;;
  esac
fi

CUR=$(sketchybar --query "$NAME" 2>/dev/null)
cur_label=$(printf '%s' "$CUR" | "$JQ" -r '.label.value // ""')
cur_label_draw=$(printf '%s' "$CUR" | "$JQ" -r '.label.drawing // "on"')
cur_icon_draw=$(printf '%s' "$CUR" | "$JQ" -r '.icon.drawing // "on"')

if [ "$LABEL" != "$cur_label" ] \
   || [ "$LABEL_DRAW" != "$cur_label_draw" ] \
   || [ "$ICON_DRAW" != "$cur_icon_draw" ]; then
  # Fixed-width SketchyBar items absorb padding and overlap adjacent pills.
  sketchybar --set "$NAME" \
    icon="$SID" \
    icon.drawing="$ICON_DRAW" \
    icon.padding_left="$ICON_PL" \
    icon.padding_right="$ICON_PR" \
    icon.y_offset="$ICON_Y_OFFSET" \
    width=dynamic \
    label="$LABEL" \
    label.drawing="$LABEL_DRAW" \
    label.padding_left="$LABEL_PL" \
    label.padding_right="$LABEL_PR" \
    label.y_offset="$LABEL_Y_OFFSET" \
    drawing=on >/dev/null
fi

sketchybar --animate "$ANIM_CURVE" "$ANIM_FRAMES_FOCUS" --set "$NAME" \
  icon.color="$FG" \
  label.color="$FG" \
  background.color="$BG" >/dev/null
