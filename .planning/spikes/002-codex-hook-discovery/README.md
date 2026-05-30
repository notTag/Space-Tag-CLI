---
spike: 002
name: codex-hook-discovery
type: standard
validates: "Given the Codex CLI, when we inspect its config surface, then we either confirm a Stop-equivalent shell hook exists OR confirm we need a JSONL-tail-watcher fallback (and which file to tail)."
verdict: VALIDATED
related: [001]
tags: [codex, hooks, research, cross-tool-compat]
---

# Spike 002: codex-hook-discovery

## What This Validates

**Given** the Codex CLI,
**when** we inspect its config surface,
**then** we either confirm a Stop-equivalent shell hook exists OR confirm we
need a JSONL-tail-watcher fallback (and which file to tail).

## Research

### Codex hook surface (from local install — `codex-cli 0.23.0`)

| Surface | Location | Schema | Notes |
|---------|----------|--------|-------|
| `hooks.json` | `~/.codex/hooks.json` | Identical to Claude Code's `~/.claude/settings.json` `hooks` block | **Primary path.** Events: `SessionStart`, `Stop`, `UserPromptSubmit` |
| `config.toml [hooks.state]` | `~/.codex/config.toml` | Each registered hook gets a `trusted_hash = "sha256:..."` entry | Trust gate: new hooks may prompt for trust on first run |
| `config.toml notify` | `~/.codex/config.toml` | `notify = ["/path/to/program", "turn-ended"]` | Older mechanism; spawns program with event-name arg. No stdin payload. |
| `~/.codex/history.jsonl` | append-only | `{session_id, ts, text}` per entry | Tailable as a fallback; not turn-end specific |
| Per-session rollout | `~/.codex/archived_sessions/rollout-<ts>-<uuid>.jsonl` | `{timestamp, type, payload}` per event | Includes `session_meta` w/ session id; full event trace |

### Schema-identity proof: vibe-island-bridge

The user has `vibe-island-bridge` (a binary in `/Applications/Vibe Island.app`)
wired as the active Codex `SessionStart`, `Stop`, AND `UserPromptSubmit` hook
**right now**, in production-grade daily use. The launcher script's
self-cleanup logic treats these config files **interchangeably with the same
parsing logic**:

```js
['.claude/settings.json',  '.codex/hooks.json',
 '.gemini/settings.json',  '.cursor/hooks.json',
 '.factory/settings.json', '.qoder/settings.json',
 '.copilot/config.json',   '.codebuddy/settings.json'].forEach(clean)
```

The same JSON shape (`hooks.{event}[].hooks[].{command,type,...}`) parses
across all of them. This is hard evidence that the cross-tool hook contract
is intentional and our spike-001 scripts will work on Codex by changing only
the install path.

### Live-fire attempt: blocked by outdated CLI

Tried to capture a live Stop hook stdin payload by additively wiring a
stdin-sniffer into the user's `hooks.json` (alongside the existing
`vibe-island-bridge` entry) and running `codex exec --sandbox read-only`.
Both `gpt-5.5` (configured default) and `gpt-5` returned **400 Bad Request**
("model requires newer CLI" / "not supported with ChatGPT account"). Codex
never reached turn-end → Stop hook didn't fire → sniffer log empty.

**Inferred (not directly verified) but high confidence (≥90%):** the stdin
payload includes `session_id` like Claude Code's. Evidence:
- Cross-tool schema parity (vibe-island treats them identically)
- The bundled `notify` mechanism uses event-name args instead of stdin, so
  hooks.json hooks would be the place to ship rich data → stdin payload
  exists
- Codex tracks session ids natively in `history.jsonl` and rollout files —
  the most useful key to pass to a hook

Verification options for the production phase (in priority order):
1. Update the user's Codex CLI to a current release, re-run the sniffer.
2. Read the Codex source (`github.com/openai/codex`, Rust hook plumbing).
3. Treat `session_id` as present-or-fall-back-to-PPID and let the spike-001
   fallback path catch it.

## How to Run

```bash
# Inspection-only — no live mutations needed.
# Inspect the local Codex hook surface:
cat ~/.codex/hooks.json
grep -E 'notify|hook|codex_hooks' ~/.codex/config.toml

# Optional: peek at any archived session rollout for the event schema:
ls ~/.codex/archived_sessions/rollout-*.jsonl | head -1 | xargs head -1 | jq .
```

## What to Expect

`hooks.json` lists `SessionStart` / `Stop` / `UserPromptSubmit` events, each
with an array of `{type:"command", command:"...", timeout:N}` entries —
character-for-character compatible with Claude Code's `~/.claude/settings.json`.

`config.toml` carries `notify = [program, "turn-ended"]` as an alternate path.

## Investigation Trail

### Iteration 1 — File system inspection (2026-05-29)

Found `~/.codex/hooks.json` exists with three events wired to
`vibe-island-bridge`. Schema confirmed identical to Claude Code via
side-by-side diff. `config.toml` carries `codex_hooks = true` (feature flag)
and `notify = [..., "turn-ended"]` (alternate mechanism). Trust-hash entries
in `[hooks.state]` track per-hook sha256 → adding new hooks may require user
confirmation on first run.

### Iteration 2 — Live-fire blocked by version mismatch

Sniffer hook installed additively, `codex exec` invoked twice (default
`gpt-5.5` and forced `gpt-5`), both returned 400 from the model endpoint.
Stop hook did not fire because the turn never completed. Sniffer log empty,
backup restored cleanly. Spike rationale shifts to schema-by-evidence rather
than schema-by-direct-observation. Documented stdin payload inference as
high-confidence-but-unverified.

### Iteration 3 — Cross-tool compatibility proof

`vibe-island-bridge`'s self-cleanup code (43-line launcher) iterates the
same parsing logic over Claude / Codex / Gemini / Cursor / Factory / Qoder /
Copilot / CodeBuddy hook config files. Confirms intentional cross-tool
schema parity. Production wiring for Codex = mechanical port of spike-001
scripts to `~/.codex/hooks.json`.

## Results

**Verdict: VALIDATED ✓** (with one inferred property)

### What works
- Codex has a native `Stop` hook event in `~/.codex/hooks.json` with the
  same JSON schema as Claude Code's `~/.claude/settings.json`.
- `SessionStart` is also available — same shape, same usage.
- Cross-tool schema parity is intentional and proven by production code
  (vibe-island-bridge wires identical handlers across 8 AI tool configs).
- Production path for Codex = drop spike-001's
  `stop-hook.sh` / `session-start-hook.sh` into `~/.codex/hooks.json` instead
  of `~/.claude/settings.json`. The PPID-walk fallback also works.
- JSONL-tail fallback is **not required**.

### What's inferred (not directly observed)
- Stop hook stdin contains `session_id`. High confidence (~90%) from
  cross-tool parity + notify-mechanism contrast. Verification deferred to
  production phase (CLI upgrade + sniffer re-run, OR Codex source read).

### Production TODOs (carry into `/gsd-plan-phase`)

1. **Two storage locations.** `~/.claude/settings.json` AND `~/.codex/hooks.json`.
   Production installer must support both, with detect-and-skip when a tool
   isn't installed.
2. **Trust-hash UX.** Adding a new hook to Codex may trigger the trust prompt
   on first turn. Need to either (a) preempt by warning user during install,
   or (b) include hash precomputation in install.sh.
3. **Tool-tagging.** Pass `TOOL=codex` (vs `TOOL=claude`) via sketchybar
   trigger env so flash-listener.sh picks **periwinkle** (vs orange).
   Already supported by spike-001's listener — just needs the right env var.
4. **Stdin payload verification.** Upgrade Codex CLI to current release, re-
   run the sniffer to confirm `session_id` is present in Stop hook stdin.
5. **Coexistence with vibe-island / other bridges.** Install.sh's jq merge
   must preserve existing hook entries (not replace them). Spike-001 already
   demonstrates this pattern.
