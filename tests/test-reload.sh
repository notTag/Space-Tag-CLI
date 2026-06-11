#!/bin/sh
# Reload: sketchybar --reload wrapper.
. "$(dirname "$0")/lib.sh"

t "reload invokes sketchybar --reload"
run reload
assert_status 0; assert_out "sketchybar reloaded"
assert_log "sketchybar --reload"

t "reload propagates a sketchybar failure"
EXTRA="STUB_SKETCHYBAR_FAIL=1"; run reload; assert_status 1

t "reload errors when sketchybar is not installed"
USE_PATH="$PATH_NOSKETCHYBAR"; run reload
assert_status 1; assert_out "sketchybar not found"

finish
