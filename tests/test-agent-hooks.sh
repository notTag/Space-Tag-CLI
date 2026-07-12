#!/usr/bin/env bash
# tests/test-agent-hooks.sh — guards the agent-hooks runtime binary resolver
# (state.sh:agent_hooks_bin). Regression cover for bug-003: on a SpaceTag *app*
# install, yabai / sketchybar are bundled inside SpaceTag.app and never placed
# on PATH, so the hooks (spawned by Claude / Codex / Hermes with a minimal env)
# could not find them and no completion flash fired. agent_hooks_bin must fall
# back to the sketchybar LaunchAgent plist — the app's source of truth — when
# command -v comes up empty.
#
# Self-contained: sources state.sh directly, uses the real /usr/libexec/PlistBuddy
# against a throwaway plist in a temp HOME. Prints the run.sh summary line.

set -u

if [ ! -x /usr/libexec/PlistBuddy ]; then
  printf 'agent-hooks: 0 tests, 0 assertions, 0 failed (skipped: PlistBuddy unavailable)\n'
  exit 0
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STATE_SH="$ROOT/sketchybar/plugins/agent-hooks/state.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=/dev/null
. "$STATE_SH"

PASS=0; FAIL=0; N=0
ok()   { PASS=$((PASS + 1)); }
nope() { FAIL=$((FAIL + 1)); printf 'FAIL %s — %s\n' "$1" "$2"; }

# A throwaway HOME carrying a fake sketchybar LaunchAgent plist that points at
# bundled stub binaries — mirrors a real SpaceTag.app install.
APP_BIN="$WORK/app/Contents/Resources/bin"
mkdir -p "$APP_BIN"
printf '#!/bin/sh\nexit 0\n' > "$APP_BIN/yabai";      chmod +x "$APP_BIN/yabai"
printf '#!/bin/sh\nexit 0\n' > "$APP_BIN/sketchybar"; chmod +x "$APP_BIN/sketchybar"
printf '#!/bin/sh\nexit 0\n' > "$APP_BIN/jq";         chmod +x "$APP_BIN/jq"

FAKE_HOME="$WORK/home"
mkdir -p "$FAKE_HOME/Library/LaunchAgents"
cat > "$FAKE_HOME/Library/LaunchAgents/com.nottag.spacetag.sketchybar.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>EnvironmentVariables</key><dict>
    <key>JQ</key><string>$APP_BIN/jq</string>
    <key>YABAI</key><string>$APP_BIN/yabai</string>
  </dict>
  <key>ProgramArguments</key><array><string>$APP_BIN/sketchybar</string></array>
</dict></plist>
EOF

# ── 1. App install: yabai NOT on PATH → resolved from the LaunchAgent plist ──
N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="/usr/bin:/bin" agent_hooks_bin yabai)
[ "$got" = "$APP_BIN/yabai" ] && ok || nope "app-yabai" "got '$got', expected '$APP_BIN/yabai'"

N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="/usr/bin:/bin" agent_hooks_bin sketchybar)
[ "$got" = "$APP_BIN/sketchybar" ] && ok || nope "app-sketchybar" "got '$got', expected '$APP_BIN/sketchybar'"

# ── 2. PATH wins over the plist when the binary is directly available ────────
PATHDIR="$WORK/pathbin"; mkdir -p "$PATHDIR"
printf '#!/bin/sh\nexit 0\n' > "$PATHDIR/yabai"; chmod +x "$PATHDIR/yabai"
N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="$PATHDIR:/usr/bin:/bin" agent_hooks_bin yabai)
[ "$got" = "$PATHDIR/yabai" ] && ok || nope "path-precedence" "got '$got', expected '$PATHDIR/yabai'"

# ── 3. No PATH hit and no plist → falls through to the bare name (loud fail) ─
N=$((N + 1))
EMPTY_HOME="$WORK/emptyhome"; mkdir -p "$EMPTY_HOME"
got=$(HOME="$EMPTY_HOME" PATH="/usr/bin:/bin" agent_hooks_bin yabai)
[ "$got" = "yabai" ] && ok || nope "bare-fallthrough" "got '$got', expected 'yabai'"

printf 'agent-hooks: %d tests, %d assertions, %d failed\n' "$N" "$((PASS + FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
