#!/usr/bin/env bash
# Top-level installer for the SpaceTag agent completion-flash feature.
# Deploys runtime scripts to ~/.config/sketchybar/plugins/agent-hooks/,
# runs per-tool adapters, and reloads sketchybar.
#
# Idempotent: re-running produces identical final state.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/state.sh"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"

DEPLOY_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"

echo "▸ agent-hooks install starting"
agent_hooks_log install "starting; deploy_dir=$DEPLOY_DIR"

# 1. State dirs
agent_hooks_ensure_dirs
agent_hooks_log install "ensured state dirs: $(agent_hooks_sessions_dir), $(agent_hooks_backups_dir)"

# 2. Deploy runtime scripts (cp not symlink — per project memory live-config-deploy-copies.md)
mkdir -p "$DEPLOY_DIR/adapters"
cp "$HERE"/*.sh "$DEPLOY_DIR/"
cp "$HERE/adapters"/*.sh "$DEPLOY_DIR/adapters/"

# 3. Restore +x (Write tool does not preserve)
chmod +x "$DEPLOY_DIR"/*.sh "$DEPLOY_DIR/adapters"/*.sh
agent_hooks_log install "deployed scripts to $DEPLOY_DIR"

# 4. Run per-tool adapters
for tool in claude codex hermes; do
  adapter="$DEPLOY_DIR/adapters/$tool.sh"
  if [ -x "$adapter" ]; then
    echo "▸ adapter: $tool"
    "$adapter" install
  else
    echo "  warn: $adapter missing — skipping"
    agent_hooks_log install "WARN $tool adapter missing at $adapter"
  fi
done

# 5. Reload sketchybar to pick up the flash_space event + flash_watcher item from sketchybarrc
if command -v "$SKETCHYBAR" >/dev/null 2>&1; then
  "$SKETCHYBAR" --reload >/dev/null 2>&1 || true
  agent_hooks_log install "sketchybar --reload fired"
fi

# 6. Summary
echo ""
echo "✓ agent-hooks install complete."
echo "  Deploy dir: $DEPLOY_DIR"
echo "  State dir:  $(agent_hooks_state_dir)"
echo "  Log:        ${SPACETAG_LOG:-/tmp/agent-hooks.log}"
echo ""
echo "  Test: open a terminal, run \`claude\` (or codex / hermes chat), send any"
echo "        message — the pill for that space should flash on turn end."
echo ""
echo "  Uninstall:  $HERE/uninstall.sh"
echo "  Diagnose:   $DEPLOY_DIR/doctor.sh"

agent_hooks_log install "complete"
