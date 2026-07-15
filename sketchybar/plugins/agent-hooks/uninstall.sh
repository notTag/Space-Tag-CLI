#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/state.sh"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"

DEPLOY_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"
KEEP_SCRIPTS=false
for arg in "$@"; do
  case "$arg" in
    --keep-scripts) KEEP_SCRIPTS=true ;;
  esac
done

echo "▸ agent-hooks uninstall starting"
agent_hooks_log uninstall "starting; keep_scripts=$KEEP_SCRIPTS"

for tool in claude codex hermes; do
  adapter="$DEPLOY_DIR/adapters/$tool.sh"
  [ -x "$adapter" ] || adapter="$HERE/adapters/$tool.sh"
  if [ -x "$adapter" ]; then
    echo "▸ adapter: $tool"
    "$adapter" uninstall
  fi
done

if [ "$KEEP_SCRIPTS" = "false" ] && [ -d "$DEPLOY_DIR" ]; then
  rm -rf "$DEPLOY_DIR"
  agent_hooks_log uninstall "removed $DEPLOY_DIR"
  echo "  removed $DEPLOY_DIR"
else
  echo "  kept $DEPLOY_DIR (--keep-scripts or already gone)"
fi

if command -v "$SKETCHYBAR" >/dev/null 2>&1; then
  "$SKETCHYBAR" --reload >/dev/null 2>&1 || true
  agent_hooks_log uninstall "sketchybar --reload fired"
fi

echo ""
echo "✓ agent-hooks uninstall complete."
echo "  Log preserved at: ${SPACETAG_LOG:-/tmp/agent-hooks.log}"
agent_hooks_log uninstall "complete"
