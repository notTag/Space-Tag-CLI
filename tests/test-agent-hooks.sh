#!/usr/bin/env bash
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

N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="/usr/bin:/bin" agent_hooks_bin yabai)
[ "$got" = "$APP_BIN/yabai" ] && ok || nope "app-yabai" "got '$got', expected '$APP_BIN/yabai'"

N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="/usr/bin:/bin" agent_hooks_bin sketchybar)
[ "$got" = "$APP_BIN/sketchybar" ] && ok || nope "app-sketchybar" "got '$got', expected '$APP_BIN/sketchybar'"

PATHDIR="$WORK/pathbin"; mkdir -p "$PATHDIR"
printf '#!/bin/sh\nexit 0\n' > "$PATHDIR/yabai"; chmod +x "$PATHDIR/yabai"
N=$((N + 1))
got=$(HOME="$FAKE_HOME" PATH="$PATHDIR:/usr/bin:/bin" agent_hooks_bin yabai)
[ "$got" = "$PATHDIR/yabai" ] && ok || nope "path-precedence" "got '$got', expected '$PATHDIR/yabai'"

N=$((N + 1))
EMPTY_HOME="$WORK/emptyhome"; mkdir -p "$EMPTY_HOME"
got=$(HOME="$EMPTY_HOME" PATH="/usr/bin:/bin" AGENT_HOOKS_BIN_DIRS="" agent_hooks_bin yabai)
[ "$got" = "yabai" ] && ok || nope "bare-fallthrough" "got '$got', expected 'yabai'"

printf 'agent-hooks: %d tests, %d assertions, %d failed\n' "$N" "$((PASS + FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
