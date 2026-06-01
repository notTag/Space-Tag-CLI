#!/usr/bin/env bash
# flash-reconcile.sh — agent-hooks
#
# Clears a "pending flash" hold once the user actually lands on the window/app
# that triggered it. flash-listener.sh paints a held tool color on a space when
# an agent finishes a turn while the user is NOT on that window (a different app
# on the same space, or a different space). That hold is meant to persist until
# the triggering window gains focus — which is NOT necessarily a space change
# (switching apps within one space fires no space_change). So this watcher
# subscribes to BOTH front_app_switched and space_change, and on each event:
#   1. reads the user's currently-focused window id,
#   2. for every pending marker ("<tool> <win>"), if <win> is now focused,
#      removes the marker,
#   3. if anything was cleared, fires space_change so space.sh repaints those
#      pills back to their steady focused/unfocused color.
#
# Markers with no <win> (fallback resolver couldn't pin a window) degrade to
# space-level clearing: cleared when their space is the focused one.
#
# Wired by sketchybarrc:
#   sketchybar --add item flash_reconciler right \
#     --set flash_reconciler drawing=off updates=on script=<this> \
#     --subscribe flash_reconciler front_app_switched space_change

set -u

SKETCHYBAR="${SKETCHYBAR:-$(command -v sketchybar || echo /opt/homebrew/bin/sketchybar)}"
YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
JQ="${JQ:-$(command -v jq || echo /opt/homebrew/bin/jq)}"

log() {
  printf '%s flash_reconcile %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$*" \
    >> "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
}

PENDING_DIR="$HOME/Library/Application Support/spacetag/pending-flash"
[ -d "$PENDING_DIR" ] || exit 0

FOCUSED_WIN="$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty')"
FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null | "$JQ" -r '.index // empty')"

# Snapshot of every live window id. Used to clear a held flash whose triggering
# window has CLOSED — a closed window can never gain focus, so the focus-based
# clear below would otherwise leave the pill stuck on the tool color forever.
# front_app_switched fires when the triggering app quits (focus moves away), so
# this watcher runs and reaps the orphaned marker. One space-separated line of
# ids; matched with word-boundary globbing (no jq per-marker).
LIVE_WINS=" $("$YABAI" -m query --windows 2>/dev/null | "$JQ" -r '.[].id' | tr '\n' ' ')"

changed=0

# Direct destroy path: when fired by the yabai window_destroyed signal,
# sketchybarrc/yabairc forward the dead window id as WIN. Reap any marker pinned
# to it immediately and trust the explicit id over the LIVE_WINS scan below — a
# just-destroyed window can still appear in `yabai -m query --windows` for a beat
# (destroy/query race), which would let the held color survive one more event.
if [ "${SENDER:-}" = "window_destroyed" ] && [ -n "${WIN:-}" ]; then
  for f in "$PENDING_DIR"/*; do
    [ -e "$f" ] || continue
    IFS=' ' read -r _t w < "$f" 2>/dev/null
    if [ -n "${w:-}" ] && [ "$w" = "$WIN" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared ${f##*/} (win=$WIN destroyed)"
    fi
  done
fi

# Backstop scan: clears markers whose window is focused, or whose window no
# longer exists (app quit, or a destroy event we missed / fired before this
# watcher was wired). Runs on every subscribed event.
for f in "$PENDING_DIR"/*; do
  [ -e "$f" ] || continue                 # no markers (glob didn't expand)
  sid="${f##*/}"
  # NOTE: do NOT `|| continue` here — markers may lack a trailing newline, which
  # makes `read` return non-zero at EOF even though it assigned the vars. Guard
  # on emptiness instead.
  IFS=' ' read -r _tool win < "$f" 2>/dev/null
  [ -n "${_tool:-}" ] || continue

  if [ -n "${win:-}" ]; then
    # Window-level: clear once the triggering window is the focused one...
    if [ -n "$FOCUSED_WIN" ] && [ "$win" = "$FOCUSED_WIN" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (win=$win focused)"
    # ...or once it no longer exists (app/window closed). Only trust the snapshot
    # when the query actually returned ids — an empty LIVE_WINS means yabai was
    # unreachable, not "all windows gone", so we must not reap on it.
    elif [ "$LIVE_WINS" != " " ] && [ "${LIVE_WINS#* $win }" = "$LIVE_WINS" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (win=$win closed)"
    fi
  else
    # No window id → space-level fallback: clear when its space is focused.
    if [ -n "$FOCUSED_SID" ] && [ "$sid" = "$FOCUSED_SID" ]; then
      rm -f "$f" 2>/dev/null && changed=1
      log "cleared $sid (space focused, no win)"
    fi
  fi
done

# Repaint only when something actually cleared — otherwise this is a cheap
# no-op (front_app_switched fires on every app switch). The re-triggered
# space_change runs space.sh, which now sees no marker and paints the steady
# focused/unfocused color.
if [ "$changed" = "1" ]; then
  "$SKETCHYBAR" --trigger space_change >/dev/null 2>&1 || true
fi

exit 0
