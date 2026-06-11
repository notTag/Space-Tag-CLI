# Space-Tag-CLI

Rename macOS spaces on the fly from the shell. No reboot, no SIP changes.
Pills render inside the native menu bar, follow the focused display, and
fade in on display switches.

<img width="374" height="39" alt="Screenshot 2026-05-22 at 7 55 44 PM" src="https://github.com/user-attachments/assets/c5465dbd-9275-4cf7-9ac4-7543e5c00fc1" />

[Usage](#usage) | [Install](#install) | [Requirements](#requirements) | [What it does](#what-it-does) | [Layout](#layout)
[Customization](#customization) | [Multi-display behavior](#multi-display-behavior) | [SIP / security posture](#sip--security-posture) | [License](#license)

## Usage

- **Right-click a pill** → it turns into an editable text box in place (no menu). Type a name, then press Enter or click away to save; Escape cancels. Clearing the text reverts the pill to its space number. (Left-click still focuses the space.)
- `space-tag nagamaki` → manually tag the current space
- `space-tag nagamaki 2` → tag space 2 regardless of which is active
- `cd ~/code/foo` → active space tagged `foo` automatically
- `space-tag clear` → clear the current space's tag
- `space-tag auto off` → stop auto-tagging on `cd` (persists; `on` re-enables, no arg prints state)
- `space-tag display all` → show every space across all displays (persists; `current` restores the default — see [Multi-display behavior](#multi-display-behavior); no arg prints state)
- `space-tag position <mode>` → set pill placement **for the focused display** (persisted per display; no arg prints this display's mode)
  - `space-tag position default <mode>` → set the fallback for displays without their own setting
  - `space-tag position clear` → drop this display's setting (fall back to the default)
  - `space-tag position list` → show the default and every per-display override
- `space-tag -- <name>` → tag with a literal name that collides with a subcommand (e.g. a space named `clear`)
- `space-tag reload` → reload sketchybar after config/theme edits (wraps `sketchybar --reload`)
- `space-tag source` → reload your shell (`exec $SHELL`) to pick up hook changes
- `space-tag help` → full usage

Everything is one standalone POSIX script (`bin/space-tag`) — callable from any
shell, keybinding, or script. Only auto-tag-on-`cd` needs shell integration,
via thin hooks in `shell/` (zsh and bash provided).

For a one-off override without changing the persisted state, export
`SPACE_TAG_AUTO=off` in the current shell — it wins over `space-tag auto`.

Positions:

| Mode          | Placement                                          |
|---------------|----------------------------------------------------|
| `center`      | Inside the menu bar, centered (default)            |
| `notch-left`  | Inside the menu bar, flush left of the notch (2pt) |
| `notch-right` | Inside the menu bar, flush right of the notch (2pt)|
| `left`        | Below the menu bar, left edge (2pt gap)            |
| `right`       | Below the menu bar, right edge (2pt gap)           |

On flat (non-notched) displays there's no notch to anchor against, so
`notch-left` / `notch-right` fall back to `left` / `right` (pills drop just
below the menu bar at that edge).

**Layout is remembered per display.** Each physical display is keyed by its
stable UUID, so a notched laptop can stay on `notch-right` while an external
stays on `center` — plug/unplug and each display keeps its own placement, no
re-toggling. Displays without a setting use the default.

## Install

```sh
./install.sh
yabai --start-service
brew services start sketchybar
exec $SHELL
```

The installer:
- Verifies prerequisites (`yabai`, `sketchybar`, `jq`, `swift`)
- Symlinks configs into `~/.config/{yabai,sketchybar}/`
- Symlinks `bin/space-tag` into `~/.local/bin/` (warns if that's not on `PATH`)
- Appends a single `source` line to `~/.zshrc` (and `~/.bashrc` if present) for the auto-tag hook

## Requirements

- macOS (Apple Silicon or Intel)
- Homebrew packages: `yabai`, `sketchybar`, `jq`
- `swift` (ships with Xcode Command Line Tools — `xcode-select --install`)
- Any POSIX shell. Auto-tag-on-`cd` hooks ship for zsh and bash; other shells
  can call `space-tag __autotag` from their own cd hook.

```sh
brew install yabai sketchybar jq
xcode-select --install   # if not already
```

## What it does

- yabai stores a tag per space under the hood (`yabai -m space --label foo`).
- sketchybar renders one transparent pill per space, overlaid on the
  native macOS menu bar.
- The bar pins to the focused display (single instance, no duplication
  across screens) and auto-adjusts `y_offset` for notched MBPs vs flat
  externals.
- A shell hook (zsh `chpwd` / bash `PROMPT_COMMAND`) auto-tags the active
  space with the current git project name when you `cd` into a repo.

Mission Control itself still shows "Desktop N" — Apple's renderer ignores
yabai's labels. The tags live in the sketchybar pills instead.

## Layout

```
Space-Tag-CLI/
├── yabai/yabairc                       # yabai daemon config (float layout)
├── sketchybar/
│   ├── sketchybarrc                    # bar definition + per-space pills
│   ├── theme.sh                        # colors, geometry, fonts, animation
│   └── plugins/
│       ├── space.sh                    # renders one pill, fades on focus change
│       ├── spaces.sh                   # reconciles the pill set with live yabai spaces
│       ├── layout.sh                   # pins bar to active display + lays out pills
│       ├── space_click.sh              # click dispatcher: left=focus, right=rename
│       ├── rename-overlay.swift        # inline editable text field over a pill
│       └── clock.sh                    # right-side clock (optional)
├── bin/space-tag                       # standalone CLI: tag/clear/auto/display/position
├── shell/
│   ├── space-tag.zsh                   # zsh chpwd hook → space-tag __autotag
│   └── space-tag.bash                  # bash PROMPT_COMMAND hook → space-tag __autotag
├── install.sh                          # idempotent symlinker
└── README.md
```

## Customization

All colors, geometry, fonts, and animation timing live in
`sketchybar/theme.sh`. To override without editing the tracked file:

```sh
cp ~/.config/sketchybar/theme.sh ~/.config/sketchybar/theme.local.sh
# edit theme.local.sh — it's sourced last, so locals win
space-tag reload
```

Common knobs:
- `COLOR_PILL_BG_FOCUSED` / `COLOR_PILL_FG_FOCUSED` — accent palette
- `Y_OFFSET_FLAT` / `Y_OFFSET_NOTCH` — vertical pill alignment per display type
- `ANIM_FRAMES_FOCUS` (default 15) — fade duration on space switch (~250ms)
- `ANIM_FRAMES_DISPLAY_FADE` (default 30) — fade-in when bar moves displays
- `BAR_HEIGHT` — change if you've enabled macOS "Larger Text" accessibility

## Multi-display behavior

**Per-display spaces (default on).** macOS treats each display as owning its own
set of spaces ("Displays have separate Spaces"). To match that, the bar shows
**only the focused display's spaces** — plug in an external monitor and the
laptop's spaces no longer ride along beside it. Moving focus between displays
swaps the pill set to that display's spaces. Run `space-tag display all` to show
every space across all displays instead (persists; `current` restores the default).
With a single display this is a no-op — every space already lives on it.

The bar pins to the focused display. On `display_change`, `layout.sh`:
1. Snaps all pills to fully transparent (instant)
2. Moves and sizes the bar for the focused display's layout mode
3. Re-anchors the space pills and animates them back to their target colors

The notch detection uses a tiny Swift one-liner to read
`NSScreen.safeAreaInsets.top` (any non-zero value = notched). yabai's
`has-notch` field is unreliable across versions and is not used.

Layout mode is stored per display (keyed by the display's stable UUID), so
each screen remembers its own `space-tag position`; the bar applies the focused
display's mode on every `display_change`.

## Agent completion flash

When an AI agent (Claude Code, Codex, or Hermes Agent) finishes a turn, the
pill for the space hosting that agent's terminal briefly flashes a per-tool
color. The flash follows the **window**, not the focused space — drag the
agent's terminal to a different space mid-session and the flash hits the new
space. Hooks fire at session start (to capture the yabai window id) and at
turn end (to resolve that window's current space and animate the pill).

### Install

```sh
./sketchybar/plugins/agent-hooks/install.sh
```

The installer detects which agents are present (`~/.claude/settings.json`,
`~/.codex/hooks.json`, `~/.hermes/config.yaml`) and wires only those. It
backs each config up to `~/Library/Application Support/spacetag/backups/`
before any modification, and re-running is idempotent.

### Colors

Defaults live in `sketchybar/theme.sh`:

| Tool         | Color      | Hex          |
|--------------|------------|--------------|
| Claude Code  | orange     | `0xffff8800` |
| Codex        | periwinkle | `0xffb6a8e8` |
| Hermes Agent | sage       | `0xff8dbf8a` |

Override locally by setting `COLOR_FLASH_CLAUDE`, `COLOR_FLASH_CODEX`, or
`COLOR_FLASH_HERMES` in `~/.config/sketchybar/theme.local.sh`.

### Focus-suppress

By default the pill flashes on every turn end, including when you're already
focused on that space. To suppress flashes on the focused space, set
`FLASH_FOCUS_SUPPRESS=true` somewhere the hook process tree will pick it up.
Easiest: add it to `~/.config/sketchybar/theme.local.sh`. Exporting in your
interactive shell does NOT propagate to already-running agent processes.

### Per-tool notes

- **Codex** — first turn after install may prompt for trust on the new hooks
  (codex sandboxes shell hooks via SHA-256 trust hashes). Allow them to proceed.
- **Hermes** — first interactive invocation will prompt once to allowlist the
  new hooks. Bypass with `hermes --accept-hooks`, `HERMES_ACCEPT_HOOKS=1`, or
  `hooks_auto_accept: true` in `~/.hermes/config.yaml`.

### Diagnose

```sh
./sketchybar/plugins/agent-hooks/doctor.sh
```

Reports per-tool install state, deployed script presence, sketchybar item
registration, state-dir counts, and the recent forensic log tail. Exits 0
when healthy, 1 otherwise.

### Uninstall

```sh
./sketchybar/plugins/agent-hooks/uninstall.sh
```

Restores each tool's config file byte-for-byte from the dated backup. Pass
`--keep-scripts` to leave the deployed runtime in place.

See `.planning/phases/01-completion-flash/01-PLAN.md` for the architecture
rationale (PPID-walk + SessionStart-captured yabai window id + sketchybar
custom event), and the spike READMEs under `.planning/spikes/` for the
end-to-end loop proof and cross-tool hook-schema parity finding.

## SIP / security posture

Uses yabai for labels and queries only — no scripting addition,
no `--load-sa`, no SIP changes. Apple Silicon hardened runtime stays
intact.

## License

MIT — see [LICENSE](LICENSE).
