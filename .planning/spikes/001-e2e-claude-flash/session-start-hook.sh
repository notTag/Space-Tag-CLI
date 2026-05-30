#!/usr/bin/env bash
# Claude Code SessionStart hook — fires when `claude` launches a session.
# At this exact moment, the focused yabai window IS the terminal hosting this
# session. Capture its stable yabai window id and persist by Claude session id
# so the Stop hook can always resolve back to the correct space, even if the
# user drags the window between spaces mid-session.
#
# Persistence: /tmp/spike-001-sessions/<session_id> — single line with the
# yabai window id (an integer).
#
# Wired by install.sh:
#   "hooks": {"SessionStart": [{"matcher": "",
#     "hooks": [{"type":"command", "command":"<abs path to this script>"}]}]}

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/forensic-log.sh"

YABAI="${YABAI:-/opt/homebrew/bin/yabai}"
JQ="${JQ:-/opt/homebrew/bin/jq}"
STATE_DIR="${SPIKE_001_STATE_DIR:-/tmp/spike-001-sessions}"
mkdir -p "$STATE_DIR"

# Claude pipes a JSON payload to the hook's stdin. We need session_id.
# Read it once into a variable so we can parse without re-blocking on stdin.
PAYLOAD="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"
SOURCE="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.source // "unknown"' 2>/dev/null)"

log session_start "fired pid=$$ ppid=$PPID source=$SOURCE session_id=${SESSION_ID:-MISSING}"

if [ -z "$SESSION_ID" ]; then
  log session_start "ERROR no session_id in stdin payload — cannot persist"
  exit 0
fi

# Capture the focused yabai window id at this exact moment. This is the
# terminal window the user just launched Claude in. Stable across space moves.
WINDOW_ID="$("$YABAI" -m query --windows --window 2>/dev/null \
  | "$JQ" -r '.id // empty')"

if [ -z "$WINDOW_ID" ] || [ "$WINDOW_ID" = "null" ]; then
  log session_start "ERROR yabai reported no focused window — cannot capture"
  exit 0
fi

# Also capture the app + space at this moment for forensic value.
FOCUSED="$("$YABAI" -m query --windows --window 2>/dev/null \
  | "$JQ" -c '{id, pid, app, title, space}')"

printf '%s\n' "$WINDOW_ID" > "$STATE_DIR/$SESSION_ID"
log session_start "captured window_id=$WINDOW_ID for session=$SESSION_ID context=$FOCUSED"

exit 0
