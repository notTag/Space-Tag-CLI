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

# ─── completion flash ─────────────────────
# Per-tool pill flash colors for the agent-completion hook (Phase 01). The
# flash_watcher subscribes to flash_space and animates the SID-targeted pill
# to its TOOL color, then reverts to the theme-correct steady-state color.
COLOR_FLASH_CLAUDE=0xffff8800       # claude — orange
COLOR_FLASH_CODEX=0xffb6a8e8        # codex — periwinkle
COLOR_FLASH_HERMES=0xff8dbf8a       # hermes — sage (locked Task 0)
# Bounded blink: when the agent's space IS the active one, the pill blinks its
# tool color this many times then settles on the focused color. On a NON-active
# space it doesn't blink at all — flash-listener.sh holds the color statically
# (via a pending marker space.sh honors) until that space is focused.
FLASH_COUNT=${FLASH_COUNT:-5}
# Default OFF: always flash even when the user is focused on the agent's space.
# install.sh propagates an override here from ~/.config/spacetag/agent-hooks.yaml
# via env so theme.sh stays the single source of truth at sketchybar source time.
FLASH_FOCUS_SUPPRESS=${FLASH_FOCUS_SUPPRESS:-false}

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

# Flat (non-notched) center mode vertically centers the PILL_HEIGHT pill in
# the real menu bar (matching the native icons). Y_OFFSET_FLAT is a fine-tune
# nudge applied on top of that centered position (+down / -up); 0 = centered.
# On notched displays the bar is pinned to the safe-area edge — NOTCH_GAP
# tunes the visible gap below the notch (negative values pull pills toward it).
Y_OFFSET_FLAT=0
NOTCH_GAP=0                         # pill drop below notch (in points)

# left / right modes drop the pills BELOW the menu bar. With topmost=off macOS
# keeps the native menu bar on top and places our bar just beneath it, so the
# bar's y_offset is simply the gap below the menu bar (it is NOT measured from
# the screen top — that's only true for the topmost=on center/notch modes).
# BELOW_BAR_GAP is that gap on flat displays; notched left/right is pinned to
# its center-mode offset instead.
BELOW_BAR_GAP=2

# Flat center mode: the pill is fit within the OS clip band (clip_h =
# NSStatusBar.thickness, the height macOS clips menu-bar topmost windows to).
# The pill is capped to clip_h minus this inset (top AND bottom) and centered in
# the band, so its rounded bottom never gets clipped — mirroring how the native
# menu bar icons sit with a little breathing room. Bigger = shorter, more inset
# pill. 1 → e.g. a 20pt pill in a 22pt band (1px slack each side).
FLAT_PILL_INSET=1

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

# center mode on a FLAT (non-notched, e.g. external) display has the same
# layering puzzle as the notch strip: pills sit IN the menu bar row, so the bar
# needs topmost=on to paint above it — but a full-width topmost bar eats clicks
# across the WHOLE menu bar, so the native status items become unclickable. Fix
# is the same: shrink the bar to a strip CENTERED on the screen (margin only)
# so topmost=on only blocks the middle, leaving both far sides live. Unlike the
# notch (whose strip is a fixed reserve), the flat strip is sized DYNAMICALLY in
# layout.sh to the live pill-row width — never wider than the pills, so it
# blocks the minimum possible. The only tunable is the edge gap, which reuses
# BAR_PAD (gap from the strip edge to the outermost pill).

# ─── fonts ───────────────────────────────────────────────────────────────
FONT_ICON="SF Pro:Bold:13.0"
FONT_LABEL="SF Pro:Semibold:13.0"

# ─── text alignment within pills ─────────────────────────────────────────
# SketchyBar vertically centers text using the font's full line metrics
# (ascent + descent), which leaves SF/system text sitting a hair off inside the
# pill. These nudge it back to optical center; applied as icon/label y_offset in
# plugins/space.sh. Sign: positive = UP, negative = down.
LABEL_Y_OFFSET=2          # custom-name pills (label text)
ICON_Y_OFFSET=0           # bare space-number pills (icon text)
# Number pills are DYNAMIC width (sized to the digit[s]) — a fixed width can't
# be used, sketchybar packs fixed-width items edge-to-edge and they overlap.

# ─── animation ───────────────────────────────────────────────────────────
ANIM_CURVE=tanh                     # linear|quadratic|tanh|sin|exp|circ
ANIM_FRAMES_FOCUS=15                # ~250ms space-focus tween
ANIM_FRAMES_DISPLAY_FADE=30         # ~500ms display-switch fade-in

# ─── shared display-geometry probe ───────────────────────────────────────
# Both plugins need the active display's live geometry; the AppKit probe lives
# here so it exists in exactly one place. Echoes a single colon-joined record:
#   <index>:<kind>:<menu_h>:<screen_w>:<notch_left>:<notch_right>:<clip_h>:<uuid>
#   • index       — yabai display index (for pinning the bar)
#   • kind        — NOTCH or FLAT
#   • menu_h      — active display's real menu bar height (safe-area top on
#                   notched; frame.maxY - visibleFrame.maxY on flat, because
#                   NSStatusBar.thickness under-reports it on some displays)
#   • screen_w    — display width in points
#   • notch_left  — x of the notch's left edge   (0 on flat)
#   • notch_right — x of the notch's right edge   (0 on flat)
#   • clip_h      — NSStatusBar.thickness: the band macOS clips menu-bar topmost
#                   windows to. On scaled displays this is LESS than menu_h, so
#                   flat center fits the pill within clip_h to avoid bottom-crop.
#   • uuid        — display's stable UUID (survives reconnect / re-arrange,
#                   unlike index) — the key for per-display layout overrides.
#                   Last field so the fixed leading fields always parse.
# yabai's has-notch field is unreliable across versions, so we ask AppKit:
# any screen whose safeAreaInsets.top > 0 is notched. Read live every call →
# resolution-dynamic. On failure, fields fall back to a safe FLAT default.
space_labels_probe() {
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
      // NSStatusBar.thickness UNDER-reports the real menu bar on some displays
      // (e.g. 22 vs an actual 30 on scaled ultrawides). The true height is the
      // gap visibleFrame leaves at the top: frame.maxY - visibleFrame.maxY.
      // Fall back to thickness if that comes out non-positive (fullscreen app).
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

# ─── local override (gitignored, optional) ──────────────────────────────
LOCAL_THEME="$HOME/.config/sketchybar/theme.local.sh"
[ -f "$LOCAL_THEME" ] && . "$LOCAL_THEME"
