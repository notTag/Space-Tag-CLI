#!/usr/bin/env bash
# Shared installer helpers for per-tool agent-hooks adapters (claude.sh,
# codex.sh, hermes.sh). Sourced — has no main body. Provides:
#
#   adapter_backup_once         dated, idempotent copy of a user config file
#   adapter_chmod_scripts       restore +x on *.sh under a dir (Write tool drops it)
#   adapter_detect              return 0 if a tool's user config file is present
#   adapter_strip_spike_entries jq-remove spike-001 hook entries from Claude/Codex
#                               settings shape; idempotent
#
# Depends on state.sh (agent_hooks_backups_dir, agent_hooks_log).
#
# Source: . "$(dirname "$0")/common.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../state.sh"

JQ="${JQ:-/opt/homebrew/bin/jq}"

# ── adapter_backup_once ────────────────────────────────────────────────────
# $1 = src path (e.g. ~/.claude/settings.json)
# $2 = backup file name (e.g. claude-settings.json)
# Copies src → "$(agent_hooks_backups_dir)/<YYYY-MM-DD>/<name>". If a backup
# already exists at that dated path, no-op (returns 0). If src is missing,
# returns 1.
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

# ── adapter_chmod_scripts ──────────────────────────────────────────────────
# $1 = directory path. chmod +x every *.sh under it (recursive). Idempotent.
# Write tool does not preserve +x — this restores it.
adapter_chmod_scripts() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  find "$dir" -type f -name '*.sh' -exec chmod +x {} +
  return 0
}

# ── adapter_detect ─────────────────────────────────────────────────────────
# $1 = tool name (claude | codex | hermes). Returns 0 if the tool's user
# config file exists, 1 otherwise. Used by installers to skip absent tools.
adapter_detect() {
  local tool="$1"
  case "$tool" in
    claude) [ -f "$HOME/.claude/settings.json" ] ;;
    codex)  [ -f "$HOME/.codex/hooks.json" ] ;;
    hermes) [ -f "$HOME/.hermes/config.yaml" ] ;;
    *)      return 1 ;;
  esac
}

# ── adapter_strip_spike_entries ────────────────────────────────────────────
# $1 = path to a JSON settings file (Claude or Codex shape).
# Removes any hook entry whose .command contains the spike-001 substring
# ".planning/spikes/001-e2e-claude-flash/". Handles both Claude shape
# (.hooks.<Event>[].hooks[]) and Codex shape (same layout per CONVENTIONS).
# Drops any matcher group that ends up empty. Idempotent. Logs each strip.
adapter_strip_spike_entries() {
  local file="$1"
  local marker=".planning/spikes/001-e2e-claude-flash/"
  [ -f "$file" ] || return 0
  local tmp
  tmp="$(mktemp)"
  "${JQ:-jq}" --arg m "$marker" '
    if .hooks then
      .hooks |= with_entries(
        .value |= (
          map(
            .hooks = ((.hooks // []) | map(select((.command // "") | contains($m) | not)))
          ) | map(select((.hooks // [] | length) > 0))
        )
      )
    else . end
  ' "$file" > "$tmp" && mv "$tmp" "$file"
  agent_hooks_log adapter "stripped spike entries from $file"
}
