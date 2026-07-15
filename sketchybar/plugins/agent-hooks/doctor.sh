#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/state.sh"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
DEPLOY_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"


OVERALL_OK=true

printf '═══ agent-hooks doctor ═══\n\n'

printf '▸ adapters:\n'
for tool in claude codex hermes; do
  adapter="$HERE/adapters/$tool.sh"
  if [ -x "$adapter" ]; then
    if out="$("$adapter" status 2>&1)"; then
      printf '  ✓ %s\n' "$out"
    else
      printf '  ✗ %s\n' "$out"
      OVERALL_OK=false
    fi
  else
    printf '  ? %s adapter missing at %s\n' "$tool" "$adapter"
    OVERALL_OK=false
  fi
done

printf '\n▸ deployed scripts (%s):\n' "$DEPLOY_DIR"
for f in state.sh session-start.sh turn-end.sh flash-listener.sh; do
  path="$DEPLOY_DIR/$f"
  if [ -x "$path" ]; then
    printf '  ✓ %s (executable)\n' "$f"
  elif [ -f "$path" ]; then
    printf '  ⚠ %s exists but NOT executable\n' "$f"
    OVERALL_OK=false
  else
    printf '  ✗ %s MISSING\n' "$f"
    OVERALL_OK=false
  fi
done

printf '\n▸ sketchybar:\n'
if command -v "$SKETCHYBAR" >/dev/null 2>&1; then
  if "$SKETCHYBAR" --query flash_watcher >/dev/null 2>&1; then
    printf '  ✓ flash_watcher item registered\n'
  else
    printf '  ✗ flash_watcher item missing — sketchybar may need --reload\n'
    OVERALL_OK=false
  fi
else
  printf '  ⚠ sketchybar binary not found at %s\n' "$SKETCHYBAR"
fi

printf '\n▸ state:\n'
state_dir="$(agent_hooks_state_dir)"
sessions_dir="$(agent_hooks_sessions_dir)"
backups_dir="$(agent_hooks_backups_dir)"
printf '  state_dir:   %s\n' "$state_dir"
if [ -d "$sessions_dir" ]; then
  count=$(ls -1 "$sessions_dir" 2>/dev/null | wc -l | tr -d ' ')
  printf '  sessions:    %s entries\n' "$count"
else
  printf '  sessions:    (dir missing)\n'
fi
if [ -d "$backups_dir" ]; then
  bcount=$(find "$backups_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
  printf '  backups:     %s files across all dated dirs\n' "$bcount"
fi

printf '\n▸ recent log (last 10 lines of %s):\n' "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
if [ -f "${SPACETAG_LOG:-/tmp/agent-hooks.log}" ]; then
  tail -10 "${SPACETAG_LOG:-/tmp/agent-hooks.log}" | sed 's/^/  /'
else
  printf '  (no log file yet)\n'
fi

printf '\n▸ next test:\n'
printf '  Open a terminal, run `claude` (or codex, or `hermes chat`), send any\n'
printf '  message — watch the pill for that space flash on turn end.\n'

printf '\n═══ '
if [ "$OVERALL_OK" = "true" ]; then
  printf 'healthy ✓\n'
  exit 0
else
  printf 'issues found ✗\n'
  exit 1
fi
