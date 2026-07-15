#!/bin/sh
. "$(dirname "$0")/lib.sh"

t "auto defaults to on with no state file"
run auto; assert_status 0; assert_eq "on"

t "auto reads persisted off"
cfg; echo off > "$CFGDIR/auto-tag"
run auto; assert_eq "off"

t "auto reads persisted on"
cfg; echo on > "$CFGDIR/auto-tag"
run auto; assert_eq "on"

t "auto falls back to the legacy auto-label file"
cfg; echo off > "$CFGDIR/auto-label"
run auto; assert_eq "off"

t "auto-tag file wins over the legacy file"
cfg; echo on > "$CFGDIR/auto-tag"; echo off > "$CFGDIR/auto-label"
run auto; assert_eq "on"

t "auto on persists state"
run auto on
assert_status 0; assert_out "auto-tag → on"; assert_file auto-tag on

t "auto off persists state"
run auto off
assert_status 0; assert_out "auto-tag → off"; assert_file auto-tag off

t "auto rejects a bad value"
run auto maybe; assert_status 1; assert_out "usage: space-tag auto [on|off]"

finish
