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

# Serialize callbacks from concurrent yabai events.
if [ "${SPACETAG_SPACES_LOCKED:-0}" != 1 ]; then
  lock_file="${TMPDIR:-/tmp}/com.nottag.spacetag.spaces.lock"
  SPACETAG_SPACES_LOCKED=1 /usr/bin/lockf -k -s -t 0 "$lock_file" "$0" "$@"
  status=$?
  [ "$status" -eq 75 ] && exit 0 # EX_TEMPFAIL: another reconciliation owns the lock.
  exit "$status"
fi

. "$HOME/.config/sketchybar/theme.sh"
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"

# Per-display spaces (default ON, mirrors macOS "Displays have separate Spaces"):
# show only the focused display's spaces. Toggled by `space-tag display`,
# persisted to ~/.config/sketchybar/per-display-spaces (empty/missing = on).
# When off, every space across all displays gets a pill (the original behavior).
# Single display → the filter is a natural no-op (all spaces share display 1).
SPACES=$("$YABAI" -m query --spaces 2>/dev/null)
[ -z "$SPACES" ] && exit 0
if [ "$(cat "$HOME/.config/sketchybar/per-display-spaces" 2>/dev/null)" != off ]; then
  # A missing display must not fall through to all spaces.
  for _ in 1 2 3; do
    DID=$("$YABAI" -m query --displays --display 2>/dev/null | "$JQ" -r '.index // empty' 2>/dev/null)
    [ -n "$DID" ] && break
    sleep 0.05
  done
  [ -z "$DID" ] && exit 0
fi

# Desired indices (live spaces) and current pill indices, as SPACE-separated
# lists so the `case " $list " in *" $i "*` membership tests below work (a
# newline-separated list would never match a space-padded needle).
if [ -n "$DID" ]; then
  WANT=$(printf '%s' "$SPACES" | "$JQ" -r --argjson d "$DID" '.[] | select(.display==$d) | .index' 2>/dev/null \
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
                     click_script="$PLUGIN_DIR/space_click.sh $i" \
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

if [ "$changed" -eq 1 ]; then
  sketchybar --trigger space_change >/dev/null 2>&1
  sleep 0.1
  "$PLUGIN_DIR/layout.sh"
fi
