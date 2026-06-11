#!/bin/sh
# Tag (default action): current/explicit space, validation, failures, -- escapes.
. "$(dirname "$0")/lib.sh"

t "tag labels the current space and fires trigger"
run myproj
assert_status 0; assert_out "space 1 → myproj"
assert_log "yabai label sid=1 value=[myproj]"
assert_log "sketchybar --trigger space_change"

t "tag uses the queried active-space index"
EXTRA="STUB_SPACE_INDEX=4"; run myproj
assert_out "space 4 → myproj"; assert_log "sid=4"

t "tag with explicit space number skips the active-space query"
run myproj 3
assert_status 0; assert_out "space 3 → myproj"
assert_log "yabai label sid=3 value=[myproj]"
assert_no_log "yabai query --spaces"

t "tag rejects a non-numeric space number"
run myproj two; assert_status 1; assert_out "space number must be numeric: two"

t "tag errors when there is no active space"
EXTRA="STUB_NO_SPACE=1"; run myproj
assert_status 1; assert_out "no active space"

t "tag propagates a yabai label failure"
EXTRA="STUB_LABEL_FAIL=1"; run myproj 2; assert_status 1

t "tag accepts a name containing spaces"
run "two words" 2
assert_status 0; assert_out "space 2 → two words"
assert_log "value=[two words]"

t "-- escapes a reserved word as a tag name"
run -- clear 3
assert_status 0; assert_out "space 3 → clear"
assert_log "yabai label sid=3 value=[clear]"

t "-- escapes a dash-leading tag name"
run -- -x; assert_status 0; assert_out "space 1 → -x"

t "bare on/off are tag names, not auto toggles"
run on
assert_status 0; assert_out "space 1 → on"
assert_log "yabai label sid=1 value=[on]"
assert_gone auto-tag

finish
