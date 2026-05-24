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

# ─── local override (gitignored, optional) ──────────────────────────────
LOCAL_THEME="$HOME/.config/sketchybar/theme.local.sh"
[ -f "$LOCAL_THEME" ] && . "$LOCAL_THEME"
