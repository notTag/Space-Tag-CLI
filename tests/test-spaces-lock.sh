#!/bin/sh
if [ ! -x /usr/bin/lockf ]; then
  printf 'spaces-lock: 0 tests, 0 assertions, 0 failed (skipped: lockf unavailable)\n'
  exit 0
fi

. "$(dirname "$0")/lib.sh"

SCRIPT="$ROOT/sketchybar/plugins/spaces.sh"

t "spaces reconciliation waits for a busy lock rather than dropping the event"
cfg
printf '. "%s/sketchybar/theme.sh"\n' "$ROOT" > "$CFGDIR/theme.sh"
LOCK_DIR="$WORK/lock"
mkdir -p "$LOCK_DIR"
/usr/bin/lockf -k "$LOCK_DIR/com.nottag.spacetag.spaces.lock" sleep 1 &
holder=$!
sleep 0.1
OUT=$(env -i HOME="$THOME" TMPDIR="$LOCK_DIR" PATH="$PATH_ALL" STUB_LOG="$LOG" "$SCRIPT" 2>&1)
ST=$?
wait "$holder"
assert_status 0
assert_eq ""
assert_log "yabai query --spaces"

t "all label refreshes survive concurrent callbacks behind a held layout lock"
cfg
printf '. "%s/sketchybar/theme.sh"\n' "$ROOT" > "$CFGDIR/theme.sh"
mkdir -p "$WORK/render-bin" "$WORK/render-lock"
cat > "$WORK/render-bin/yabai" <<'EOF'
#!/bin/sh
printf '{"index":%s,"label":"Renamed %s","has-focus":false}\n' "$5" "$5"
EOF
chmod +x "$WORK/render-bin/yabai"
# Hold the same lock as layout until every callback has been started.
/usr/bin/lockf -k "$WORK/render-lock/com.nottag.spacetag.spaces.lock" sh -c 'touch "$1"; sleep 1' sh "$WORK/lock-ready" &
holder=$!
while [ ! -f "$WORK/lock-ready" ]; do sleep 0.01; done
pids=""
for sid in 1 2 3 4; do
  env -i HOME="$THOME" TMPDIR="$WORK/render-lock" PATH="$WORK/render-bin:$PATH_ALL" STUB_LOG="$LOG" \
    NAME="space.$sid" "$ROOT/sketchybar/plugins/space.sh" >"$WORK/render-$sid.out" 2>&1 &
  pids="$pids $!"
done
for pid in $pids; do
  if wait "$pid"; then ok; else nope "render callback failed"; fi
done
wait "$holder"
for sid in 1 2 3 4; do
  assert_log "--set space.$sid icon=$sid icon.drawing=off"
  assert_log "label=Renamed $sid"
done

finish
