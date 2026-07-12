#!/bin/sh
# Native menu-bar clicks must survive startup when yabai is unavailable.

. "$(dirname "$0")/lib.sh"

LAYOUT="$ROOT/sketchybar/plugins/layout.sh"
RC="$ROOT/sketchybar/sketchybarrc"

t "bar boots below the native menu bar"
if sed -n '1,35p' "$RC" | grep -q 'topmost=off'; then
  ok
else
  nope "initial bar configuration is not topmost=off"
fi

t "failed display probe demotes the overlay"
cfg
printf '%s\n' "space_tag_probe() { printf ':FLAT:24:0:0:0:22:'; }" > "$CFGDIR/theme.sh"
OUT=$(env -i HOME="$THOME" PATH="$PATH_ALL" STUB_LOG="$LOG" JQ="$REAL_JQ" "$LAYOUT" 2>&1)
ST=$?
assert_status 0
assert_log "sketchybar --bar topmost=off"

finish
