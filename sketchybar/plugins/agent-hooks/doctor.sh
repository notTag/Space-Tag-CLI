#!/usr/bin/env bash
# Diagnostic for the SpaceTag agent completion-flash feature.
#
# Reports:
#   1. Per-tool adapter status (delegates to <tool>.sh status)
#   2. Deployed script presence + exec bit
#   3. Sketchybar flash_watcher item presence
#   4. State dir + active session count
#   5. Recent forensic log tail
#
# Exit code: 0 if all installed tools' adapters report installed AND scripts
# are deployed AND sketchybar item present. 1 otherwise. Suitable for CI.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/state.sh"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"
DEPLOY_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"

# Run doctor on the REPO copy of adapters (HERE) by default, but if running
# from a deployed location, use the deployed copies. HERE already resolves to
# either, so this falls out naturally.

OVERALL_OK=true

printf '═══ agent-hooks doctor ═══\n\n'

# 1. Adapter status per tool
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

# 2. Deployed runtime scripts
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

# 3. Sketchybar item
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

# 4. State dir + sessions
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

# 5. Recent log
printf '\n▸ recent log (last 10 lines of %s):\n' "${SPACETAG_LOG:-/tmp/agent-hooks.log}"
if [ -f "${SPACETAG_LOG:-/tmp/agent-hooks.log}" ]; then
  tail -10 "${SPACETAG_LOG:-/tmp/agent-hooks.log}" | sed 's/^/  /'
else
  printf '  (no log file yet)\n'
fi

# 6. Next-test hint
printf '\n▸ next test:\n'
printf '  Open a terminal, run `claude` (or codex, or `hermes chat`), send any\n'
printf '  message — watch the pill for that space flash on turn end.\n'

# 7. Verdict
printf '\n═══ '
if [ "$OVERALL_OK" = "true" ]; then
  printf 'healthy ✓\n'
  exit 0
else
  printf 'issues found ✗\n'
  exit 1
fi
