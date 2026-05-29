# Spike Conventions

Patterns established across the completion-flash spike session
(2026-05-28 → 2026-05-29). New spikes in this project follow these unless
the question requires otherwise.

## Stack

- **Language:** POSIX shell (`#!/usr/bin/env bash`, `set -u`). Matches the
  parent project (sketchybar plugins + yabai config) which is all bash.
- **Helpers:** `jq` for JSON config merges, `yabai`/`sketchybar` via absolute
  paths (`/opt/homebrew/bin/...`). No new deps.
- **Sandbox-only execution** for large-output commands (use context-mode's
  `ctx_execute` rather than Bash).

## Structure

Each spike: `.planning/spikes/NNN-descriptive-name/`

```
NNN-descriptive-name/
  README.md          # frontmatter + investigation trail + results
  forensic-log.sh    # source-able log helper (single fn, ISO timestamps)
  install.sh         # idempotent wiring + auto +x; auto-backup mutated files
  uninstall.sh       # restore from backup + clean state dir
  <action-script>.sh # the actual behavior under test
```

## Patterns

### Forensic log layer

Every spike writes to `/tmp/spike-NNN-*.log` via a shared `forensic-log.sh`:
```bash
. "$(dirname "$0")/forensic-log.sh"
log <category> <message>
```
Output format: `<ISO-8601-with-ms> <tag> <message>`. Each script in the spike
uses a unique tag (e.g. `stop_hook`, `flash_listener`, `install`,
`session_start`) so `grep -E '^<tag>'` slices cleanly.

### Idempotent JSON config patching

When wiring into a user-owned JSON config (e.g. `~/.claude/settings.json`,
`~/.codex/hooks.json`):

1. **Back up once.** Skip if backup already exists.
2. **jq merge.** Strip any prior entry whose command matches the spike's
   script path (allows re-install for upgrades), then append the new entry.
   Pattern:
   ```bash
   jq --arg cmd "$SCRIPT" '
     .hooks.Event //= [] |
     .hooks.Event = (
       (.hooks.Event | map(.hooks = ((.hooks // []) | map(select(.command != $cmd))))
                     | map(select((.hooks | length) > 0)))
       + [{matcher: "", hooks: [{type: "command", command: $cmd}]}]
     )
   ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
   ```
3. **Uninstall restores from backup.** If backup missing, jq-strip the
   spike's entry instead. Other users' entries are never touched.

### `chmod +x` in install.sh

The Write tool does not preserve execute bit. Every install.sh starts with
`chmod +x "$HERE"/*.sh` so re-runs after edits self-heal. Tied to project
memory `[[plugin-execute-bit]]`.

### Theme integration

Scripts that touch sketchybar colors source the project's theme:
```bash
. "$HOME/.config/sketchybar/theme.sh"
```
This pulls in user overrides from `theme.local.sh` automatically (see
project memory `[[live-config-deploy-copies]]` — repo edits don't propagate
without `cp` and reload). Use the symbolic vars (`$COLOR_PILL_BG_FOCUSED`,
etc.), never hardcoded hex.

### Two-path resolution (primary + fallback)

When a piece of state could be missing (e.g. session-launched-before-install),
implement BOTH paths and tag the strategy in forensic log:
- `strategy=sessionstart` — primary, deterministic
- `strategy=fallback` — best-effort heuristic

Lets users see when they're in the degraded mode.

## Tools & Libraries

- `jq` — JSON read/write/merge. Always tested with `// empty` / `// "fallback"`
  patterns to survive missing fields.
- `yabai -m query --windows --window <ID>` — stable window lookup by id.
  Preferred over pid-based queries when the id is available (it survives
  window moves between spaces).
- `sketchybar --add event NAME` / `--trigger NAME KEY=value` — custom event
  primitive for cross-script communication.
- `sketchybar --animate sin_in_out N --set <item> background.color=0xAARRGGBB`
  — color tween. 15 frames ≈ 250ms at 60fps for "noticeable but quick".

## Avoid

- **Hardcoded paths to repo files**, even in spike code. Production wires
  scripts from a deployed location (e.g. `~/.config/spacetag/`). Spike scripts
  can be local-path-only, but production paths must work cross-machine.
- **Direct mutation of `space.sh` / `spaces.sh`** for spike testing — the
  project's production pill rendering. Spikes add hidden helper items via
  `sketchybar --add item NAME ... drawing=off updates=on` and listen on
  custom events instead.
- **`cat`-based stdin draining in hooks**. Hooks must read stdin synchronously
  (`PAYLOAD="$(cat 2>/dev/null || true)"`); backgrounding `cat >/dev/null &`
  leaks subprocesses.
