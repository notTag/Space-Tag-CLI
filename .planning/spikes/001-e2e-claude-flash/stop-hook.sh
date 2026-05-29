#!/usr/bin/env bash
# Claude Code Stop hook — fires when the assistant finishes a turn.
# Two-path resolution:
#   1. PRIMARY — read session_id from stdin, look up the yabai window id
#      captured by session-start-hook.sh, query its current space.
#   2. FALLBACK — PPID walk + is-visible heuristic. Used for sessions that
#      started before this hook was installed.
# Triggers sketchybar `flash_space SID=<n> TOOL=claude` on success.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/forensic-log.sh"

# Read Claude's stdin payload once (session_id is the key into the
# session_start state map).
PAYLOAD="$(cat 2>/dev/null || true)"

YABAI="${YABAI:-/opt/homebrew/bin/yabai}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
STATE_DIR="${SPIKE_001_STATE_DIR:-/tmp/spike-001-sessions}"

SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"
log stop_hook "fired pid=$$ ppid=$PPID session_id=${SESSION_ID:-MISSING}"

# ── PRIMARY PATH: persisted window id from SessionStart capture ───────────
# Robust against window rearrangement and multi-window terminals. Asks yabai
# for the window's CURRENT space (window may have been dragged to a new space
# mid-session — flash follows the window, not the user).
if [ -n "$SESSION_ID" ] && [ -f "$STATE_DIR/$SESSION_ID" ]; then
  WIN_ID="$(cat "$STATE_DIR/$SESSION_ID" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$WIN_ID" ]; then
    SPACE="$("$YABAI" -m query --windows --window "$WIN_ID" 2>/dev/null \
      | "$JQ" -r '.space // empty')"
    if [ -n "$SPACE" ] && [ "$SPACE" != "null" ]; then
      log stop_hook "resolved via SESSIONSTART_MAP window_id=$WIN_ID space=$SPACE"
      "$SKETCHYBAR" --trigger flash_space SID="$SPACE" TOOL=claude
      log stop_hook "triggered flash_space SID=$SPACE TOOL=claude strategy=sessionstart"
      exit 0
    else
      log stop_hook "SESSIONSTART_MAP stale: window_id=$WIN_ID no longer exists, falling back"
    fi
  fi
fi

# ── FALLBACK PATH: PPID walk + is-visible heuristic ───────────────────────
# Used when SessionStart hook wasn't installed at session launch (e.g. this
# very Claude session). Less reliable for multi-window terminal apps.
log stop_hook "FALLBACK ppid-walk + is-visible heuristic (sessionstart map missing)"

# Cache yabai windows once; we'll test each pid in the chain against this set.
WINDOWS_JSON="$("$YABAI" -m query --windows 2>/dev/null)"
if [ -z "$WINDOWS_JSON" ] || [ "$WINDOWS_JSON" = "null" ]; then
  log stop_hook "ERROR yabai --windows returned empty"
  exit 0
fi

# Walk PPID chain. macOS `ps -o ppid= -p <pid>` returns parent pid.
# Cap depth at 20 to avoid loops on any oddball process trees.
PID="$PPID"
SPACE=""
RESOLVED_PID=""
TRAIL=""
for _ in $(seq 1 20); do
  [ -z "$PID" ] && break
  [ "$PID" = "1" ] && break

  TRAIL="$TRAIL $PID"

  # Is this pid a yabai window? An app like Warp/iTerm has ONE pid but MANY
  # windows across many spaces. Pick the right one by preferring is-visible=true
  # (the window currently rendered on its display). Fall back to first match if
  # none is visible.
  #
  # Production-grade alternative (TODO for the plan phase): capture the focused
  # window's yabai id at SessionStart hook fire, persist by session id, look
  # it up here. Robust against window rearrangement and multi-window terminals.
  HIT="$(printf '%s' "$WINDOWS_JSON" | "$JQ" -r --argjson p "$PID" '
    [.[] | select(.pid == $p)] as $cand
    | ($cand | map(select(."is-visible" == true)) | .[0]) as $visible
    | ($visible // ($cand | .[0]) | .space // empty)
  ')"
  if [ -n "$HIT" ] && [ "$HIT" != "null" ]; then
    SPACE="$HIT"
    RESOLVED_PID="$PID"
    # Log the candidate count so we can audit ambiguous matches in the trail.
    CANDS="$(printf '%s' "$WINDOWS_JSON" | "$JQ" --argjson p "$PID" \
      '[.[] | select(.pid == $p)] | length')"
    log stop_hook "resolver_candidates pid=$PID count=$CANDS picked_space=$SPACE strategy=visible-or-first"
    break
  fi

  PARENT="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"
  PID="$PARENT"
done

log stop_hook "ppid_trail$TRAIL"

if [ -z "$SPACE" ]; then
  log stop_hook "FAIL no yabai window in ppid chain (killer for the loop)"
  exit 0
fi

log stop_hook "resolved pid=$RESOLVED_PID space=$SPACE strategy=fallback"

# Trigger sketchybar event with SID. The flash_watcher item subscribes.
"$SKETCHYBAR" --trigger flash_space SID="$SPACE" TOOL=claude
log stop_hook "triggered flash_space SID=$SPACE TOOL=claude strategy=fallback"
exit 0
