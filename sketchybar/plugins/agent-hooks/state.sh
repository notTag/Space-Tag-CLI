#!/usr/bin/env bash

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

# App installs expose bundled binaries through the SketchyBar LaunchAgent.
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
