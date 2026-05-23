# space-labels

Rename macOS spaces on the fly from the shell. No reboot, no SIP changes.
Pills render inside the native menu bar, follow the focused display, and
fade in on display switches.

<img width="374" height="39" alt="Screenshot 2026-05-22 at 7 55 44 PM" src="https://github.com/user-attachments/assets/c5465dbd-9275-4cf7-9ac4-7543e5c00fc1" />

[Usage](#usage) | [Install](#install) | [Requirements](#requirements) | [What it does](#what-it-does) | [Layout](#layout)
[Customization](#customization) | [Multi-display behavior](#multi-display-behavior) | [SIP / security posture](#sip--security-posture) | [License](#license)

## Usage

- `space-label nagamaki` → manually label the current space
- `cd ~/code/foo` → active space labeled `foo` automatically
- `space-unlabel` → clear the current space's label

## Install

```sh
./install.sh
yabai --start-service
brew services start sketchybar
exec zsh
```

The installer:
- Verifies prerequisites (`yabai`, `sketchybar`, `jq`, `swift`)
- Symlinks configs into `~/.config/{yabai,sketchybar}/`
- Appends a single `source` line to `~/.zshrc` for the chpwd hook

## Requirements

- macOS (Apple Silicon or Intel)
- Homebrew packages: `yabai`, `sketchybar`, `jq`
- `swift` (ships with Xcode Command Line Tools — `xcode-select --install`)
- zsh

```sh
brew install yabai sketchybar jq
xcode-select --install   # if not already
```

## What it does

- yabai stores a label per space (`yabai -m space --label foo`).
- sketchybar renders one transparent pill per space, overlaid on the
  native macOS menu bar.
- The bar pins to the focused display (single instance, no duplication
  across screens) and auto-adjusts `y_offset` for notched MBPs vs flat
  externals.
- A zsh `chpwd` hook auto-labels the active space with the current git
  project name when you `cd` into a repo.

Mission Control itself still shows "Desktop N" — Apple's renderer ignores
yabai labels. The labels live in the sketchybar pills instead.

## Layout

```
space-labels/
├── yabai/yabairc                       # yabai daemon config (float layout)
├── sketchybar/
│   ├── sketchybarrc                    # bar definition + per-space pills
│   ├── theme.sh                        # colors, geometry, fonts, animation
│   └── plugins/
│       ├── space.sh                    # renders one pill, fades on focus change
│       ├── clock.sh                    # right-side clock (optional)
│       └── y_offset.sh                 # pins bar to active display + fade-in
├── zsh/space-label.zsh                 # chpwd hook + space-label/space-unlabel fns
├── install.sh                          # idempotent symlinker
└── README.md
```

## Customization

All colors, geometry, fonts, and animation timing live in
`sketchybar/theme.sh`. To override without editing the tracked file:

```sh
cp ~/.config/sketchybar/theme.sh ~/.config/sketchybar/theme.local.sh
# edit theme.local.sh — it's sourced last, so locals win
brew services restart sketchybar
```

Common knobs:
- `COLOR_PILL_BG_FOCUSED` / `COLOR_PILL_FG_FOCUSED` — accent palette
- `Y_OFFSET_FLAT` / `Y_OFFSET_NOTCH` — vertical pill alignment per display type
- `ANIM_FRAMES_FOCUS` (default 15) — fade duration on space switch (~250ms)
- `ANIM_FRAMES_DISPLAY_FADE` (default 30) — fade-in when bar moves displays
- `BAR_HEIGHT` — change if you've enabled macOS "Larger Text" accessibility

## Multi-display behavior

The bar pins to the focused display. On `display_change`, `y_offset.sh`:
1. Snaps all pills to fully transparent (instant)
2. Moves the bar to the new display with the correct notch-aware `y_offset`
3. Animates pills back to their target colors

The notch detection uses a tiny Swift one-liner to read
`NSScreen.safeAreaInsets.top` (any non-zero value = notched). yabai's
`has-notch` field is unreliable across versions and is not used.

## SIP / security posture

Uses yabai for labels and queries only — no scripting addition,
no `--load-sa`, no SIP changes. Apple Silicon hardened runtime stays
intact.

## License

MIT — see [LICENSE](LICENSE).
