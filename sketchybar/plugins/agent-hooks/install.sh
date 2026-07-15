#!/usr/bin/env bash

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/state.sh"
SKETCHYBAR="${SKETCHYBAR:-/opt/homebrew/bin/sketchybar}"

DEPLOY_DIR="${SCRIPTS_DIR:-$HOME/.config/sketchybar/plugins/agent-hooks}"

echo "▸ agent-hooks install starting"
agent_hooks_log install "starting; deploy_dir=$DEPLOY_DIR"

agent_hooks_ensure_dirs
agent_hooks_log install "ensured state dirs: $(agent_hooks_sessions_dir), $(agent_hooks_backups_dir)"

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

chmod +x "$DEPLOY_DIR"/*.sh "$DEPLOY_DIR/adapters"/*.sh
agent_hooks_log install "deployed scripts to $DEPLOY_DIR"

SKETCHYBAR_CFG_DIR="$HOME/.config/sketchybar"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
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

YABAI_CFG_DIR="$HOME/.config/yabai"
mkdir -p "$YABAI_CFG_DIR" || {
  echo "✗ agent-hooks install: cannot create $YABAI_CFG_DIR" >&2
  agent_hooks_log install "FATAL mkdir $YABAI_CFG_DIR failed"
  exit 1
}
sync_if_drifted "$REPO_ROOT/yabai/yabairc" "$YABAI_CFG_DIR/yabairc" yabairc || exit 1

YABAI="${YABAI:-$(command -v yabai || echo /opt/homebrew/bin/yabai)}"
if command -v "$YABAI" >/dev/null 2>&1; then
  # A live yabai does not reload the newly deployed signal configuration.
  "$YABAI" -m signal --remove spacetag_window_destroyed 2>/dev/null || true
  "$YABAI" -m signal --add label=spacetag_window_destroyed event=window_destroyed \
    action='sketchybar --trigger window_destroyed WIN=$YABAI_WINDOW_ID' 2>/dev/null || true
  agent_hooks_log install "re-asserted live yabai signal spacetag_window_destroyed"
else
  echo "  warn: yabai not found — window_destroyed signal not registered live" >&2
  agent_hooks_log install "WARN yabai absent; window_destroyed signal not registered live"
fi

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

if command -v "$SKETCHYBAR" >/dev/null 2>&1; then
  "$SKETCHYBAR" --reload >/dev/null 2>&1 || true
  agent_hooks_log install "sketchybar --reload fired"
fi

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
