#!/usr/bin/env bash
# spaces.sh — reconcile the space pills with the live yabai spaces.
#
# macOS spaces can be added, removed, and reordered at runtime. Pills are keyed
# by yabai's (always-contiguous) space index, so the SET of pills must track the
# SET of spaces or pills go missing/stale. This adds a pill for every space that
# lacks one, removes pills whose space is gone, then re-renders labels and
# re-flows the bar. Idempotent: run once at boot and on every yabai
# space_created / space_destroyed (via the space_set_change event).
#
# Pills are created with updates=on, NOT the bar's when_shown default: a hidden
# (drawing=off) when_shown item never runs its script again, so it could never
# un-hide itself — a deadlock that strands pills when spaces are renumbered.

. "$HOME/.config/sketchybar/theme.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

# Desired indices (live spaces) and current pill indices, as SPACE-separated
# lists so the `case " $list " in *" $i "*` membership tests below work (a
# newline-separated list would never match a space-padded needle).
WANT=$("$YABAI" -m query --spaces 2>/dev/null | "$JQ" -r '.[].index' 2>/dev/null \
       | /usr/bin/sort -n | /usr/bin/tr '\n' ' ')
[ -z "${WANT// }" ] && exit 0
HAVE=$(sketchybar --query bar 2>/dev/null \
       | "$JQ" -r '.items[]? | select(startswith("space."))' 2>/dev/null \
       | /usr/bin/sed 's/^space\.//' | /usr/bin/sort -n | /usr/bin/tr '\n' ' ')

# Reconcile the pill set with the live spaces. `changed` tracks whether the set
# actually moved, so the periodic poll (spaces_watcher update_freq — the fallback
# for missed yabai space_created/destroyed signals) is a cheap no-op in steady
# state: only a real add/remove triggers the re-render + reflow below.
changed=0

# Add a pill for every space that doesn't have one.
for i in $WANT; do
  case " $HAVE " in
    *" $i "*) ;;
    *)
      changed=1
      sketchybar --add item space."$i" center \
                 --set space."$i" \
                     updates=on \
                     icon="$i" \
                     icon.padding_left=10 \
                     background.color="$COLOR_PILL_BG" \
                     background.corner_radius="$PILL_CORNER_RADIUS" \
                     background.height="$PILL_HEIGHT" \
                     click_script="$YABAI -m space --focus $i" \
                     script="$PLUGIN_DIR/space.sh" \
                 --subscribe space."$i" space_change >/dev/null
      ;;
  esac
done

# Remove pills whose space no longer exists.
for i in $HAVE; do
  case " $WANT " in
    *" $i "*) ;;
    *) changed=1; sketchybar --remove space."$i" >/dev/null 2>&1 ;;
  esac
done

# Only when the set actually changed: re-render every pill's label/focus, let
# them settle, then re-flow the bar. (Steady-state poll ticks fall through.)
if [ "$changed" -eq 1 ]; then
  sketchybar --trigger space_change >/dev/null 2>&1
  sleep 0.1
  "$PLUGIN_DIR/layout.sh"
fi
