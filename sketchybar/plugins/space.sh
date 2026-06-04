#!/usr/bin/env bash
# Render a space pill. NAME is set by sketchybar to "space.<sid>".
# Reads the yabai-stored label for that space and highlights if focused.

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

# Two visual modes:
#   • No label → show the space number centered (icon on, label off).
#   • Has label → show the label only (icon off), centered.
if [ -z "$LABEL" ]; then
  # Bare number: dynamic width + symmetric icon padding. The digit is centered in
  # its advance box and the item padding (set in layout.sh) makes the real
  # inter-pill gaps. NOTE: a fixed `width` can NOT be used for uniform pills —
  # sketchybar packs fixed-width items edge-to-edge and shoves padding INTO the
  # neighbour, so pills overlap. Dynamic width is the only spaced option.
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

# Pending completion-flash hold: a space an agent finished on keeps its tool
# flash color (set by flash-listener.sh) SOLID — even while this space is
# focused — for as long as the user is in a different app than the one that
# triggered it. The marker is "<tool> <win>"; flash-reconcile.sh removes it once
# window <win> gains focus, then re-triggers space_change so we repaint steady.
PENDING_FILE="$(agent_hooks_pending_dir)/$SID"
if [ -f "$PENDING_FILE" ]; then
  read -r PEND_TOOL _ < "$PENDING_FILE"
  case "$PEND_TOOL" in
    codex)  BG="$COLOR_FLASH_CODEX"  ;;
    hermes) BG="$COLOR_FLASH_HERMES" ;;
    *)      BG="$COLOR_FLASH_CLAUDE" ;;
  esac
fi

# space_change fires for EVERY pill on every focus switch, but a pill's geometry
# (icon-vs-label mode, paddings, dynamic width) only changes when its LABEL
# changes (rename/clear) or on first render — never when focus alone moves.
# Re-setting width=dynamic + paddings on every focus switch re-packs the whole
# row, which reads as a jiggle. So only touch geometry when it actually differs
# from what's drawn; the color fade below still runs every time.
CUR=$(sketchybar --query "$NAME" 2>/dev/null)
cur_label=$(printf '%s' "$CUR" | "$JQ" -r '.label.value // ""')
cur_label_draw=$(printf '%s' "$CUR" | "$JQ" -r '.label.drawing // "on"')
cur_icon_draw=$(printf '%s' "$CUR" | "$JQ" -r '.icon.drawing // "on"')

if [ "$LABEL" != "$cur_label" ] \
   || [ "$LABEL_DRAW" != "$cur_label_draw" ] \
   || [ "$ICON_DRAW" != "$cur_icon_draw" ]; then
  # Geometry snaps instantly (no animation). width=dynamic is the only spaced
  # option (see note above); explicit so any previously-set fixed width clears.
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

# Always tween the focus colors so a focus change fades rather than hard-swaps.
sketchybar --animate "$ANIM_CURVE" "$ANIM_FRAMES_FOCUS" --set "$NAME" \
  icon.color="$FG" \
  label.color="$FG" \
  background.color="$BG" >/dev/null
