#!/usr/bin/env bash
# Sketchybar event handler — runs when `flash_space` is triggered.
# Receives SID + TOOL via env from `sketchybar --trigger flash_space SID=N TOOL=...`.
# Animates the matching pill's background to the tool color, holds, then reverts
# to the theme-correct steady-state color for the pill (focused vs unfocused).
#
# Wired by sketchybarrc:
#   sketchybar --add event flash_space
#   sketchybar --add item flash_watcher right \
#     --set flash_watcher drawing=off updates=on script=<this script> \
#     --subscribe flash_watcher flash_space
#
# Production port of .planning/spikes/001-e2e-claude-flash/flash-listener.sh
# with per-tool color map (claude / codex / hermes) sourced from theme.sh.

set -u

# Source theme first so $COLOR_FLASH_* and $COLOR_PILL_BG{,_FOCUSED} are in
# scope. theme.sh's tail sources theme.local.sh, so user overrides apply
# automatically (e.g. custom flash colors).
. "$HOME/.config/sketchybar/theme.sh"
STATE_SH="$HOME/.config/sketchybar/plugins/agent-hooks/state.sh"
if [ -f "$STATE_SH" ]; then
  . "$STATE_SH"
else
  agent_hooks_pending_dir() {
    printf '%s\n' "$HOME/Library/Application Support/spacetag/pending-flash"
  }
fi

SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
YABAI="${YABAI:-/opt/homebrew/bin/yabai}"

# Inlined forensic log helper — kept self-contained so this script runs cleanly
# even if state.sh is not yet deployed.
log() {
  printf '%s flash_listener %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$*" \
    >> "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
}

# Sketchybar passes the triggering event name as $SENDER and the custom kv args
# (SID, TOOL) as plain env vars.
log "fired SENDER=${SENDER:-?} SID=${SID:-?} TOOL=${TOOL:-?}"

if [ -z "${SID:-}" ]; then
  log "ERROR no SID in trigger env"
  exit 0
fi

PILL="space.$SID"

# Bail loud if the pill doesn't exist (wrong space, rename race).
PILL_QUERY="$("$SKETCHYBAR" --query "$PILL" 2>/dev/null)"
if [ -z "$PILL_QUERY" ] || [ "$PILL_QUERY" = "null" ]; then
  log "ERROR pill $PILL not found"
  exit 0
fi

# Per-tool flash color — theme.sh owns the values.
case "${TOOL:-}" in
  claude) FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;
  codex)  FLASH_COLOR="$COLOR_FLASH_CODEX"  ;;
  hermes) FLASH_COLOR="$COLOR_FLASH_HERMES" ;;
  *)      FLASH_COLOR="$COLOR_FLASH_CLAUDE" ;;  # default → orange
esac

# Steady-state colors come from theme.sh, NOT raw queried bg. Raw query returns
# the transparent default (alpha 00) for pills that never had bg explicitly
# set, which would leave the pill looking broken after the flash. space.sh
# repaints on every focus change with $COLOR_PILL_BG{_FOCUSED}, so we settle on
# those values to match its steady state. (Spike iteration 2 finding.)
# Are we ON the window that triggered this flash? The trigger forwards the
# agent's yabai window id as WIN. "On the triggering app" → the user's focused
# window IS that window → blink. Otherwise (different app on the same space, OR
# a different space entirely) → hold a solid color until that window is focused.
# When WIN is absent (fallback resolver couldn't pin a window), degrade to
# space-level focus so the flash still does something sane.
FOCUSED_SID="$("$YABAI" -m query --spaces --space 2>/dev/null \
  | "$JQ" -r '.index // empty')"
FOCUSED_WIN="$("$YABAI" -m query --windows --window 2>/dev/null \
  | "$JQ" -r '.id // empty')"

if [ -n "${WIN:-}" ]; then
  [ "$WIN" = "$FOCUSED_WIN" ] && ON_TRIGGER=1 || ON_TRIGGER=0
else
  [ "$SID" = "$FOCUSED_SID" ] && ON_TRIGGER=1 || ON_TRIGGER=0
fi

# Persistent per-space "pending flash" markers. space.sh reads these so a held
# flash color survives the full-row repaint that fires on every focus switch —
# it persists until the TRIGGERING WINDOW is focused, at which point
# flash-reconcile.sh clears the marker and the pill repaints its steady color.
PENDING_DIR="$(agent_hooks_pending_dir)"
mkdir -p "$PENDING_DIR" 2>/dev/null

if [ "$ON_TRIGGER" = "1" ]; then
  # User is on the triggering window → bounded blink: flash the tool color
  # FLASH_COUNT times, then settle on the focused steady-state color. Clear any
  # stale pending marker first — the active window must never keep a held color.
  rm -f "$PENDING_DIR/$SID" 2>/dev/null
  REVERT_BG="$COLOR_PILL_BG_FOCUSED"
  N="${FLASH_COUNT:-5}"
  log "active flash: $PILL ${N}x to $FLASH_COLOR, settle $REVERT_BG (win=${WIN:-?})"

  # Background subshell so the trigger returns immediately and doesn't block
  # sketchybar's event loop for the whole blink sequence.
  (
    i=0
    while [ "$i" -lt "$N" ]; do
      "$SKETCHYBAR" --animate sin_in_out 10 \
        --set "$PILL" background.color="$FLASH_COLOR"
      sleep 0.35
      "$SKETCHYBAR" --animate sin_in_out 10 \
        --set "$PILL" background.color="$REVERT_BG"
      sleep 0.35
      i=$((i + 1))
    done
    # REVERT_BG was frozen to the FOCUSED color when the blink started. If the
    # user switched away mid-blink, that final write paints the pill focused-blue
    # even though it's now unfocused (and no marker exists, so the reconciler
    # never corrects it). Hand the final paint to space.sh, which re-derives the
    # steady color from the CURRENT focus + any pending markers. See BUGS/bug-004.
    "$SKETCHYBAR" --trigger space_change >/dev/null 2>&1 || true
    log "active flash done $PILL ($N cycles)"
  ) &
else
  # User is NOT on the triggering window (different app on this space, or a
  # different space). Do NOT blink — hold the tool color statically and record a
  # marker of "<tool> <win>". space.sh re-applies the color on every repaint;
  # flash-reconcile.sh clears it once window WIN gains focus.
  printf '%s %s\n' "${TOOL:-claude}" "${WIN:-}" > "$PENDING_DIR/$SID" 2>/dev/null
  "$SKETCHYBAR" --animate sin_in_out 15 \
    --set "$PILL" background.color="$FLASH_COLOR"
  log "held flash: $PILL to $FLASH_COLOR (pending until win=${WIN:-?} focused, tool=${TOOL:-claude})"
fi

exit 0
