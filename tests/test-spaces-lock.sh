#!/bin/sh
if [ ! -x /usr/bin/lockf ]; then
  printf 'spaces-lock: 0 tests, 0 assertions, 0 failed (skipped: lockf unavailable)\n'
  exit 0
fi

. "$(dirname "$0")/lib.sh"

SCRIPT="$ROOT/sketchybar/plugins/spaces.sh"

t "spaces reconciliation skips a callback when the lock is held"
LOCK_DIR="$WORK/lock"
mkdir -p "$LOCK_DIR"
/usr/bin/lockf -k "$LOCK_DIR/com.nottag.spacetag.spaces.lock" sleep 1 &
holder=$!
sleep 0.1
OUT=$(env -i HOME="$THOME" TMPDIR="$LOCK_DIR" PATH="$SYS" "$SCRIPT" 2>&1)
ST=$?
wait "$holder"
assert_status 0
assert_eq ""

finish
