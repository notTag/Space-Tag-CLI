#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./state.sh
. "$HERE/state.sh"
# shellcheck source=/dev/null
. "$HOME/.config/sketchybar/theme.sh"

YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
JQ="${JQ:-$(command -v jq || echo /opt/homebrew/bin/jq)}"

PAYLOAD="$(cat 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"
SOURCE="$(printf '%s'    "$PAYLOAD" | "$JQ" -r '.source // empty'     2>/dev/null)"

if [ -z "${SESSION_ID:-}" ]; then
  agent_hooks_log session_start "ERROR no session_id in stdin"
  printf '{}\n'
  exit 0
fi

# The window ID remains stable if the session's window moves to another space.
WINDOW_ID="$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.id // empty' 2>/dev/null)"

if [ -z "${WINDOW_ID:-}" ]; then
  agent_hooks_log session_start "ERROR no focused yabai window for session_id=$SESSION_ID source=$SOURCE"
  printf '{}\n'
  exit 0
fi

agent_hooks_ensure_dirs

SESSIONS_DIR="$(agent_hooks_sessions_dir)"
printf '%s\n' "$WINDOW_ID" > "$SESSIONS_DIR/$SESSION_ID"

agent_hooks_prune_sessions

agent_hooks_log session_start "captured window_id=$WINDOW_ID session_id=$SESSION_ID source=$SOURCE"

printf '{}\n'
exit 0
