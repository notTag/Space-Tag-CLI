# Knobs

Everything you can tune in Space-Tag-CLI, grouped by where it lives and whether
it's a **runtime command** (change on the fly) or an **edit-and-reload constant**
(edit `sketchybar/theme.sh` or copy it to `~/.config/sketchybar/theme.local.sh`,
then `space-tag reload`).

---

## 1. Layout / pill position — runtime

Set with `space-tag position`. Persists per display to
`~/.config/sketchybar/position.d/<uuid>` (shared default in
`~/.config/sketchybar/position`) and reflows immediately (fires `position_change`).

```
space-tag position                 # print this display's effective mode
space-tag position center          # in the menu bar, centered (default)
space-tag position notch-left      # flush to the LEFT of the notch, in the menu bar row
space-tag position notch-right     # flush to the RIGHT of the notch, in the menu bar row
space-tag position left            # below the menu bar, left edge
space-tag position right           # below the menu bar, right edge
space-tag position default <mode>  # set the fallback for displays without their own setting
space-tag position clear           # drop this display's setting (fall back to the default)
space-tag position list            # show the default and every per-display override
```

| Mode | Where pills sit | Clickable pills | Native menu bar |
| --- | --- | --- | --- |
| `center` | menu bar, centered | yes | preserved |
| `notch-left` | menu bar row, left of notch | yes | preserved (narrow strip) |
| `notch-right` | menu bar row, right of notch | yes | preserved (narrow strip) |
| `left` | below menu bar, left | yes | preserved |
| `right` | below menu bar, right | yes | preserved |

> On a flat (non-notched) display there's no notch to anchor a centered strip
> to, so `notch-left` falls back to `left` and `notch-right` to `right` (pills
> drop below the menu bar at that edge). A true in-menu-bar left/right strip
> isn't possible — `margin` is symmetric, so the bar frame can only center.
>
> On a **flat** display, `center` pills are vertically centered in the menu bar
> (matching the native icons) and the bar is shrunk to a strip sized
> **dynamically** to the live pill row — so it only blocks the middle and the
> native menu items on both sides stay clickable. No knob needed; the strip
> grows/shrinks as spaces and tags change. Use `Y_OFFSET_FLAT` to nudge the
> vertical position and `BAR_PAD` for the strip's edge gap.

---

## 2. Tagging — runtime

```
space-tag <name>               # tag the current space
space-tag <name> <index>       # tag the space with that index
space-tag -- <name>            # tag with a literal name (escapes reserved words like "clear")
space-tag clear                # clear the current space's tag
space-tag auto                 # print auto-tag state
space-tag auto on|off          # toggle auto-tagging from git repo name on cd
space-tag display              # print which spaces the bar shows
space-tag display current|all  # focused display's spaces only / every display's
```

| Knob | Where | Default | Effect |
| --- | --- | --- | --- |
| `SPACE_TAG_AUTO` | env var (per-shell) | unset (= on) | `off` disables cd auto-tagging for this shell only |
| auto-tag state | `~/.config/sketchybar/auto-tag` | on | persisted on/off for `space-tag auto` |
| per-display state | `~/.config/sketchybar/per-display-spaces` | on (= `current`) | persisted on/off for `space-tag display` (`current` = on, `all` = off) |

---

## 3. Notch strip geometry — `theme.sh`

The knobs that shape the `notch-left` / `notch-right` strip (see
[notch design notes](#how-the-notch-strip-works) below).

| Knob | Default | Effect |
| --- | --- | --- |
| `NOTCH_PILL_ROOM` | `330` | **Fallback only.** The notch strip's half-width is now sized **dynamically** to the live pill row (`row_w + NOTCH_SIDE_GAP + 2·BAR_PAD`) so it always fits the whole row and never strands a pill, regardless of tag length. `NOTCH_PILL_ROOM` is used only at boot before any pill has been measured. (Previously this was a fixed reserve and would overflow once the pill row exceeded it.) |
| `NOTCH_SIDE_GAP` | `8` | Gap (points) between the notch edge and the nearest pill. |
| `NOTCH_GAP` | `0` | Only used by `center` mode on notched displays: pill drop below the notch edge (points). Negative pulls pills up toward the notch. |

---

## 4. Geometry — `theme.sh`

| Knob | Default | Effect |
| --- | --- | --- |
| `PILL_HEIGHT` | `25` | Pill background height (points). Also the bar height in `notch-*` and `left`/`right` modes. |
| `PILL_CORNER_RADIUS` | `6` | Pill corner radius. |
| `BAR_HEIGHT` | `24` | Boot-time fallback bar height only, before `y_offset.sh` runs; live height is derived per-display. |
| `Y_OFFSET_FLAT` | `0` | Fine-tune nudge for `center` mode on flat displays. The pill is vertically centered in the real menu bar (to match the native icons); this shifts it `+down` / `-up` from that centered position. `0` = centered. |
| `BELOW_BAR_GAP` | `2` | Gap (points) between the menu bar's bottom edge and the pills in `left`/`right` mode (and the flat fallbacks for `notch-left`/`notch-right`). On flat displays `layout.sh` calibrates sketchybar's `topmost=off` base live (it under-reports the real menu bar) and offsets so the pills clear the **real** menu bar by exactly this gap. Notched `left`/`right` is pinned to its center-mode offset (`y=1`) since the safe area already clears the bar. |
| `FLAT_PILL_INSET` | `1` | Flat `center` only. Breathing room (top AND bottom) inside the **OS clip band** (`clip_h` = `NSStatusBar.thickness`, the height macOS clips menu-bar topmost windows to). The pill is capped to `clip_h − 2·FLAT_PILL_INSET` and centered in the band so its rounded bottom is never clipped — on scaled displays `clip_h` is smaller than `menu_h`, which is what caused the old bottom-crop. Bigger = shorter, more inset pill. |
| `BAR_PAD` | `8` | Gap from the bar's edge to the outermost pill. Single source of truth — read by `sketchybarrc` (bar padding) and `position.sh` (notch boundary math). |
| `PILL_PAD` | `4` | Spacing on each side of a pill (gap between adjacent pills). Read by `sketchybarrc` (`--default`) and `position.sh`. |

---

## 5. Colors — `theme.sh`

Format `0xAARRGGBB` (alpha `00` = transparent, `ff` = opaque). Palette is Catppuccin Mocha.

| Knob | Default | Effect |
| --- | --- | --- |
| `COLOR_BAR_BG` | `0x00000000` | Bar background (transparent — pills float on the real menu bar). |
| `COLOR_PILL_BG` | `0xff313244` | Unfocused pill background. |
| `COLOR_PILL_FG` | `0xffcdd6f4` | Unfocused pill text/icon. |
| `COLOR_PILL_BG_FOCUSED` | `0xff89b4fa` | Focused pill background. |
| `COLOR_PILL_FG_FOCUSED` | `0xff1e1e2e` | Focused pill text/icon. |
| `COLOR_PILL_BG_HIDDEN` | `0x00313244` | Transparent BG used for the display-switch fade-in. |
| `COLOR_PILL_FG_HIDDEN` | `0x00cdd6f4` | Transparent FG used for the fade-in. |

---

## 6. Fonts — `theme.sh`

| Knob | Default | Effect |
| --- | --- | --- |
| `FONT_ICON` | `SF Pro:Bold:13.0` | Space index/icon font (`family:style:size`). |
| `FONT_LABEL` | `SF Pro:Semibold:13.0` | Space label font. |

### Text alignment inside pills

SketchyBar centers text using the font's full line metrics, so SF/system text
can sit a hair off vertically; these nudge it back. Pills are dynamic-width
(sized to their content) — a fixed `width` can't be used because sketchybar
packs fixed-width items edge-to-edge and they overlap. Applied per-pill in
`plugins/space.sh`.

| Knob | Default | Effect |
| --- | --- | --- |
| `LABEL_Y_OFFSET` | `2` | Vertical nudge for custom-name (label) pills. `+` = up, `-` = down. |
| `ICON_Y_OFFSET` | `0` | Vertical nudge for bare space-number (icon) pills. `+` = up, `-` = down. |

---

## 7. Animation — `theme.sh`

| Knob | Default | Effect |
| --- | --- | --- |
| `ANIM_CURVE` | `tanh` | Easing curve: `linear`/`quadratic`/`tanh`/`sin`/`exp`/`circ`. |
| `ANIM_FRAMES_FOCUS` | `15` | Space-focus color tween length (~250ms). |
| `ANIM_FRAMES_DISPLAY_FADE` | `30` | Display-switch fade-in length (~500ms). |

---

## 8. Runtime binaries — `theme.sh`

| Knob | Default | Effect |
| --- | --- | --- |
| `YABAI` | `$(command -v yabai)` | Path to yabai; override via env if not on `PATH`. |
| `JQ` | `$(command -v jq)` | Path to jq; override via env. |

---

## 9. Bar-level constants — `sketchybar/sketchybarrc` (hardcoded)

Tunable but not yet promoted to `theme.sh`. (Bar/pill padding used to live here
too — they're now `BAR_PAD` / `PILL_PAD` in `theme.sh`, see §4.)

| Knob | Location | Default | Effect |
| --- | --- | --- | --- |
| `icon.padding_left` | `sketchybarrc` per-item | `10` | Left inset of the space index inside a pill. |
| boot retry loop | `sketchybarrc` | `20 × 0.5s` (~10s) | How long boot waits for yabai's socket before giving up on pills. |

---

## 10. Local override file

Copy `~/.config/sketchybar/theme.sh` to `~/.config/sketchybar/theme.local.sh`
(gitignored). It's sourced **last**, so anything you set there wins over the
committed defaults. Best place for machine-specific tuning like `NOTCH_PILL_ROOM`.

---

## How the notch strip works

`notch-left` / `notch-right` need clickable pills **beside** the notch without
killing the native menu bar. macOS makes this a layering puzzle:

- `topmost=on` is required for pills to be clickable, but a *full-width* topmost
  bar eats clicks across the whole menu bar.
- So the bar is shrunk with `margin` to a thin strip **centered on the notch**
  (the notch is itself screen-centered). `topmost=on` then only blocks that
  strip; native items on both far sides stay live.
- `margin = notch_left - notch_room`, where `notch_room` is sized **dynamically**
  to the measured pill row (`row_w + NOTCH_SIDE_GAP + 2·BAR_PAD`) — so the strip
  always fits the whole row and never strands a pill. Pills are pushed flush to
  the notch edge via per-item padding, and right-grouped pills are `--reorder`ed
  so they read left→right. (`NOTCH_PILL_ROOM` is just the pre-measurement
  fallback.)

All notch/screen geometry is read live from AppKit every run, so the layout is
resolution-dynamic — no pixel values are hardcoded to a specific resolution.
