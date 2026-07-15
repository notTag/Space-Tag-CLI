#!/bin/sh
. "$(dirname "$0")/lib.sh"

t "display defaults to current with no state file"
run display; assert_status 0; assert_eq "current"

t "display reads a persisted off file as all"
cfg; echo off > "$CFGDIR/per-display-spaces"
run display; assert_eq "all"

t "display current writes 'on' (spaces.sh file contract) and fires trigger"
run display current
assert_status 0; assert_out "display → current"
assert_file per-display-spaces on
assert_log "sketchybar --trigger space_set_change"

t "display all writes 'off' (spaces.sh file contract)"
run display all
assert_status 0; assert_out "display → all"
assert_file per-display-spaces off

t "display rejects a bad value"
run display on; assert_status 1; assert_out "usage: space-tag display [current|all]"

finish
