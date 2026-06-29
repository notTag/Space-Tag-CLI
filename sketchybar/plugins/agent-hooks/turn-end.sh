#!/usr/bin/env bash
# turn-end.sh — agent-hooks
#
# Production port of spike 001's stop-hook.sh. Fires when an agent finishes a
# turn (Claude Stop, Codex turn_end, Hermes on_turn_end). Resolves the agent's
# host space and triggers sketchybar `flash_space` so the listener can animate
# the matching pill.
#
# Two-path resolution:
#   1. PRIMARY  — read `session_id` from stdin, look up the yabai window id
#                 captured by session-start.sh, ask yabai for that window's
#                 CURRENT space (window may have been dragged mid-session — the
#                 flash follows the window, not the user). Robust against
#                 rearrangement and multi-window terminals.
#   2. FALLBACK — PPID walk + is-visible heuristic. Used when SessionStart
#                 wasn't installed at session launch (pre-install sessions) or
#                 the persisted window vanished.
#
# Wire contract:
#   stdin  : JSON object containing `session_id` at top level (Claude / Codex /
#            Hermes all match this shape).
#   $1     : TOOL name (`claude` | `codex` | `hermes`). Adapters pass it
#            explicitly so the flash listener can colour by source.
#   stdout : `{}\n` on every code path (Hermes JSON-response contract; Claude
#            and Codex ignore extra output).
#   exit   : always 0 — never block the agent loop on errors.
#
# Focus-suppress gate: when `FLASH_FOCUS_SUPPRESS=true` AND the resolved space
# is the user's currently-focused space, skip the trigger. Default is `false`
# (always flash) per the locked decision in the phase plan.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./state.sh
. "$HERE/state.sh"
# shellcheck source=/dev/null
. "$HOME/.config/sketchybar/theme.sh"

# Binary bindings. theme.sh may set YABAI / JQ, but leaves them empty when
# command -v fails inside a hook's minimal PATH — so re-resolve through
# agent_hooks_bin, which also knows the SpaceTag app's bundled binary locations
# (an app install never puts yabai / sketchybar on PATH). SKETCHYBAR is not set
# by theme.sh, so this script binds it too and stays standalone.
YABAI="${YABAI:-$(agent_hooks_bin yabai)}"
JQ="${JQ:-$(agent_hooks_bin jq)}"
SKETCHYBAR="${SKETCHYBAR:-$(agent_hooks_bin sketchybar)}"

# Read stdin once, synchronously. Avoid re-blocking on a closed pipe.
PAYLOAD="$(cat 2>/dev/null || true)"

# TOOL defaults to claude — adapters should always pass it, but fall back so
# a direct hook invocation (e.g. Claude Code with no wrapper) still works.
TOOL="${1:-claude}"

SESSION_ID="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.session_id // empty' 2>/dev/null)"

agent_hooks_log turn_end "fired pid=$$ ppid=$PPID tool=$TOOL session_id=${SESSION_ID:-MISSING}"

# ── PRIMARY PATH: persisted window id from SessionStart capture ──────────
# Robust against window rearrangement and multi-window terminals. Asks yabai
# for the window's CURRENT space (window may have been dragged to a new space
# mid-session — flash follows the window, not the user).
SESSIONS_DIR="$(agent_hooks_sessions_dir)"
if [ -n "${SESSION_ID:-}" ] && [ -f "$SESSIONS_DIR/$SESSION_ID" ]; then
  WIN_ID="$(cat "$SESSIONS_DIR/$SESSION_ID" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$WIN_ID" ]; then
    SPACE="$("$YABAI" -m query --windows --window "$WIN_ID" 2>/dev/null | "$JQ" -r '.space // empty' 2>/dev/null)"
    if [ -n "$SPACE" ] && [ "$SPACE" != "null" ]; then
      agent_hooks_log turn_end "strategy=sessionstart window_id=$WIN_ID space=$SPACE"

      # Focus-suppress gate (primary path).
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

# ── FALLBACK PATH: PPID walk + is-visible heuristic ──────────────────────
# Used when SessionStart hook wasn't installed at session launch (e.g. the
# very first install). Less reliable for multi-window terminal apps.
agent_hooks_log turn_end "FALLBACK ppid-walk + is-visible heuristic (sessionstart map missing or stale)"

# Cache yabai windows once; we'll test each pid in the chain against this set.
WINDOWS_JSON="$("$YABAI" -m query --windows 2>/dev/null || printf '[]')"

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
  # (the window the user actually sees on its space), falling back to the
  # first match if none is visible.
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
  # Resolve the specific window id we picked for this pid (visible-or-first),
  # so the flash listener can compare against the user's focused window. Empty
  # is fine — flash-listener degrades to space-level focus when WIN is absent.
  WIN_ID="$(printf '%s' "$WINDOWS_JSON" | "$JQ" -r --argjson p "$RESOLVED_PID" '
    [.[] | select(.pid == $p)] as $cand
    | (($cand | map(select(."is-visible" == true)) | .[0]) // ($cand | .[0]))
    | .id // empty' 2>/dev/null)"
  agent_hooks_log turn_end "strategy=fallback resolved pid=$RESOLVED_PID space=$SPACE win=$WIN_ID"

  # Focus-suppress gate (fallback path).
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

# ── Both paths failed: log and exit non-blocking ─────────────────────────
agent_hooks_log turn_end "FAIL no resolvable window for session_id=${SESSION_ID:-MISSING}"
printf '{}\n'
exit 0
