#!/bin/sh
. "$(dirname "$0")/lib.sh"

t "autotag honors SPACE_TAG_AUTO=off"
EXTRA="SPACE_TAG_AUTO=off STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0; assert_no_log "yabai"

t "autotag honors persisted off state"
cfg; echo off > "$CFGDIR/auto-tag"
EXTRA="STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0; assert_no_log "yabai"

t "autotag honors legacy auto-label off state"
cfg; echo off > "$CFGDIR/auto-label"
EXTRA="STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0; assert_no_log "yabai"

t "autotag SPACE_TAG_AUTO=on overrides persisted off"
cfg; echo off > "$CFGDIR/auto-tag"
EXTRA="SPACE_TAG_AUTO=on STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0; assert_log "yabai label sid=1 value=[widget]"

t "autotag tags the active space with the repo basename"
EXTRA="STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0
assert_log "yabai label sid=1 value=[widget]"
assert_log "sketchybar --trigger space_change"

t "autotag is a silent no-op outside a git repo"
run __autotag
assert_status 0; assert_eq ""; assert_no_log "yabai label"

t "autotag exits 0 when there is no active space"
EXTRA="STUB_GIT_ROOT=/repos/widget STUB_NO_SPACE=1"; run __autotag
assert_status 0; assert_no_log "yabai label"

t "autotag exits 0 when yabai is missing"
USE_PATH="$PATH_NOYABAI"
EXTRA="STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0

t "autotag exits 0 when jq is missing"
USE_PATH="$PATH_NOJQ"
EXTRA="STUB_GIT_ROOT=/repos/widget"; run __autotag
assert_status 0

t "autotag exits 0 even when the label write fails"
EXTRA="STUB_GIT_ROOT=/repos/widget STUB_LABEL_FAIL=1"; run __autotag
assert_status 0

finish
