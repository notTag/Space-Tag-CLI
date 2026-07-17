#!/bin/sh
. "$(dirname "$0")/lib.sh"

t "uninstall dry-run stops services and removes the CLI"
mkdir -p "$THOME/.local/bin"
: > "$THOME/.local/bin/space-tag"
run uninstall --dry-run
assert_status 0
assert_out "[dry-run] yabai --stop-service"
assert_out "[dry-run] brew services stop sketchybar"
assert_out "[dry-run] rm -rf $THOME/.local/bin/space-tag"
assert_out "dry run complete — nothing was removed."

t "uninstall forwards keep-brew"
run uninstall --dry-run --keep-brew
assert_status 0
assert_out "keeping brew packages"
assert_no_out "brew uninstall sketchybar"
assert_no_out "brew uninstall yabai"

t "uninstall rejects unknown flags"
run uninstall --bogus
assert_status 2
assert_out "unknown flag: --bogus"

finish
