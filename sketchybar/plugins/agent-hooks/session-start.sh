#!/usr/bin/env bash
# session-start.sh — agent-hooks
#
# Captures the focused yabai window id at agent session start and persists it
# keyed by session_id. Invoked by Claude Code (SessionStart), Codex CLI
# (session_start), and Hermes Agent (on_session_start) — all three pipe a JSON
# payload to stdin with `session_id` at the top level.
#
# At this exact moment the focused yabai window IS the terminal hosting the
# agent session, so its id is the stable handle we use later (in turn-end.sh)
# to resolve back to whatever space the user has since dragged the window to.
#
# Wire contract:
#   stdin  : JSON object, must contain `session_id`. Claude also sends `source`.
#   stdout : `{}\n` on every code path (Hermes JSON-response contract).
#   exit   : always 0 — never block the agent loop on errors.
#
# Persistence: $(agent_hooks_sessions_dir)/<session_id> — single line, integer
# yabai window id.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./state.sh
. "$HERE/state.sh"
# shellcheck source=/dev/null
. "$HOME/.config/sketchybar/theme.sh"

# Binary bindings — theme.sh sets YABAI / JQ, but a hook process can be spawned
# with a minimal PATH that drops /opt/homebrew. Mirror the fallback chain used
# by turn-end.sh / flash-listener.sh so the focused-window capture still works.
YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
JQ="${JQ:-$(command -v jq || echo /opt/homebrew/bin/jq)}"

# Read stdin once, synchronously. Avoid re-blocking on a closed pipe.
PAYLOAD="$(cat 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"
SOURCE="$(printf '%s'    "$PAYLOAD" | "$JQ" -r '.source // empty'     2>/dev/null)"

if [ -z "${SESSION_ID:-}" ]; then
  agent_hooks_log session_start "ERROR no session_id in stdin"
  printf '{}\n'
  exit 0
fi

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
