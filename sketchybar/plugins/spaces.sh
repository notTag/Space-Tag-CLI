#!/usr/bin/env bash

# Concurrent reconciliations race on the sketchybar item set → duplicate/dropped pills.
if [ "${SPACETAG_SPACES_LOCKED:-0}" != 1 ]; then
  lock_file="${TMPDIR:-/tmp}/com.nottag.spacetag.spaces.lock"
  lockf_lock_busy=75   # lockf's exit status when -t 0 finds the lock already taken
  SPACETAG_SPACES_LOCKED=1 /usr/bin/lockf -k -s -t 0 "$lock_file" "$0" "$@"
  status=$?
  [ "$status" -eq "$lockf_lock_busy" ] && exit 0
  exit "$status"
fi

. "$HOME/.config/sketchybar/theme.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

SPACES=$("$YABAI" -m query --spaces 2>/dev/null)
[ -z "$SPACES" ] && exit 0
if [ "$(cat "$HOME/.config/sketchybar/per-display-spaces" 2>/dev/null)" != off ]; then
  for _ in 1 2 3; do
    focused_display=$("$YABAI" -m query --displays --display 2>/dev/null | "$JQ" -r '.index // empty' 2>/dev/null)
    [ -n "$focused_display" ] && break
    sleep 0.05
  done
  # Skip rather than fall through: an all-spaces reconcile would paint every
  # display's spaces onto this one.
  [ -z "$focused_display" ] && exit 0
fi

# Desired indices (live spaces) and current pill indices, as SPACE-separated
# lists so the `case " $list " in *" $i "*` membership tests below work (a
# newline-separated list would never match a space-padded needle).
if [ -n "$focused_display" ]; then
  WANT=$(printf '%s' "$SPACES" | "$JQ" -r --argjson d "$focused_display" '.[] | select(.display==$d) | .index' 2>/dev/null \
         | /usr/bin/sort -n | /usr/bin/tr '\n' ' ')
else
  WANT=$(printf '%s' "$SPACES" | "$JQ" -r '.[].index' 2>/dev/null \
         | /usr/bin/sort -n | /usr/bin/tr '\n' ' ')
fi
[ -z "${WANT// }" ] && exit 0
HAVE=$(sketchybar --query bar 2>/dev/null \
       | "$JQ" -r '.items[]? | select(startswith("space."))' 2>/dev/null \
       | /usr/bin/sed 's/^space\.//' | /usr/bin/sort -n | /usr/bin/tr '\n' ' ')

changed=0

for i in $WANT; do
  case " $HAVE " in
    *" $i "*) ;;
    *)
      changed=1
      # A hidden when_shown item cannot run its script to make itself visible.
      sketchybar --add item space."$i" center \
                 --set space."$i" \
                     updates=on \
                     icon="$i" \
                     icon.padding_left=10 \
                     background.color="$COLOR_PILL_BG" \
                     background.corner_radius="$PILL_CORNER_RADIUS" \
                     background.height="$PILL_HEIGHT" \
                     click_script="$PLUGIN_DIR/space_click.sh $i" \
                     script="$PLUGIN_DIR/space.sh" \
                 --subscribe space."$i" space_change >/dev/null
      ;;
  esac
done

for i in $HAVE; do
  case " $WANT " in
    *" $i "*) ;;
    *) changed=1; sketchybar --remove space."$i" >/dev/null 2>&1 ;;
  esac
done

if [ "$changed" -eq 1 ]; then
  sketchybar --trigger space_change >/dev/null 2>&1
  sleep 0.1
  "$PLUGIN_DIR/layout.sh"
fi
