#!/bin/sh
# Clear: empties the current space's tag.
. "$(dirname "$0")/lib.sh"

t "clear empties the current space's label"
run clear
assert_status 0; assert_out "space 1 → (cleared)"
assert_log "yabai label sid=1 value=[]"
assert_log "sketchybar --trigger space_change"

t "clear errors when there is no active space"
EXTRA="STUB_NO_SPACE=1"; run clear
assert_status 1; assert_out "no active space"

t "clear propagates a yabai failure"
EXTRA="STUB_LABEL_FAIL=1"; run clear; assert_status 1

finish
