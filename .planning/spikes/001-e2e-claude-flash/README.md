---
spike: 001
name: e2e-claude-flash
type: standard
validates: "Given Claude Code finishes a turn in a terminal on space N, when its Stop hook fires a script that walks PPID → yabai window → space, then the sketchybar pill for space N flashes orange (~1s) and reverts."
verdict: VALIDATED
related: []
tags: [claude-code, hooks, ppid, yabai, sketchybar, flash]
---

# Spike 001: e2e-claude-flash

## What This Validates

**Given** Claude Code finishes a turn in a terminal on space N,
**when** its Stop hook fires a script that walks the PPID chain to find the
terminal's window pid → asks yabai for that window's space → triggers a
sketchybar custom event,
**then** the pill for space N flashes orange (~1s fade-in, ~1s hold, ~1s
fade-out — total ~3s window) and returns to its default colors with no
permanent state drift.

This bundles the two highest-risk unknowns into one observable loop:

1. **PPID resolution** — does the Stop hook's process tree actually trace back
   to a yabai-known window? Claude could spawn hooks in a detached shell (no
   terminal ancestor) → the entire concept dies here.
2. **Sketchybar event wiring** — can an external script trigger a custom event
   that an item subscribes to, animate a per-space pill's background, and
   revert without clobbering the pill's existing space.sh behavior?

## Research

| Approach | Surface | Pros | Cons | Status |
|----------|---------|------|------|--------|
| PPID-walk → `yabai -m query --windows --window` by pid | Pure shell + jq | Zero new deps; no Claude env coupling | Fails if Claude spawns hook outside terminal tree | **Chosen** |
| `$CLAUDE_PROJECT_DIR` env var only | Claude-provided | No PPID walk needed | Doesn't carry window/space identity | Skipped — wrong shape |
| Capture pid at session start (PreToolUse), reuse on Stop | Claude hooks | Robust to focus shifts | Extra moving part; not needed if PPID works | Fallback if PPID walk fails |

### Known patterns in this project
- Custom events: `sketchybar --add event NAME` + `sketchybar --trigger NAME KEY=value`.
  Already used by `position_change` and `space_set_change` in `sketchybarrc`.
- Hidden helper items: `--add item NAME right --set NAME drawing=off updates=on
  script=... --subscribe NAME EVENT` (see `layout_watcher`, `spaces_watcher`).
- Per-pill name format: `space.$SID` where `$SID` = yabai space index.
- Color tween: `sketchybar --animate $CURVE $FRAMES --set space.$SID
  background.color=0xAARRGGBB`.

### Known landmines
- `space.sh` re-applies bg color on every `space_change` (focus shift). If a focus
  change lands during the flash, it gets clobbered. Acceptable for the spike;
  production will need a `flash_in_progress` guard or longer animation precedence.
- `theme.sh` lives at `~/.config/sketchybar/theme.sh` (deployed copy, not the repo
  symlink — see project memory).

## How to Run

```bash
# 1. Install hook + sketchybar listener
./install.sh

# 2. Open a terminal on the space you want to test (any space).
#    Run Claude Code there:
#      claude
#    Send any message ("say hi") and wait for the turn to end.

# 3. Watch the pill for that space flash orange briefly, then revert.

# 4. Inspect forensic log to see what the resolver actually found:
cat /tmp/spike-001-flash.log

# 5. Teardown (restores ~/.claude/settings.json and removes sketchybar items):
./uninstall.sh
```

## What to Expect

**Success case:**
- Pill for the focused-at-turn-end space briefly turns orange.
- `/tmp/spike-001-flash.log` contains a sequence:
  - `stop_hook fired pid=NNN ppid=NNN`
  - `walking ppid: PID → PID → PID → TERMINAL_PID`
  - `yabai window found pid=TERMINAL_PID space=N`
  - `triggered flash_space SID=N`
  - `flash_listener fired SENDER=flash_space SID=N`
  - `animated space.N to orange`
  - `reverted space.N to default`

**Failure modes to look for:**
- "no yabai window in ppid chain" → the killer. PPID walk does not reach a
  terminal window. Possible causes: Claude spawns hook via launchd/subprocess
  with no terminal parent; the GUI terminal's window pid differs from any
  process in the chain.
- "trigger fired but listener didn't" → sketchybar subscription not bound. Check
  `sketchybar --query flash_watcher`.
- "listener fired but no flash visible" → `space.sh` clobbered, animation curve
  wrong, or color string malformed.

## Observability

Forensic log at `/tmp/spike-001-flash.log`, append-only, ISO-8601 timestamps,
category tag per line. Every script (`stop-hook.sh`, `flash-listener.sh`,
`install.sh`) writes to it via `forensic-log.sh`.

Inspect summary:
```bash
grep -E '^(stop_hook|flash_listener|install)' /tmp/spike-001-flash.log
```

## Investigation Trail

### Iteration 1 — Resolver dry-run from Claude session (2026-05-28)

Ran `stop-hook.sh` directly from this very Claude Code session (no install
needed — the current shell's PPID chain mirrors what a real Stop hook would
see). Result:

```
stop_hook fired pid=26902 ppid=26899
stop_hook ppid_trail 26899 18308 4337 4320 4317
stop_hook resolved pid=4317 space=3
stop_hook triggered flash_space SID=3 TOOL=claude
```

**Finding:** PPID walk succeeded after 5 hops. Terminal's GUI window pid lives
5 tiers above the hook script (hook → bash invocation → Claude wrapper → Claude
main → terminal helper → terminal GUI window pid). The depth-20 loop cap is
plenty.

**Implication for the killer hypothesis:** Claude Code does *not* detach hooks
from the terminal tree. The PPID chain stays continuous. This is the most
important finding of the spike — the entire concept hinges on it and it holds.

### Iteration 2 — Live flash, first run (FALLBACK path)

Installed. First auto-fire from this conversation triggered a flash. Visual
verified by user.

**Finding (#1):** the revert restored bg to `0x00000000` (transparent) — what
the pill bg was *queried* as. For the focused pill, this looks broken because
the proper focused color is solid grey. Patched flash-listener.sh to source
theme.sh and revert to `$COLOR_PILL_BG_FOCUSED` or `$COLOR_PILL_BG` based on
the SID-vs-focused-space test.

**Finding (#2 — the big one):** the PPID walk lands on the *app* pid (Warp =
pid 4317), which owns 5 windows across 5 spaces. `head -n1` was arbitrary →
wrong window chosen. User confirmed: the actual Claude session lived on space
3 but the resolver flashed space 4.

### Iteration 3 — `is-visible` tiebreaker (partial fix)

Patched resolver to prefer `is-visible: true` among candidate windows. Worked
when the Claude terminal was on the user's focused space. **Broke** when the
user navigated to a different space — the heuristic then picked whichever
Warp window happened to be on the focused space, not the one running Claude.
Confirmed the heuristic's ceiling. Direction shift: need a deterministic map
from session → yabai window id.

### Iteration 4 — SessionStart capture (PRIMARY path)

Added `session-start-hook.sh` wired into Claude's `SessionStart` event. At
session launch, the focused window IS the terminal Claude was just typed
into. Hook captures that window's stable yabai id and persists it to
`/tmp/spike-001-sessions/<session_id>`.

Stop hook now reads `session_id` from stdin, looks up the window id, queries
yabai for its **current** space, and triggers the flash. PPID-walk path kept
as fallback for pre-install sessions (tagged `strategy=fallback` in the log).

**Validated by live run:**
```
stop_hook fired ... session_id=8c1a4aae-d6bb-4002-a0e0-53e2d54d6952
resolved via SESSIONSTART_MAP window_id=358 space=4
triggered flash_space SID=4 TOOL=claude strategy=sessionstart
flash_listener revert plan: space.4 state=unfocused revert_bg=0xff313244
flashed space.4 to 0xffff8800
reverted space.4 to 0xff313244 (unfocused)
```

Window id 358 = the Warp window the user was in when SessionStart fired. Even
though Warp has 5 windows owned by the same app pid, the SessionStart-captured
id uniquely identifies *the one running this Claude session*. yabai's window
query returns its **current** space (4 in this run) — meaning the flash will
follow the window even if it is dragged to a new space mid-session.

## Results

**Verdict: VALIDATED ✓**

### What works
- PPID is continuous from Stop hook back to terminal app (no detached shell).
- `SessionStart` hook fires at `claude` launch with a `session_id` we can use
  as a map key. yabai reports a stable focused-window id at that moment.
- Stop hook receives `session_id` on stdin (verified from log).
- Sketchybar custom events trigger reliably from external scripts; per-pill
  `--animate sin_in_out N --set background.color=` is the right primitive.
- Reverting to theme-derived `$COLOR_PILL_BG{_FOCUSED}` (sourced from
  `~/.config/sketchybar/theme.sh`) produces a clean, theme-consistent recovery.
- jq-merge of `~/.claude/settings.json` is idempotent and preserves all
  existing user hooks (sfx-play, gsd-*, context-mode).

### Known limits / production TODOs

1. **State dir lifecycle.** `/tmp/spike-001-sessions/<session_id>` is created
   per session and never reaped. macOS clears `/tmp` on boot, but production
   should pick a better location (`~/Library/Application Support/spacetag/...`)
   and prune on session end (Claude's `SessionEnd` hook if it exists, or a TTL
   sweep on next `SessionStart`).
2. **Pill-bg revert race.** A focus change during the ~1s flash will fire
   `space_change`, and `space.sh` will repaint with the proper theme color
   anyway. Benign in practice; if it causes flicker, gate `space.sh`'s repaint
   on a `flash_in_progress` flag.
3. **Window-destroyed mid-session.** If the user closes the Claude tab, the
   stored window id becomes stale. Already handled: yabai returns no space →
   we log `SESSIONSTART_MAP stale ... falling back` and use PPID heuristic.
4. **Fallback path picks the wrong window for multi-window terminal apps.**
   By design — that's why the primary path exists. Logged as `strategy=fallback`
   so users / debuggers can see when they're in the degraded mode.
5. **Codex** is unaddressed here. Spike 002 is the next step.
6. **Focus-suppress toggle** (locked decision: optional). Not built in this
   spike — `flash-listener.sh` always flashes. Production should read the
   suppress-when-focused config and skip the trigger when SID == focused
   space.

---

## Superseded — 2026-05-30

This spike is now archived. Production code lives at:
- `sketchybar/plugins/agent-hooks/` (runtime scripts: state.sh, session-start.sh, turn-end.sh, flash-listener.sh)
- `sketchybar/plugins/agent-hooks/adapters/` (per-tool installers: claude.sh, codex.sh, hermes.sh)
- `sketchybar/plugins/agent-hooks/install.sh` and `uninstall.sh`
- `sketchybar/sketchybarrc` (the `flash_space` event + `flash_watcher` item)

**Do NOT run `install.sh` or `uninstall.sh` in THIS directory** on a system with the production code installed — they wire and unwire the same sketchybar item names that production now owns, and would break the live flash. Use `sketchybar/plugins/agent-hooks/uninstall.sh` instead.

Spike scripts retained for forensic value (the PPID-walk + is-visible fallback path was derived here, and the spike's investigation trail documents the dead-ends so future tools-of-similar-shape don't re-discover them).
