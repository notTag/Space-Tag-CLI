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
BAR_HEIGHT=24                       # native macOS menu bar is ~24pt (flat)
PILL_HEIGHT=20
PILL_CORNER_RADIUS=6

# y_offset for the bar so pills sit inside the native menu bar.
# Notched MBPs have a taller (~37pt) menu bar; flat displays ~24pt.
Y_OFFSET_FLAT=-20
Y_OFFSET_NOTCH=0

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
