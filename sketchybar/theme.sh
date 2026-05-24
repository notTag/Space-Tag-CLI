#!/usr/bin/env bash
# Shared theme + tuning constants. Sourced by sketchybarrc and plugins
# so colors and offsets live in one place. Override locally by copying
# this file to ~/.config/sketchybar/theme.local.sh (untracked) — the
# loader below sources it last so locals win.

# ─── runtime binaries (work on both Apple Silicon and Intel) ─────────────
YABAI="${YABAI:-$(command -v yabai)}"
JQ="${JQ:-$(command -v jq)}"

# ─── color palette (Catppuccin Mocha) ────────────────────────────────────
# Format: 0xAARRGGBB. Alpha byte 00 = transparent, ff = opaque.
COLOR_BAR_BG=0x00000000            # bar background (fully transparent)
COLOR_PILL_BG=0xff313244            # unfocused pill background
COLOR_PILL_FG=0xffcdd6f4            # unfocused pill text/icon
COLOR_PILL_BG_FOCUSED=0xff89b4fa    # focused pill background
COLOR_PILL_FG_FOCUSED=0xff1e1e2e    # focused pill text/icon

# Transparent variants for fade-in (alpha byte = 00).
COLOR_PILL_BG_HIDDEN=0x00313244
COLOR_PILL_FG_HIDDEN=0x00cdd6f4

# ─── geometry ────────────────────────────────────────────────────────────
# Bar height is derived live in plugins/y_offset.sh:
#   • flat displays  → NSStatusBar.system.thickness (matches the OS menu
#     bar; tracks "Larger Text" accessibility)
#   • notched displays → PILL_HEIGHT + 2*NOTCH_GAP (pills centered, so the
#     gap below the notch edge is exactly NOTCH_GAP points)
# BAR_HEIGHT below is only a boot-time fallback for sketchybarrc before
# y_offset.sh has had a chance to run.
BAR_HEIGHT=24
PILL_HEIGHT=25
PILL_CORNER_RADIUS=6

# Padding (points), single source of truth — sketchybarrc and the plugins all
# read these. BAR_PAD = gap from the bar's edge to the outermost pill; it also
# feeds the notch boundary math in plugins/position.sh. PILL_PAD = spacing on
# each side of a pill (gap between adjacent pills).
BAR_PAD=8
PILL_PAD=4

# y_offset for the bar on flat (non-notched) displays. On notched displays
# the bar is pinned to the safe-area edge — NOTCH_GAP tunes the visible
# gap below the notch (negative values pull pills toward the notch).
Y_OFFSET_FLAT=0
NOTCH_GAP=0                         # pill drop below notch (in points)

# notch-left / notch-right layouts: the bar is shrunk to a strip CENTERED on
# the notch (margin only — SketchyBar's x_offset moves the bar's frame but not
# its items, so an off-center strip and its pills would diverge). topmost=on
# then only blocks that centered strip, leaving the native menu bar items on
# both far sides clickable. NOTCH_PILL_ROOM is the space (points) reserved for
# pills on each side of the notch; it sets the strip's half-width via
#   margin = notch_left - NOTCH_PILL_ROOM
# Bigger NOTCH_PILL_ROOM = wider strip = more pill room but LESS clearance from
# the app menus (left) and status cluster (right); smaller = the reverse. Keep
# it ≥ your widest pill-row width. NOTCH_SIDE_GAP is the gap from the notch
# edge to the nearest pill.
NOTCH_PILL_ROOM=330
NOTCH_SIDE_GAP=8

# ─── fonts ───────────────────────────────────────────────────────────────
FONT_ICON="SF Pro:Bold:13.0"
FONT_LABEL="SF Pro:Semibold:13.0"

# ─── animation ───────────────────────────────────────────────────────────
ANIM_CURVE=tanh                     # linear|quadratic|tanh|sin|exp|circ
ANIM_FRAMES_FOCUS=15                # ~250ms space-focus tween
ANIM_FRAMES_DISPLAY_FADE=30         # ~500ms display-switch fade-in

# ─── shared display-geometry probe ───────────────────────────────────────
# Both plugins need the active display's live geometry; the AppKit probe lives
# here so it exists in exactly one place. Echoes a single colon-joined record:
#   <index>:<kind>:<menu_h>:<screen_w>:<notch_left>:<notch_right>
#   • index       — yabai display index (for pinning the bar)
#   • kind        — NOTCH or FLAT
#   • menu_h      — active display's real menu bar height (safe-area top on
#                   notched, NSStatusBar thickness on flat)
#   • screen_w    — display width in points
#   • notch_left  — x of the notch's left edge   (0 on flat)
#   • notch_right — x of the notch's right edge   (0 on flat)
# yabai's has-notch field is unreliable across versions, so we ask AppKit:
# any screen whose safeAreaInsets.top > 0 is notched. Read live every call →
# resolution-dynamic. On failure, fields fall back to a safe FLAT default.
space_labels_probe() {
  local active index dims state
  active=$("$YABAI" -m query --displays --display 2>/dev/null)
  index=$(printf '%s' "$active" | "$JQ" -r '.index' 2>/dev/null)
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
      print("NOTCH:\(safeTop):\(w):\(l):\(r)")
    } else {
      print("FLAT:\(thickness):\(w):0:0")
    }
    exit(0)
  }
}
print("FLAT:\(thickness):0:0:0")
' 2>/dev/null)
  printf '%s:%s\n' "$index" "${state:-FLAT:24:0:0:0}"
}

# ─── local override (gitignored, optional) ──────────────────────────────
LOCAL_THEME="$HOME/.config/sketchybar/theme.local.sh"
[ -f "$LOCAL_THEME" ] && . "$LOCAL_THEME"
