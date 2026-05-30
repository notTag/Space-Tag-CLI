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
#    Hard-fail on deploy errors: a silent cp failure here leaves the user with an
#    "install complete" message but no working flash hook (reviewer-reproduced
#    against a clean $HOME). Make it loud.
mkdir -p "$DEPLOY_DIR/adapters" || {
  echo "✗ agent-hooks install: cannot create $DEPLOY_DIR/adapters" >&2
  agent_hooks_log install "FATAL mkdir $DEPLOY_DIR/adapters failed"
  exit 1
}
cp "$HERE"/*.sh "$DEPLOY_DIR/" || {
  echo "✗ agent-hooks install: failed to deploy runtime scripts to $DEPLOY_DIR" >&2
  agent_hooks_log install "FATAL cp scripts → $DEPLOY_DIR failed"
  exit 1
}
cp "$HERE/adapters"/*.sh "$DEPLOY_DIR/adapters/" || {
  echo "✗ agent-hooks install: failed to deploy adapters to $DEPLOY_DIR/adapters" >&2
  agent_hooks_log install "FATAL cp adapters → $DEPLOY_DIR/adapters failed"
  exit 1
}

# 3. Restore +x (Write tool does not preserve)
chmod +x "$DEPLOY_DIR"/*.sh "$DEPLOY_DIR/adapters"/*.sh
agent_hooks_log install "deployed scripts to $DEPLOY_DIR"

# 3b. Sync sketchybarrc + theme.sh if deployed copies have drifted from the repo.
#     Top-level install.sh symlinks these, but in practice some users end up with
#     real-file copies (e.g. via editor-clobber or a prior copy-based install) —
#     per project memory [[live-config-deploy-copies]]. If deployed is a symlink,
#     leave it; if it's a real file and content differs, cp from repo so the new
#     flash_space event + flash colors land. Idempotent.
SKETCHYBAR_CFG_DIR="$HOME/.config/sketchybar"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# Ensure the sketchybar config dir exists — on a clean $HOME the cp's below
# would silently no-op and leave flash_space / flash_watcher unregistered.
mkdir -p "$SKETCHYBAR_CFG_DIR" || {
  echo "✗ agent-hooks install: cannot create $SKETCHYBAR_CFG_DIR" >&2
  agent_hooks_log install "FATAL mkdir $SKETCHYBAR_CFG_DIR failed"
  exit 1
}
sync_if_drifted() {
  local repo_src="$1" deployed="$2" label="$3"
  [ -f "$repo_src" ] || return 0
  if [ -L "$deployed" ]; then
    agent_hooks_log install "skip $label sync (symlink at $deployed, picks up edits)"
    return 0
  fi
  if [ ! -f "$deployed" ]; then
    cp "$repo_src" "$deployed" || {
      echo "✗ agent-hooks install: failed to copy $label → $deployed" >&2
      agent_hooks_log install "FATAL cp $repo_src → $deployed failed"
      return 1
    }
    agent_hooks_log install "deployed missing $label: copied $repo_src → $deployed"
    return 0
  fi
  if ! cmp -s "$repo_src" "$deployed"; then
    cp "$repo_src" "$deployed" || {
      echo "✗ agent-hooks install: failed to sync $label → $deployed" >&2
      agent_hooks_log install "FATAL cp $repo_src → $deployed (drift-sync) failed"
      return 1
    }
    agent_hooks_log install "synced $label (deployed drifted from repo)"
  fi
}
sync_if_drifted "$REPO_ROOT/sketchybar/sketchybarrc" "$SKETCHYBAR_CFG_DIR/sketchybarrc"  sketchybarrc || exit 1
sync_if_drifted "$REPO_ROOT/sketchybar/theme.sh"      "$SKETCHYBAR_CFG_DIR/theme.sh"      theme.sh      || exit 1

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
