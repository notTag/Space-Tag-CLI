#!/usr/bin/env bash

YABAI="${YABAI:-$(command -v yabai)}"
JQ="${JQ:-$(command -v jq)}"

COLOR_BAR_BG=0x00000000
COLOR_PILL_BG=0xff313244
COLOR_PILL_FG=0xffcdd6f4
COLOR_PILL_BG_FOCUSED=0xff89b4fa
COLOR_PILL_FG_FOCUSED=0xff1e1e2e

COLOR_PILL_BG_HIDDEN=0x00313244
COLOR_PILL_FG_HIDDEN=0x00cdd6f4

COLOR_FLASH_CLAUDE=0xffff8800
COLOR_FLASH_CODEX=0xffb6a8e8
COLOR_FLASH_HERMES=0xff8dbf8a
FLASH_COUNT=${FLASH_COUNT:-5}
FLASH_FOCUS_SUPPRESS=${FLASH_FOCUS_SUPPRESS:-false}

BAR_HEIGHT=24
PILL_HEIGHT=25
PILL_CORNER_RADIUS=6

BAR_PAD=8
PILL_PAD=4

Y_OFFSET_FLAT=0
NOTCH_GAP=0

BELOW_BAR_GAP=2

FLAT_PILL_INSET=1

NOTCH_PILL_ROOM=330
NOTCH_SIDE_GAP=8


FONT_ICON="SF Pro:Bold:13.0"
FONT_LABEL="SF Pro:Semibold:13.0"

LABEL_Y_OFFSET=2
ICON_Y_OFFSET=0

ANIM_CURVE=tanh
ANIM_FRAMES_FOCUS=15
ANIM_FRAMES_DISPLAY_FADE=30

space_tag_probe() {
  local active index dims state uuid
  active=$("$YABAI" -m query --displays --display 2>/dev/null)
  index=$(printf '%s' "$active" | "$JQ" -r '.index' 2>/dev/null)
  uuid=$(printf '%s' "$active"  | "$JQ" -r '.uuid // empty' 2>/dev/null)
  dims=$(printf '%s' "$active"  | "$JQ" -r '"\(.frame.w|floor)x\(.frame.h|floor)"' 2>/dev/null)
  state=$(TARGET="$dims" /usr/bin/swift -e '
import AppKit
let target = ProcessInfo.processInfo.environment["TARGET"] ?? ""
let thickness = Int(NSStatusBar.system.thickness)
for s in NSScreen.screens {
  let w = Int(s.frame.size.width)
  if "\(w)x\(Int(s.frame.size.height))" == target {
    let safeTop = Int(s.safeAreaInsets.top)
    if safeTop > 0 {
      let l = Int((s.auxiliaryTopLeftArea  ?? .zero).size.width)
      let r = Int(CGFloat(w) - (s.auxiliaryTopRightArea ?? .zero).size.width)
      print("NOTCH:\(safeTop):\(w):\(l):\(r):\(thickness)")
    } else {
      // NSStatusBar.thickness under-reports some scaled displays.
      let menuReal = Int(s.frame.maxY - s.visibleFrame.maxY)
      let menuH = menuReal > 0 ? menuReal : thickness
      print("FLAT:\(menuH):\(w):0:0:\(thickness)")
    }
    exit(0)
  }
}
print("FLAT:\(thickness):0:0:0:\(thickness)")
' 2>/dev/null)
  printf '%s:%s:%s\n' "$index" "${state:-FLAT:24:0:0:0:22}" "$uuid"
}

LOCAL_THEME="$HOME/.config/sketchybar/theme.local.sh"
[ -f "$LOCAL_THEME" ] && . "$LOCAL_THEME"
