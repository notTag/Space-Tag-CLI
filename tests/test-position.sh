#!/bin/sh
. "$(dirname "$0")/lib.sh"

t "position falls back to center with no state"
run position; assert_status 0; assert_eq "center  (default)"

t "position shows the shared default when no override"
cfg; echo left > "$CFGDIR/position"
run position; assert_eq "left  (default)"

t "position prefers this display's override"
cfg; mkdir -p "$CFGDIR/position.d"
echo left > "$CFGDIR/position"
echo notch-right > "$CFGDIR/position.d/TEST-UUID-1"
run position; assert_eq "notch-right  (this display)"

t "position falls back to default when no active display"
cfg; mkdir -p "$CFGDIR/position.d"
echo notch-right > "$CFGDIR/position.d/TEST-UUID-1"
EXTRA="STUB_NO_DISPLAY=1"; run position
assert_eq "center  (default)"

t "position <mode> persists per display and fires trigger"
run position left
assert_status 0; assert_out "this display (TEST-UUID-1) → left"
assert_file position.d/TEST-UUID-1 left
assert_log "sketchybar --trigger position_change"

t "position <mode> errors when no active display"
EXTRA="STUB_NO_DISPLAY=1"; run position left
assert_status 1; assert_out "no active display"

t "position rejects an invalid mode"
run position middle; assert_status 1; assert_out "usage: space-tag position"

t "position accepts every documented mode"
for m in center notch-left notch-right left right; do
  run position "$m"; assert_status 0
done

t "position default <mode> persists the shared default"
run position default right
assert_status 0; assert_out "default position → right"
assert_file position right
assert_log "sketchybar --trigger position_change"

t "position default rejects an invalid mode"
run position default sideways; assert_status 1; assert_out "usage: space-tag position"

t "position default with no mode is rejected"
run position default; assert_status 1; assert_out "usage: space-tag position"

t "position clear drops this display's override"
cfg; mkdir -p "$CFGDIR/position.d"
echo left > "$CFGDIR/position.d/TEST-UUID-1"
run position clear
assert_status 0; assert_out "this display (TEST-UUID-1) → default"
assert_gone position.d/TEST-UUID-1
assert_log "sketchybar --trigger position_change"

t "position clear errors when no active display"
EXTRA="STUB_NO_DISPLAY=1"; run position clear
assert_status 1; assert_out "no active display"

t "position list shows only the default when no overrides"
run position list; assert_status 0; assert_eq "default      center"

t "position list shows overrides and marks this display"
cfg; mkdir -p "$CFGDIR/position.d"
echo left > "$CFGDIR/position"
echo center > "$CFGDIR/position.d/TEST-UUID-1"
echo right > "$CFGDIR/position.d/OTHER-UUID"
run position list
assert_status 0
assert_out "default      left"
assert_out "TEST-UUID-1  center  <- this display"
assert_out "OTHER-UUID  right"

finish
