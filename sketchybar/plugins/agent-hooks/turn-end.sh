#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./state.sh
. "$HERE/state.sh"
# shellcheck source=/dev/null
. "$HOME/.config/sketchybar/theme.sh"

YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
JQ="${JQ:-$(command -v jq || echo /opt/homebrew/bin/jq)}"
SKETCHYBAR="${SKETCHYBAR:-$(command -v sketchybar || echo /opt/homebrew/bin/sketchybar)}"

PAYLOAD="$(cat 2>/dev/null || true)"

TOOL="${1:-claude}"

SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"

agent_hooks_log turn_end "fired pid=$$ ppid=$PPID tool=$TOOL session_id=${SESSION_ID:-MISSING}"

SESSIONS_DIR="$(agent_hooks_sessions_dir)"
if [ -n "${SESSION_ID:-}" ] && [ -f "$SESSIONS_DIR/$SESSION_ID" ]; then
  WIN_ID="$(cat "$SESSIONS_DIR/$SESSION_ID" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$WIN_ID" ]; then
    # Resolve the window's current space in case it moved during the session.
    SPACE="$("$YABAI" -m query --windows --window "$WIN_ID" 2>/dev/null | "$JQ" -r '.space // empty' 2>/dev/null)"
    if [ -n "$SPACE" ] && [ "$SPACE" != "null" ]; then
      agent_hooks_log turn_end "strategy=sessionstart window_id=$WIN_ID space=$SPACE"

      if [ "${FLASH_FOCUS_SUPPRESS:-false}" = "true" ]; then
        FOCUSED="$("$YABAI" -m query --spaces --space 2>/dev/null | "$JQ" -r '.index // empty' 2>/dev/null)"
        if [ -n "$FOCUSED" ] && [ "$SPACE" = "$FOCUSED" ]; then
          agent_hooks_log turn_end "focus_suppress=true skipped strategy=sessionstart space=$SPACE"
          printf '{}\n'
          exit 0
        fi
      fi

      "$SKETCHYBAR" --trigger flash_space SID="$SPACE" TOOL="$TOOL" WIN="$WIN_ID" >/dev/null 2>&1 || true
      agent_hooks_log turn_end "triggered flash_space SID=$SPACE TOOL=$TOOL WIN=$WIN_ID strategy=sessionstart"
      printf '{}\n'
      exit 0
    else
      agent_hooks_log turn_end "SESSIONSTART_MAP stale window_id=$WIN_ID space-query empty, falling back"
    fi
  fi
fi

agent_hooks_log turn_end "FALLBACK ppid-walk + is-visible heuristic (sessionstart map missing or stale)"

WINDOWS_JSON="$("$YABAI" -m query --windows 2>/dev/null || printf '[]')"

PID="$PPID"
SPACE=""
RESOLVED_PID=""
TRAIL=""
for _ in $(seq 1 20); do
  [ -z "$PID" ] && break
  [ "$PID" = "1" ] && break

  TRAIL="$TRAIL $PID"

  HIT="$(printf '%s' "$WINDOWS_JSON" | "$JQ" -r --argjson p "$PID" '
    [.[] | select(.pid == $p)] as $cand
    | ($cand | map(select(."is-visible" == true)) | .[0]) as $visible
    | ($visible // ($cand | .[0]) | .space // empty)
  ' 2>/dev/null)"
  if [ -n "$HIT" ] && [ "$HIT" != "null" ]; then
    SPACE="$HIT"
    RESOLVED_PID="$PID"
    CANDS="$(printf '%s' "$WINDOWS_JSON" | "$JQ" --argjson p "$PID" \
      '[.[] | select(.pid == $p)] | length' 2>/dev/null)"
    agent_hooks_log turn_end "resolver_candidates pid=$PID count=$CANDS picked_space=$SPACE strategy=visible-or-first"
    break
  fi

  PARENT="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"
  PID="$PARENT"
done

agent_hooks_log turn_end "ppid_trail$TRAIL"

if [ -n "$SPACE" ]; then
  WIN_ID="$(printf '%s' "$WINDOWS_JSON" | "$JQ" -r --argjson p "$RESOLVED_PID" '
    [.[] | select(.pid == $p)] as $cand
    | (($cand | map(select(."is-visible" == true)) | .[0]) // ($cand | .[0]))
    | .id // empty' 2>/dev/null)"
  agent_hooks_log turn_end "strategy=fallback resolved pid=$RESOLVED_PID space=$SPACE win=$WIN_ID"

  if [ "${FLASH_FOCUS_SUPPRESS:-false}" = "true" ]; then
    FOCUSED="$("$YABAI" -m query --spaces --space 2>/dev/null | "$JQ" -r '.index // empty' 2>/dev/null)"
    if [ -n "$FOCUSED" ] && [ "$SPACE" = "$FOCUSED" ]; then
      agent_hooks_log turn_end "focus_suppress=true skipped strategy=fallback space=$SPACE"
      printf '{}\n'
      exit 0
    fi
  fi

  "$SKETCHYBAR" --trigger flash_space SID="$SPACE" TOOL="$TOOL" WIN="$WIN_ID" >/dev/null 2>&1 || true
  agent_hooks_log turn_end "triggered flash_space SID=$SPACE TOOL=$TOOL WIN=$WIN_ID strategy=fallback"
  printf '{}\n'
  exit 0
fi

agent_hooks_log turn_end "FAIL no resolvable window for session_id=${SESSION_ID:-MISSING}"
printf '{}\n'
exit 0
