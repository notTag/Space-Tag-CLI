---
plan: 01-completion-flash
phase: 01
phase_name: completion-flash
wave: rolling
depends_on: []
autonomous: true
requirements: []
files_modified:
  - sketchybar/plugins/agent-hooks/session-start.sh (new, shared)
  - sketchybar/plugins/agent-hooks/turn-end.sh (new, shared)
  - sketchybar/plugins/agent-hooks/flash-listener.sh (new, shared)
  - sketchybar/plugins/agent-hooks/state.sh (new, shared)
  - sketchybar/plugins/agent-hooks/adapters/common.sh (new)
  - sketchybar/plugins/agent-hooks/adapters/claude.sh (new)
  - sketchybar/plugins/agent-hooks/adapters/codex.sh (new)
  - sketchybar/plugins/agent-hooks/adapters/hermes.sh (new)
  - sketchybar/plugins/agent-hooks/install.sh (new, top-level installer)
  - sketchybar/plugins/agent-hooks/uninstall.sh (new, top-level uninstaller)
  - sketchybar/plugins/agent-hooks/doctor.sh (new, diagnostic)
  - sketchybar/sketchybarrc (add flash_space event + flash_watcher item)
  - sketchybar/theme.sh (3 new flash colors + focus-suppress default)
  - install.sh (top-level: add agent-hooks deploy step)
  - README.md (document the feature)
must_haves:
  - Claude Code turn end fires Stop hook → orange pill flash within 1s on the space hosting that Claude session
  - Codex turn end fires Stop hook → periwinkle pill flash within 1s on the space hosting that Codex session
  - Hermes Agent turn end fires post_llm_call hook → hermes-color pill flash within 1s on the space hosting that Hermes session
  - Flash follows the **window** when dragged to a new space mid-session (window-id lookup, not focused-space lookup)
  - `focus_suppress: true` in config disables flashing when the user is already on that space (`focus_suppress: false` is default — always flash, per locked decision)
  - Existing user hooks (sfx-play, gsd-*, vibe-island-bridge) preserved by all installer adapters — verified by jq/yq inspection after install
  - Re-running install is idempotent (no duplicate hook entries; existing entries upgraded with new script paths)
  - Uninstall restores original config files from backups byte-for-byte
  - Install removes spike-001 hook entries automatically (path-match cleanup)
  - Spike scripts and live hook entries that point at `.planning/spikes/001-e2e-claude-flash/` are gone after install completes
  - All shared scripts have +x bit (Write tool does not preserve)
---

# Phase 01: Completion Flash

## Phase Goal

Flash a pill on the space hosting an AI agent's terminal when that agent finishes a turn, so the user sees "agent done" at a glance regardless of which space they are currently focused on. Ships for Claude Code, Codex, and Hermes Agent in the same release. Reuses the SessionStart-capture + stable-window-id resolver pattern proven in `spikes/001-e2e-claude-flash/`.

## Why this design

The spike validated that:
1. PPID-walk alone is not enough for multi-window terminal apps (Warp has 5 windows under one app pid — `head -n1` and `is-visible` heuristics both fail when the user navigates away from the agent's window).
2. SessionStart hook fires before any focus change, so the focused yabai window id at that moment IS the window the user just launched the agent in. Persist that id keyed by `session_id`, then on every Stop / `post_llm_call` look it up and ask yabai for its **current** space.
3. Cross-tool hook schemas are intentionally parallel — Claude / Codex / Hermes use the same conceptual surface (SessionStart-equivalent + turn-end event, JSON / JSON / YAML config, stdin JSON payload with `session_id`). The wrapper scripts can be shared; only the **installer adapters** are tool-specific (different config files, different event names, different stdout requirements, different consent gates).

See `.planning/spikes/001-e2e-claude-flash/README.md` and `.planning/spikes/002-codex-hook-discovery/README.md` for full evidence trail and known production TODOs that this plan addresses.

## Architecture (locked)

```
~/.claude/settings.json        ─┐
~/.codex/hooks.json            ─┼─ per-tool adapter installs scripts pointing at:
~/.hermes/config.yaml          ─┘

~/.config/sketchybar/plugins/agent-hooks/
  session-start.sh   ← capture focused yabai window id, persist by session_id
  turn-end.sh        ← read session_id from stdin, lookup window id, query
                       yabai for its current space, --trigger flash_space SID=N TOOL=<tool>
                       (PPID-walk + is-visible fallback for pre-install sessions)
  flash-listener.sh  ← subscribed to flash_space; animate pill bg to tool color,
                       hold ~600ms, revert to theme-correct color
                       (focus-suppress check: skip flash if SID == focused space AND config says suppress)
  state.sh           ← shared state helpers: paths, dir creation, TTL prune
  adapters/
    common.sh        ← shared installer helpers: backup-once, jq-merge / yq-merge,
                       detect-and-skip, chmod +x sweep
    claude.sh        ← installs/uninstalls in ~/.claude/settings.json (JSON)
    codex.sh         ← installs/uninstalls in ~/.codex/hooks.json (JSON) + trust hash
    hermes.sh        ← installs/uninstalls in ~/.hermes/config.yaml (YAML),
                       wraps turn-end.sh so it prints {} on stdout
  install.sh         ← top-level: deploy scripts, run all adapters, remove spike-001
  uninstall.sh       ← top-level: run all adapters' uninstall, restore from backups
  doctor.sh          ← diagnostic: detect installed tools, verify each adapter's
                       wiring, tail recent /tmp/agent-hooks.log entries

~/Library/Application Support/spacetag/sessions/
  <session_id>       ← one-line file: yabai window id (integer)
                       TTL: pruned on next SessionStart per tool, or 7d untouched

~/Library/Application Support/spacetag/backups/
  <YYYY-MM-DD>/      ← one dir per first-install date
    claude-settings.json
    codex-hooks.json
    hermes-config.yaml

~/.config/spacetag/agent-hooks.yaml
  focus_suppress: false        # default per locked decision: always flash
  per_tool:
    claude:   { enabled: true,  color: 0xffff8800 }     # orange
    codex:    { enabled: true,  color: 0xffb6a8e8 }     # periwinkle
    hermes:   { enabled: true,  color: 0xff6dd5b0 }     # mint (TBD — see Task 0)
```

## Per-tool variant matrix (lock the differences here so adapters are mechanical)

| Aspect | Claude | Codex | Hermes |
|--------|--------|-------|--------|
| Config path | `~/.claude/settings.json` | `~/.codex/hooks.json` | `~/.hermes/config.yaml` |
| Format | JSON | JSON | YAML |
| Session-start event | `SessionStart` | `SessionStart` | `on_session_start` |
| Turn-end event | `Stop` | `Stop` | `post_llm_call` |
| Stdin shape | `{session_id, ...}` | `{session_id, ...}` (inferred; verify on first prod run) | `{session_id, hook_event_name, cwd, extra, ...}` |
| Stdout required | empty / ignored | empty / ignored | **must `printf '{}\n'`** (else hermes logs malformed-JSON warning per `hooks.md`) |
| Consent | none | trust-hash in `config.toml [hooks.state]` — first run prompts | first-use allowlist in `~/.hermes/shell-hooks-allowlist.json`; bypass with `hooks_auto_accept: true` |
| Adapter installer responsibilities | jq-merge into `hooks.Stop[]` and `hooks.SessionStart[]` | jq-merge into `hooks.Stop[0].hooks[]` and `hooks.SessionStart[0].hooks[]` + warn user about first-run trust prompt | yq-merge into `hooks.post_llm_call[]` and `hooks.on_session_start[]`, set `hooks_auto_accept: true` OR document interactive prompt, register wrapped command |

---

## Tasks

### Task 0 — Lock the Hermes flash color ✅ DONE (2026-05-30)

**Type:** decision
**Wave:** 0
**Depends on:** —
**Autonomous:** false (needs user input)

**Locked value:** `COLOR_FLASH_HERMES=0xff8dbf8a` (sage green).

Rationale: distinct from `COLOR_FLASH_CLAUDE=0xffff8800` (orange) and `COLOR_FLASH_CODEX=0xffb6a8e8` (periwinkle); softer / less attention-grabbing than mint; sits well against Catppuccin Mocha `COLOR_PILL_BG=0xff313244` and the focused-pill blue `COLOR_PILL_BG_FOCUSED=0xff89b4fa`.

---

### Task 1 — Add flash colors + focus-suppress default to theme.sh

**Type:** execute
**Wave:** 1
**Depends on:** Task 0
**Autonomous:** true

<action>
Append three flash color vars and a focus-suppress default to `sketchybar/theme.sh` after the existing `COLOR_PILL_*` block. Names: `COLOR_FLASH_CLAUDE=0xffff8800`, `COLOR_FLASH_CODEX=0xffb6a8e8`, `COLOR_FLASH_HERMES=<value from Task 0>`. Also add a section header comment `# ─── completion flash ─────────────────────` and a `FLASH_FOCUS_SUPPRESS=${FLASH_FOCUS_SUPPRESS:-false}` line so `agent-hooks.yaml` overrides via env in install.sh propagate. Keep existing variable order untouched.
</action>

<read_first>
- `sketchybar/theme.sh` (current vars and section ordering; do not break the existing geometry / animation comment blocks below the color section)
- `~/.config/sketchybar/theme.sh` (the deployed copy — confirm format matches; per project memory `live-config-deploy-copies.md` this is the file plugins actually source)
</read_first>

<acceptance_criteria>
- `grep -E '^COLOR_FLASH_(CLAUDE|CODEX|HERMES)=' sketchybar/theme.sh` returns 3 lines with matching hex values
- `grep -E '^FLASH_FOCUS_SUPPRESS=' sketchybar/theme.sh` returns 1 line with default `false`
- Sourcing the file (`bash -n sketchybar/theme.sh && . sketchybar/theme.sh`) does not error and existing vars (`COLOR_PILL_BG`, `BAR_HEIGHT`, etc.) still have their original values
</acceptance_criteria>

---

### Task 2 — Implement shared `state.sh` (paths, mkdir, TTL prune)

**Type:** execute
**Wave:** 1
**Depends on:** —
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/state.sh` exporting these functions:
- `agent_hooks_state_dir()` — echoes `${SPACETAG_STATE_DIR:-$HOME/Library/Application Support/spacetag}`. Path is parenthesized-safe (handles spaces).
- `agent_hooks_sessions_dir()` — echoes `$(agent_hooks_state_dir)/sessions`
- `agent_hooks_backups_dir()` — echoes `$(agent_hooks_state_dir)/backups`
- `agent_hooks_log()` — appends ISO-8601 timestamp + `$1` tag + remaining args to `${SPACETAG_LOG:-/tmp/agent-hooks.log}`
- `agent_hooks_prune_sessions()` — removes session files older than 7 days from sessions dir using `find ... -mtime +7 -delete`
- `agent_hooks_ensure_dirs()` — mkdir -p both sessions and backups dirs

Source-only: the file is `. "$(dirname "$0")/state.sh"` from session-start.sh / turn-end.sh / install.sh.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/forensic-log.sh` (analog log helper; pattern matches)
- `.planning/spikes/CONVENTIONS.md` (forensic log layer convention — ISO timestamps, category tag, append-only)
</read_first>

<acceptance_criteria>
- `bash -n sketchybar/plugins/agent-hooks/state.sh` exits 0
- `bash -c '. sketchybar/plugins/agent-hooks/state.sh && agent_hooks_state_dir'` echoes a path matching `Application Support/spacetag` (or the override)
- `agent_hooks_ensure_dirs` creates both dirs and is idempotent (re-running does not error)
- `agent_hooks_log info "test"` writes a line ending in `info test` to the log file
</acceptance_criteria>

---

### Task 3 — Implement `session-start.sh` (capture window id by session_id)

**Type:** execute
**Wave:** 1
**Depends on:** Task 2
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/session-start.sh`. Behavior:
1. Source `state.sh` and `theme.sh` for `$YABAI` / `$JQ`.
2. Read stdin into `PAYLOAD` synchronously (`PAYLOAD="$(cat 2>/dev/null || true)"`).
3. Parse `SESSION_ID=$(echo "$PAYLOAD" | "$JQ" -r '.session_id // empty')`.
4. Parse `SOURCE=$(echo "$PAYLOAD" | "$JQ" -r '.source // empty')` for forensic value (Claude provides this; hermes/codex may not).
5. If no `SESSION_ID`: log `session_start ERROR no session_id in stdin`, then exit 0 (non-blocking).
6. Query `WINDOW_ID=$("$YABAI" -m query --windows --window | "$JQ" -r '.id // empty')`. If empty: log error, exit 0.
7. Write the window id (newline-terminated) to `$(agent_hooks_sessions_dir)/$SESSION_ID`.
8. Call `agent_hooks_prune_sessions` (cheap, runs at most once per session start).
9. Log `session_start captured window_id=$WINDOW_ID session_id=$SESSION_ID`.

CRITICAL: When invoked by Hermes (`post_llm_call` / `on_session_start`), the script MUST end with `printf '{}\n'` on stdout so the JSON-response contract is satisfied. Claude and Codex ignore stdout, so unconditional `printf '{}\n'` is safe and shared.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/session-start-hook.sh` (proven structure — read the whole file; this is the production-grade version)
- `~/.hermes/hermes-agent/website/docs/user-guide/features/hooks.md` (Shell Hooks section: stdin JSON wire format and `printf '{}\n'` requirement)
- `sketchybar/plugins/agent-hooks/state.sh` (the helpers being sourced)
</read_first>

<acceptance_criteria>
- `bash -n sketchybar/plugins/agent-hooks/session-start.sh` exits 0
- Piping `'{"session_id":"test-uuid-123"}'` to the script: log file gains a `session_start captured window_id=N session_id=test-uuid-123` line, and `$(agent_hooks_sessions_dir)/test-uuid-123` contains a single integer line equal to the focused yabai window id
- Final stdout line is exactly `{}` (verifiable with `tail -1 | od -c` showing `{` `}` newline)
- Re-running with the same session_id overwrites the file (idempotent)
- Empty stdin payload causes a single log line and exit 0 without touching sessions dir
</acceptance_criteria>

---

### Task 4 — Implement `turn-end.sh` (resolve space, trigger flash)

**Type:** execute
**Wave:** 1
**Depends on:** Task 2, Task 3
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/turn-end.sh`. Behavior:
1. Source `state.sh` and `theme.sh`. Bind `$YABAI`, `$JQ`, `$SKETCHYBAR`.
2. Read `PAYLOAD="$(cat 2>/dev/null || true)"`. Extract `SESSION_ID`.
3. Argument `$1` is the TOOL name (`claude` | `codex` | `hermes`) — adapters pass it explicitly.
4. PRIMARY path: if `SESSION_ID` non-empty AND `$(agent_hooks_sessions_dir)/$SESSION_ID` exists, read `WIN_ID`. Query `SPACE=$("$YABAI" -m query --windows --window "$WIN_ID" | "$JQ" -r '.space // empty')`. If non-empty: log `strategy=sessionstart window_id=$WIN_ID space=$SPACE`, `--trigger flash_space SID=$SPACE TOOL=$1`, then `printf '{}\n'` and exit 0.
5. FALLBACK path: PPID walk + is-visible heuristic (port from spike `stop-hook.sh` lines ~50-100). Cache `WINDOWS_JSON` once. Walk PPID up to depth 20. For each pid, pick visible-or-first window owned by that pid. On hit: log `strategy=fallback ...`, trigger, exit.
6. If both paths fail: log `FAIL no resolvable window for session_id=$SESSION_ID`, `printf '{}\n'`, exit 0 (non-blocking).
7. Always end with `printf '{}\n'` on every code path (Hermes safety).

Pre-trigger gate: if `FLASH_FOCUS_SUPPRESS=true` (sourced from theme.sh; loader resolves from `~/.config/spacetag/agent-hooks.yaml` via install-time templating) AND the resolved `$SPACE` equals the currently-focused space (`$YABAI -m query --spaces --space | $JQ -r '.index'`), skip the trigger and log `focus_suppress=true skipped`. The default is `false` — always flash — per locked decision.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/stop-hook.sh` (full file — this is the proven resolver; production version is a mechanical port plus the `$1` TOOL arg plus the focus-suppress gate plus the trailing `printf '{}\n'`)
- `~/.hermes/hermes-agent/website/docs/user-guide/features/hooks.md` (stdin payload shape — Hermes wraps everything in `extra` but `session_id` is at top level, same as Claude/Codex)
- `sketchybar/plugins/agent-hooks/state.sh`
- `sketchybar/plugins/space.sh` (existing per-pill render — the production hook MUST NOT modify pills directly; only `--trigger flash_space` so the listener owns animation)
</read_first>

<acceptance_criteria>
- `bash -n sketchybar/plugins/agent-hooks/turn-end.sh` exits 0
- Invoked with stdin `'{"session_id":"test-id-abc"}'` and arg `claude`, AFTER `session-start.sh` has been run with the same session id from the current shell: log shows `strategy=sessionstart window_id=N space=M`, and `sketchybar --query flash_watcher` shows it received the event (or `tail -f /tmp/agent-hooks.log` after triggering shows `flash_listener fired ... TOOL=claude`)
- Invoked with empty stdin and arg `claude`: log shows `strategy=fallback` and either a successful trigger OR a `FAIL no resolvable window` line — does NOT crash
- Final stdout line is exactly `{}` on every exit path
- When `FLASH_FOCUS_SUPPRESS=true` is exported in env AND resolved SID equals focused space: log shows `focus_suppress=true skipped`, no sketchybar trigger fires
</acceptance_criteria>

---

### Task 5 — Implement `flash-listener.sh` (animate + theme-correct revert)

**Type:** execute
**Wave:** 1
**Depends on:** Task 1
**Autonomous:** true

<action>
Port `.planning/spikes/001-e2e-claude-flash/flash-listener.sh` to `sketchybar/plugins/agent-hooks/flash-listener.sh` with three changes:
1. Color map: case on `$TOOL` → set `FLASH_COLOR` to `$COLOR_FLASH_CLAUDE`, `$COLOR_FLASH_CODEX`, or `$COLOR_FLASH_HERMES`. Default falls through to claude orange.
2. Source `theme.sh` early so all three flash colors are in scope; the spike's `theme.sh` source order already handles theme.local.sh overrides — preserve that.
3. Keep the existing query-pill / determine focus / animate / hold / revert sequence — proven in spike Iteration 4.

Listener flow:
- Validate `$SID` non-empty; else log error + exit 0.
- `PILL=space.$SID`; bail if `--query "$PILL"` returns empty.
- Pick `FLASH_COLOR` from `$TOOL`.
- Resolve revert color: query focused space; if `$SID == focused`, use `$COLOR_PILL_BG_FOCUSED` else `$COLOR_PILL_BG`.
- `--animate sin_in_out 15 --set "$PILL" background.color=$FLASH_COLOR`.
- Background subshell: `sleep 0.6; --animate sin_in_out 20 --set "$PILL" background.color=$REVERT_BG`, log revert.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/flash-listener.sh` (the proven listener — read full file; this task is a port + color-map extension)
- `sketchybar/theme.sh` (after Task 1 lands: confirms the three flash color vars exist)
- `sketchybar/plugins/space.sh` (DO NOT modify it; this task only references it to understand the revert-color semantics — `space.sh` repaints on focus change so the revert is correct for the steady state)
</read_first>

<acceptance_criteria>
- `bash -n sketchybar/plugins/agent-hooks/flash-listener.sh` exits 0
- Manually triggering `sketchybar --trigger flash_space SID=<existing-pill> TOOL=claude` after install: log shows `flashed ... to $COLOR_FLASH_CLAUDE` and a ~1s later `reverted ... to $COLOR_PILL_BG_FOCUSED` (or `_BG` depending on focus); querying the pill 2s later shows bg matches the proper theme color (NOT `0x00000000`)
- Same for `TOOL=codex` flashes periwinkle; `TOOL=hermes` flashes the Task-0 color
- Trigger with non-existent SID logs `ERROR pill space.999 not found` and exits cleanly
</acceptance_criteria>

---

### Task 6 — Wire `flash_space` event + `flash_watcher` item in sketchybarrc

**Type:** execute
**Wave:** 2
**Depends on:** Task 5
**Autonomous:** true

<action>
Add to `sketchybar/sketchybarrc` in the `# ─── custom events ───` block: `sketchybar --add event flash_space`.

In the `# ─── watchers ────` block, after `spaces_watcher`, add:

```
sketchybar --add item flash_watcher right \
           --set flash_watcher drawing=off updates=on \
               script="$PLUGIN_DIR/agent-hooks/flash-listener.sh" \
           --subscribe flash_watcher flash_space
```

Match the indentation and comment style of `layout_watcher` / `spaces_watcher`. Add a brief comment explaining the watcher's purpose (one-line: "flash_watcher: animates the SID-targeted pill to TOOL color on flash_space event, reverts to theme color after ~1s").
</action>

<read_first>
- `sketchybar/sketchybarrc` (full file — see existing event registration pattern + watcher pattern; match style exactly)
- `.planning/spikes/001-e2e-claude-flash/install.sh` (the spike's runtime --add invocation; production version is config-file based, not runtime, so the wiring survives sketchybar --reload)
</read_first>

<acceptance_criteria>
- `grep -F 'sketchybar --add event flash_space' sketchybar/sketchybarrc` returns 1 line
- `grep -F 'flash_watcher' sketchybar/sketchybarrc` returns at least 3 lines (--add, --set with script path, --subscribe)
- After `sketchybar --reload`: `sketchybar --query flash_watcher` returns a JSON object (item exists), and `sketchybar --query bar | jq '.items'` includes "flash_watcher"
- Triggering `sketchybar --trigger flash_space SID=1 TOOL=claude` causes a log entry from flash-listener.sh
</acceptance_criteria>

---

### Task 7 — Implement `adapters/common.sh` (shared installer helpers)

**Type:** execute
**Wave:** 3
**Depends on:** Task 2
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/adapters/common.sh` exporting:
- `adapter_backup_once <src-path> <backup-name>` — copies src to `$(agent_hooks_backups_dir)/$(date +%Y-%m-%d)/<backup-name>` if backup doesn't already exist for today. Returns 0 if backed up or already exists, 1 if src missing.
- `adapter_chmod_scripts <dir>` — `chmod +x` all `*.sh` in dir (Write tool does not preserve +x; per `[[plugin-execute-bit]]` memory). Idempotent.
- `adapter_detect <tool>` — returns 0 if the tool's config file exists, 1 otherwise. Used to skip absent tools cleanly.
- `adapter_strip_spike_entries <claude-settings-path>` — jq-removes any Stop / SessionStart entries whose command path contains `.planning/spikes/001-e2e-claude-flash/`. Idempotent. Logged.

Source-only file; no main body.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/install.sh` (the jq-merge + backup pattern — preserved here as a shared helper, not duplicated per adapter)
- `.planning/spikes/CONVENTIONS.md` (the "idempotent JSON config patching" convention; this helper IS that convention)
- `sketchybar/plugins/agent-hooks/state.sh` (sourced for `agent_hooks_backups_dir`)
</read_first>

<acceptance_criteria>
- `bash -n adapters/common.sh` exits 0
- `bash -c '. adapters/common.sh && adapter_detect claude && echo YES || echo NO'` echoes `YES` if `~/.claude/settings.json` exists, else `NO`
- `adapter_backup_once /tmp/test-src.json claude-settings.json` creates the dated backup dir and a copy; running it again same day does not duplicate (file mtime unchanged)
- `adapter_strip_spike_entries` on a settings.json file containing the spike path leaves a file whose `jq '.hooks.Stop[] | .hooks[] | .command'` does NOT contain `.planning/spikes/001-e2e-claude-flash/` for ANY entry
</acceptance_criteria>

---

### Task 8 — Implement `adapters/claude.sh` (Claude Code installer)

**Type:** execute
**Wave:** 3
**Depends on:** Task 7
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/adapters/claude.sh` with sub-commands invoked as `claude.sh install|uninstall|status`.

Install path:
1. `adapter_detect claude` (skip with log if `~/.claude/settings.json` missing).
2. `adapter_backup_once ~/.claude/settings.json claude-settings.json`.
3. `adapter_strip_spike_entries ~/.claude/settings.json` (removes spike-001 entries cleanly).
4. jq-merge: add this script's `session-start.sh` (full absolute path resolved at install time) into `.hooks.SessionStart[]` and a wrapper invoking `turn-end.sh claude` into `.hooks.Stop[]`. Use the same dedupe pattern from `spike/001/install.sh` (strip existing entry by command, then append). Preserve all unrelated existing hooks (`sfx-play.sh`, `gsd-*`, `context-mode`).
5. Log + echo summary line.

Uninstall path: jq-strip both entries by command path; if `claude-settings.json.spike-001.bak` style backups exist, prefer restore; else use jq-strip.

Status: echo "claude: installed" if both event entries match this adapter's expected script paths; else "claude: not installed".
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/install.sh` (the proven Claude jq-merge — lines ~50-90 of the spike's install.sh, including the dedupe pattern)
- `.planning/spikes/001-e2e-claude-flash/uninstall.sh` (the strip pattern)
- `sketchybar/plugins/agent-hooks/adapters/common.sh` (the shared helpers being called)
- `~/.claude/settings.json` (the live target file — its current shape with sfx-play, gsd-*, context-mode entries; verify after install all are still present)
</read_first>

<acceptance_criteria>
- `bash -n adapters/claude.sh` exits 0
- After `adapters/claude.sh install` on a fresh checkout: `jq '.hooks.Stop[].hooks[].command' ~/.claude/settings.json` includes the production `turn-end.sh claude` invocation AND still includes the pre-existing `sfx-play.sh` entry
- `jq '.hooks.SessionStart[].hooks[].command' ~/.claude/settings.json` includes `session-start.sh` AND still includes the gsd-* SessionStart entries
- After install: zero entries reference `.planning/spikes/001-e2e-claude-flash/`
- `adapters/claude.sh install` run twice in a row: hook entry count for this adapter's commands stays at 1 each (idempotent)
- `adapters/claude.sh uninstall` returns the file to a state where `jq '.hooks.Stop[].hooks[].command'` no longer contains the production paths, and all original user hooks are still present
- `adapters/claude.sh status` echoes `claude: installed` after install and `claude: not installed` after uninstall
</acceptance_criteria>

---

### Task 9 — Implement `adapters/codex.sh` (Codex CLI installer)

**Type:** execute
**Wave:** 3
**Depends on:** Task 7
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/adapters/codex.sh` with sub-commands `install|uninstall|status`.

Codex schema differences from Claude (re-verify by reading existing `~/.codex/hooks.json`):
- Stop / SessionStart arrays each contain ONE entry which has its OWN `.hooks[]` array. So the jq-merge target is `.hooks.Stop[0].hooks[]` not `.hooks.Stop[].hooks[]`.
- Entries have shape `{type: "command", command: "...", timeout: 5}`.
- `config.toml [hooks.state]` tracks `trusted_hash = "sha256:..."` per registered hook (path:event:N:N). Adding a new hook means Codex prompts for trust on first run.

Install path:
1. `adapter_detect codex` (skip with log if `~/.codex/hooks.json` missing).
2. `adapter_backup_once ~/.codex/hooks.json codex-hooks.json`.
3. jq-merge: in `.hooks.Stop[0].hooks`, dedupe by command then append `{type:"command", command:"<abs path>/turn-end.sh codex", timeout:5}`. Same shape for `.hooks.SessionStart[0].hooks` with `session-start.sh`. If the top-level Stop / SessionStart arrays are empty, create an entry like the existing vibe-island-bridge pattern.
4. Echo to user: "Codex: first turn after install may prompt for trust on your new hooks (allow them to proceed)."
5. Log.

Uninstall: jq-strip by command path; preserve all other entries (notably vibe-island-bridge).

Status: same shape as claude.sh.
</action>

<read_first>
- `~/.codex/hooks.json` (current file — shape with single-entry Stop / SessionStart arrays each containing a `.hooks[]` array with the vibe-island-bridge entry; the jq merge target is one level deeper than Claude's)
- `.planning/spikes/002-codex-hook-discovery/README.md` (the cross-tool parity proof + trust-hash mechanism notes + production TODOs)
- `~/.codex/config.toml` (the `[hooks.state]` section — informational; we don't write to it, codex does on first trust)
- `sketchybar/plugins/agent-hooks/adapters/common.sh`
</read_first>

<acceptance_criteria>
- `bash -n adapters/codex.sh` exits 0
- After `adapters/codex.sh install`: `jq '.hooks.Stop[0].hooks[].command' ~/.codex/hooks.json` includes `turn-end.sh codex` AND still includes the original vibe-island-bridge entry
- Same shape verified for `SessionStart[0].hooks[]`
- Idempotency: re-running install does not add duplicate entries (count for our scripts stays at 1 each)
- `adapters/codex.sh uninstall` returns the file to its backed-up state byte-for-byte (`diff` against `$(agent_hooks_backups_dir)/<date>/codex-hooks.json` is empty)
- `adapters/codex.sh status` works for both states
</acceptance_criteria>

---

### Task 10 — Implement `adapters/hermes.sh` (Hermes Agent installer)

**Type:** execute
**Wave:** 3
**Depends on:** Task 7
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/adapters/hermes.sh` with sub-commands `install|uninstall|status`.

Hermes schema (`~/.hermes/config.yaml`, YAML):
- `hooks: {}` is the top-level map. Each value is a list of entries. Events for us: `on_session_start` and `post_llm_call`.
- Each entry: `{matcher: "<regex>", command: "<cmd>", timeout: <int>}`. Matcher is optional for non-tool events.
- Consent: first-use prompts per (event, command) pair, stored in `~/.hermes/shell-hooks-allowlist.json`. Bypassable with `hooks_auto_accept: true` at top level OR env var `HERMES_ACCEPT_HOOKS=1` OR `--accept-hooks` CLI flag.

Install path:
1. `adapter_detect hermes` (skip with log if `~/.hermes/config.yaml` missing).
2. `adapter_backup_once ~/.hermes/config.yaml hermes-config.yaml`.
3. Use `yq` (require it via `command -v yq` — if missing, error with install hint `brew install yq`) to:
   - Set `.hooks.on_session_start += [{command: "<abs>/session-start.sh", timeout: 5}]` after dedupe by command.
   - Set `.hooks.post_llm_call += [{command: "<abs>/turn-end.sh hermes", timeout: 5}]` after dedupe.
   - DO NOT auto-set `hooks_auto_accept: true` — leaves the user's existing setting alone. If it's false and the user runs hermes next, they'll get a one-time trust prompt. Document this in the install summary.
4. Echo: "Hermes: next interactive `hermes` invocation will prompt you to allow these new hooks (one-time). Auto-accept with `--accept-hooks`, `HERMES_ACCEPT_HOOKS=1`, or `hooks_auto_accept: true` in config.yaml."
5. Run `hermes hooks doctor` and tee its output to the log so we capture any allowlist warnings.

Uninstall: yq-strip by command path; restore from backup if available.
</action>

<read_first>
- `~/.hermes/config.yaml` (current shape — `hooks: {}` is empty currently; confirm yq is the right tool by checking what's installed)
- `~/.hermes/hermes-agent/website/docs/user-guide/features/hooks.md` (Shell Hooks section — YAML schema, JSON wire protocol, consent model)
- `sketchybar/plugins/agent-hooks/adapters/common.sh`
- `sketchybar/plugins/agent-hooks/turn-end.sh` (this is the script being wired; the trailing `printf '{}\n'` requirement comes from here)
</read_first>

<acceptance_criteria>
- `bash -n adapters/hermes.sh` exits 0
- `yq` is required by the script; absence produces a clear error with `brew install yq` hint
- After `adapters/hermes.sh install`: `yq '.hooks.on_session_start[].command' ~/.hermes/config.yaml` includes `session-start.sh`; `yq '.hooks.post_llm_call[].command' ~/.hermes/config.yaml` includes `turn-end.sh hermes`
- `hermes hooks list` (run after install) shows both entries
- Idempotency: re-running install does not duplicate entries
- `adapters/hermes.sh uninstall` restores byte-for-byte from backup
- `adapters/hermes.sh status` works for both states
</acceptance_criteria>

---

### Task 11 — Top-level `install.sh` + `uninstall.sh`

**Type:** execute
**Wave:** 4
**Depends on:** Task 1, Task 5, Task 6, Task 8, Task 9, Task 10
**Autonomous:** true

<action>
`sketchybar/plugins/agent-hooks/install.sh`:
1. Source `state.sh` for `agent_hooks_log`.
2. Call `agent_hooks_ensure_dirs`.
3. Deploy plugin scripts: copy `sketchybar/plugins/agent-hooks/*.sh` and `adapters/*.sh` from the repo to `~/.config/sketchybar/plugins/agent-hooks/` and `~/.config/sketchybar/plugins/agent-hooks/adapters/`. This MUST be `cp` not symlink per project memory `[[live-config-deploy-copies]]`.
4. Run `chmod +x` recursively on the deployed dir.
5. Run each adapter's install: `claude.sh install`, `codex.sh install`, `hermes.sh install`. Tolerate per-adapter `not installed` skips.
6. `sketchybar --reload` to pick up the rc changes from Task 6.
7. Echo summary: per-tool install state, log location, and uninstall hint.

`sketchybar/plugins/agent-hooks/uninstall.sh`:
1. Source `state.sh`.
2. Run each adapter's uninstall.
3. Optionally: remove the deployed plugin dir at `~/.config/sketchybar/plugins/agent-hooks/`. Add a `--keep-scripts` flag to leave them in place (debug convenience).
4. `sketchybar --reload`.
5. Echo summary.

`install.sh` MUST be idempotent: running twice in succession should produce identical final state.
</action>

<read_first>
- `install.sh` (the existing top-level installer at repo root — read for style + how it currently deploys sketchybar plugins; this task adds an `agent-hooks` deploy step to it OR is a sub-installer invoked from it)
- `.planning/spikes/001-e2e-claude-flash/install.sh` / `uninstall.sh` (the spike's install/uninstall — port the structure)
- `sketchybar/sketchybarrc` (for the reload mechanism; verify the rc handles the new flash_watcher item on reload without erroring)
</read_first>

<acceptance_criteria>
- `bash -n install.sh && bash -n uninstall.sh` exit 0
- After `install.sh`: `ls ~/.config/sketchybar/plugins/agent-hooks/` contains all 4 runtime scripts + adapters subdir; all are executable (`stat -f '%Lp'` >= 700)
- After `install.sh`: `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.hermes/config.yaml` ALL contain the new hook entries (for tools detected as installed); zero references to `.planning/spikes/001-e2e-claude-flash/` remain
- `install.sh` run twice: state after second run is identical to state after first (diff each touched file → no changes)
- After `uninstall.sh`: each config file matches its backup byte-for-byte; deployed plugin dir is gone (unless `--keep-scripts`)
- `sketchybar --query flash_watcher` succeeds after install, errors-or-missing after uninstall (depending on rc state)
</acceptance_criteria>

---

### Task 12 — `doctor.sh` diagnostic

**Type:** execute
**Wave:** 4
**Depends on:** Task 11
**Autonomous:** true

<action>
Create `sketchybar/plugins/agent-hooks/doctor.sh`. Behavior:
1. For each tool: detect, run `<adapter>.sh status`, echo result.
2. Verify deployed scripts exist and are executable.
3. Verify `flash_watcher` sketchybar item exists.
4. Verify `flash_space` event registered (best-effort — `sketchybar --query bar | jq` to see if event-add was a no-op vs. registered).
5. Tail last 30 lines of `agent-hooks.log` so user can see recent fires.
6. Verify state dir + sessions count.
7. Print recommended next test: "Open a terminal, run `claude --print 'hi'` (or codex / hermes equivalent), watch the pill flash."

Exit code: 0 if all installed tools' adapters report installed AND scripts deployed; 1 otherwise (so it can be used in CI).
</action>

<read_first>
- All adapter files (they expose `status` and we reuse the contract)
- `sketchybar/plugins/agent-hooks/state.sh` (for paths)
- `.planning/spikes/001-e2e-claude-flash/forensic-log.sh` (log file conventions)
</read_first>

<acceptance_criteria>
- `bash -n doctor.sh` exits 0
- After `install.sh`: `doctor.sh` exits 0 and prints `claude: installed`, `codex: installed` (if applicable), `hermes: installed` lines
- After `uninstall.sh`: `doctor.sh` exits 1 and prints `... not installed` lines
- Log tail is present in output when log file exists
- Output is human-readable: section dividers, one finding per line, no JSON dumps
</acceptance_criteria>

---

### Task 13 — Smoke verification (manual UAT)

**Type:** verify
**Wave:** 5
**Depends on:** Task 11, Task 12
**Autonomous:** false (needs visual confirmation)

<action>
Run the spike-style UAT loop for the production code:
1. `install.sh` from the repo root.
2. `doctor.sh` — confirm all detected tools report installed.
3. Open a fresh terminal on each detected tool's space. Send any message (e.g. `claude` → "say hi"; `codex` if CLI works → "say hi"; `hermes chat` → "say hi"). Confirm visually that the right-colored pill flashes on the corresponding space within ~1s.
4. Test "follow window across spaces": drag the agent's terminal window to a different space, send another message, confirm flash hits the NEW space.
5. Test focus-suppress: set `FLASH_FOCUS_SUPPRESS=true` (env or theme.local.sh), restart sketchybar, send a message while focused on agent's space → no flash; switch away and send another → flashes.
6. `uninstall.sh`; `doctor.sh` reports all `not installed`; verify config files restored byte-for-byte from backups.
7. Tail `agent-hooks.log` and confirm strategy=sessionstart predominates (not strategy=fallback) for sessions started after install.
</action>

<read_first>
- `sketchybar/plugins/agent-hooks/doctor.sh` (status semantics for interpreting output)
- `.planning/spikes/001-e2e-claude-flash/README.md` Results section (the spike's UAT checklist — production reproduces the same observable outcomes)
</read_first>

<acceptance_criteria>
- All three tools' pills flash correctly per their configured color on a fresh-installed session
- Window-drag follow-through verified for at least one tool
- focus_suppress toggle verified (one of the documented bypass methods is sufficient)
- Uninstall restores config files exactly; no orphaned plugin files left in `~/.config/sketchybar/plugins/agent-hooks/` unless `--keep-scripts` was passed
- `agent-hooks.log` shows `strategy=sessionstart` for sessions that started after install — strategy=fallback is acceptable for pre-existing sessions only
</acceptance_criteria>

---

### Task 14 — Document feature in README.md

**Type:** execute
**Wave:** 5
**Depends on:** Task 13
**Autonomous:** true

<action>
Append a `## Agent completion flash` section to the repo `README.md` with:
- One-paragraph what + why.
- Install instruction: `./install.sh` (mentions it wires Claude / Codex / Hermes if installed).
- Color customization: `theme.local.sh` overrides `COLOR_FLASH_CLAUDE / _CODEX / _HERMES`.
- Focus-suppress toggle: env var or `theme.local.sh`.
- Uninstall path: `sketchybar/plugins/agent-hooks/uninstall.sh`.
- Doctor command: `sketchybar/plugins/agent-hooks/doctor.sh`.
- Per-tool notes: Codex trust-hash on first run; Hermes auto-accept option.

Keep the section under 60 lines. Link to `.planning/phases/01-completion-flash/01-PLAN.md` for the design rationale.
</action>

<read_first>
- `README.md` (existing top-level README — match its formatting and section ordering)
</read_first>

<acceptance_criteria>
- `grep -F '## Agent completion flash' README.md` returns 1 line
- Section mentions all three tools, both customization paths (color + suppress), uninstall, doctor
- No marketing language; matches existing README tone (technical, terse)
</acceptance_criteria>

---

### Task 15 — Remove the spike from the live system, archive scripts

**Type:** execute
**Wave:** 5
**Depends on:** Task 11
**Autonomous:** true

<action>
Two-step:
1. Run `.planning/spikes/001-e2e-claude-flash/uninstall.sh` to remove its live hook wiring and restore its backup if any are still around. (`install.sh` Task 11 should have already stripped the entries — this is belt + suspenders.)
2. Do NOT delete the spike directory itself — it's preserved as research artifact + future debug reference. Add a final-line note to `spikes/001-e2e-claude-flash/README.md` Results section saying "Superseded by production code under `sketchybar/plugins/agent-hooks/`. Spike scripts retained for forensic value; install.sh / uninstall.sh in this dir should not be run on a system with the production install."

Run `doctor.sh` final time to confirm no spike entries remain.
</action>

<read_first>
- `.planning/spikes/001-e2e-claude-flash/uninstall.sh` (verify what it does before invoking)
- `.planning/spikes/001-e2e-claude-flash/README.md` (the file we are appending to)
</read_first>

<acceptance_criteria>
- After running spike uninstall.sh: `grep -r '.planning/spikes/001-e2e-claude-flash/' ~/.claude/settings.json ~/.codex/hooks.json` returns nothing
- Spike directory still exists with all files
- Spike README has the "superseded" note appended
- `doctor.sh` reports 0 spike entries in any config file
</acceptance_criteria>

---

## Verification (goal-backward)

For each must_have above:
1. **Claude completion → orange flash on Claude's space within 1s** — Task 13 step 3
2. **Codex completion → periwinkle flash within 1s** — Task 13 step 3
3. **Hermes completion → hermes-color flash within 1s** — Task 13 step 3
4. **Flash follows window across spaces** — Task 13 step 4
5. **focus_suppress disables flash on focused space** — Task 13 step 5
6. **Existing user hooks preserved** — Task 8/9/10 acceptance criteria + Task 13 step 7 log inspection
7. **Idempotent install/uninstall** — Task 11 acceptance criteria
8. **Spike entries removed by install** — Task 15

If any must_have fails verification: drop back to the relevant task, iterate. Do not call the phase done until all 8 pass.

---

## Decisions (locked during planning)

- **State dir:** `~/Library/Application Support/spacetag/sessions/` (not `/tmp`; survives reboot; pruned with 7-day TTL).
- **Backup dir:** `~/Library/Application Support/spacetag/backups/<YYYY-MM-DD>/`.
- **CLI shape:** No top-level `spacetag` CLI in this phase. Install/uninstall/doctor are bash scripts invoked directly from `sketchybar/plugins/agent-hooks/`. A wrapper CLI can be added later when other `spacetag` subcommands ship (see BACKLOG.md).
- **Hermes color:** Locked at `0xff8dbf8a` (sage green) — Task 0 done 2026-05-30.
- **Hermes auto-accept:** Adapter does NOT mutate the user's `hooks_auto_accept` setting. First-run trust prompt is documented instead.
- **Codex stdin payload:** session_id presence assumed (inferred from cross-tool parity). Task 11 install summary instructs the user to confirm on first prod Codex run; if absent, Codex falls back to PPID heuristic.
- **Branch:** `feat/completion-flash` (continues from spike commits in this branch's history).
- **Files in `~/.config/sketchybar/plugins/agent-hooks/` are deploy copies, not symlinks** (per project memory `live-config-deploy-copies.md` — repo edits propagate via `install.sh`, not auto-magically).

## Out of scope (defer to follow-up phases)

- GUI app customization surface for colors / suppress toggle (theme.local.sh sufficient for this phase).
- Gemini and Cursor adapters (see BACKLOG.md — research required first).
- Telemetry / metrics on flash counts.
- Per-tool stdin payload verification beyond Claude + Hermes (Codex assumed; verify on first prod run).
- Notification Center DB watcher (the "any app notification" Part 2 from the original idea).
- SessionEnd / on_session_end hook for proactive state-file cleanup (TTL prune in session-start.sh covers most cases).
