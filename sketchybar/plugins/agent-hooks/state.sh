#!/usr/bin/env bash
# Shared state helpers for the agent-hooks plugin. Sourced by session-start.sh,
# turn-end.sh, install.sh, doctor.sh, etc. Defines paths under the spacetag
# state dir, a forensic logger (ISO-8601 + tag, append-only), a 7-day TTL prune
# for session files, and an idempotent mkdir helper.
#
# Source: . "$(dirname "$0")/state.sh"
#
# Env overrides:
#   SPACETAG_STATE_DIR  override the base state dir (default
#                       "$HOME/Library/Application Support/spacetag")
#   SPACETAG_LOG        override the forensic log path (default
#                       /tmp/agent-hooks.log)

agent_hooks_state_dir() {
  printf '%s\n' "${SPACETAG_STATE_DIR:-$HOME/Library/Application Support/spacetag}"
}

agent_hooks_sessions_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/sessions"
}

agent_hooks_backups_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/backups"
}

agent_hooks_pending_dir() {
  printf '%s\n' "$(agent_hooks_state_dir)/pending-flash"
}

agent_hooks_log() {
  local tag="$1"; shift
  local log="${SPACETAG_LOG:-/tmp/agent-hooks.log}"
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$tag" "$*" >> "$log"
}

agent_hooks_prune_sessions() {
  find "$(agent_hooks_sessions_dir)" -type f -mtime +7 -delete 2>/dev/null || true
}

agent_hooks_ensure_dirs() {
  mkdir -p "$(agent_hooks_sessions_dir)" "$(agent_hooks_backups_dir)" "$(agent_hooks_pending_dir)"
}

# ── runtime binary resolution ───────────────────────────────────────────────
# Resolve an absolute path to one of the runtime binaries (yabai | jq |
# sketchybar). The agent CLIs (Claude / Codex / Hermes) spawn these hooks with
# their own minimal environment — they do NOT inherit the sketchybar
# LaunchAgent's PATH or its YABAI / JQ / SKETCHYBAR exports. On a SpaceTag *app*
# install the binaries are bundled inside SpaceTag.app and never placed on PATH,
# so `command -v` finds nothing and the old hard-coded /opt/homebrew fallback
# points at a path that does not exist — every query then fails silently and no
# flash ever fires. Search order:
#   1. on PATH               — CLI / Homebrew installs expose the binary directly
#   2. SpaceTag LaunchAgent  — app install: the authoritative bundled path the
#                              running sketchybar / yabai actually use
#   3. well-known prefixes   — last-resort Homebrew locations (arm + intel)
# Falls through to the bare name so a genuinely-missing binary fails loudly at
# the call site (callers already log the empty result).
agent_hooks_bin() {
  local name="$1"
  local candidate

  candidate="$(command -v "$name" 2>/dev/null)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(agent_hooks_bin_from_launchagent "$name")"
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$name"
}

# Read the absolute binary path the SpaceTag app's sketchybar LaunchAgent is
# configured with. The plist is the single source of truth for an app install:
# its EnvironmentVariables carry YABAI and JQ, and ProgramArguments[0] is the
# sketchybar binary itself. Returns non-zero (no output) when the plist or
# PlistBuddy is absent (e.g. a Homebrew / CLI install) so the caller moves on.
agent_hooks_bin_from_launchagent() {
  local name="$1"
  local plist="$HOME/Library/LaunchAgents/com.nottag.spacetag.sketchybar.plist"
  local plist_buddy=/usr/libexec/PlistBuddy
  [ -f "$plist" ] || return 1
  [ -x "$plist_buddy" ] || return 1
  case "$name" in
    yabai)      "$plist_buddy" -c 'Print :EnvironmentVariables:YABAI' "$plist" 2>/dev/null ;;
    jq)         "$plist_buddy" -c 'Print :EnvironmentVariables:JQ'    "$plist" 2>/dev/null ;;
    sketchybar) "$plist_buddy" -c 'Print :ProgramArguments:0'         "$plist" 2>/dev/null ;;
    *)          return 1 ;;
  esac
}
