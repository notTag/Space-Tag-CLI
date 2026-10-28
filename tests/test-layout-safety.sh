#!/bin/sh
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
OUT=$(env -i SPACETAG_SPACES_LOCKED=1 HOME="$THOME" PATH="$PATH_ALL" STUB_LOG="$LOG" JQ="$REAL_JQ" "$LAYOUT" 2>&1)
ST=$?
assert_status 0
assert_log "sketchybar --bar topmost=off"

t "startup stays hidden until layout is ready"
if sed -n '1,35p' "$RC" | grep -q 'hidden=on'; then ok; else nope "bar starts visible"; fi

t "ready layout reveals only after placement and prepares expansion"
cfg
cat > "$CFGDIR/theme.sh" <<EOF
. "$ROOT/sketchybar/theme.sh"
space_tag_probe() { printf '1:FLAT:30:1440:0:0:22:display-1'; }
EOF
mkdir -p "$WORK/layout-bin"
cat > "$WORK/layout-bin/sketchybar" <<'EOF'
#!/bin/sh
echo "sketchybar $*" >> "$STUB_LOG"
if [ "$1" = --query ]; then
  case "$2" in
    bar) echo '{"items":["space.1","space.2"]}' ;;
    *) printf '{"bounding_rects":{"1":{"size":[%s,22],"origin":[640,0]}}}\n' "${STUB_ITEM_WIDTH:-80}" ;;
  esac
fi
EOF
chmod +x "$WORK/layout-bin/sketchybar"
OUT=$(env -i SPACETAG_SPACES_LOCKED=1 HOME="$THOME" PATH="$WORK/layout-bin:$PATH_ALL" STUB_LOG="$LOG" JQ="$REAL_JQ" "$LAYOUT" 2>&1)
ST=$?
assert_status 0
assert_log "height=16"
assert_log "y_offset=7"
assert_log "background.height=1"
assert_log "padding_left=0 padding_right=0"
assert_log "--bar hidden=off"
if awk '/background.height=1/{prepared=1} /--bar hidden=off/ && prepared {revealed=1} END {if (!revealed) exit 1}' "$LOG"; then ok; else nope "missing prepared reveal"; fi

READY_THEME="$CFGDIR/theme.sh"
t "unmeasured items stay hidden and do not start the reveal animation"
cfg
cp "$READY_THEME" "$CFGDIR/theme.sh"
OUT=$(env -i SPACETAG_SPACES_LOCKED=1 HOME="$THOME" PATH="$WORK/layout-bin:$PATH_ALL" STUB_LOG="$LOG" \
  JQ="$REAL_JQ" STUB_ITEM_WIDTH=0 "$LAYOUT" 2>&1)
ST=$?
assert_status 0
assert_log "--bar hidden=on"
assert_no_log "--animate"

finish
