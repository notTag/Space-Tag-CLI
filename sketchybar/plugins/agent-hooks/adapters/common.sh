#!/usr/bin/env bash

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../state.sh"

JQ="${JQ:-/opt/homebrew/bin/jq}"

adapter_backup_once() {
  local src="$1"
  local name="$2"
  if [ ! -f "$src" ]; then
    agent_hooks_log adapter "backup skipped — src missing: $src"
    return 1
  fi
  local day
  day="$(date +%Y-%m-%d)"
  local dest_dir
  dest_dir="$(agent_hooks_backups_dir)/$day"
  local dest="$dest_dir/$name"
  if [ -f "$dest" ]; then
    return 0
  fi
  mkdir -p "$dest_dir"
  cp "$src" "$dest"
  agent_hooks_log adapter "backed up $src → $dest"
  return 0
}

adapter_chmod_scripts() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -type f -name '*.sh' -exec chmod +x {} +
  return 0
}

adapter_detect() {
  local tool="$1"
  case "$tool" in
    claude) [ -f "$HOME/.claude/settings.json" ] ;;
    codex)  [ -f "$HOME/.codex/hooks.json" ] ;;
    hermes) [ -f "$HOME/.hermes/config.yaml" ] ;;
    *)      return 1 ;;
  esac
}

adapter_strip_spike_entries() {
  local file="$1"
  local marker=".planning/spikes/001-e2e-claude-flash/"
  [ -f "$file" ] || return 0
  local tmp
  tmp="$(mktemp)"
  if ! "${JQ:-jq}" --arg m "$marker" '
    if .hooks then
      .hooks |= with_entries(
        .value |= (
          map(
            .hooks = ((.hooks // []) | map(select((.command // "") | contains($m) | not)))
          ) | map(select((.hooks // [] | length) > 0))
        )
      )
    else . end
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    agent_hooks_log adapter "failed to strip spike entries from $file"
    return 1
  fi
  mv "$tmp" "$file" || {
    rm -f "$tmp"
    agent_hooks_log adapter "failed to replace $file after stripping spike entries"
    return 1
  }
  agent_hooks_log adapter "stripped spike entries from $file"
}
