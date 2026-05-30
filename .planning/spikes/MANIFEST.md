# Spike Manifest

## Idea

Flash a SpaceTag pill with a per-tool color when Claude Code or Codex CLI finish
their turn — so the user sees "agent done" at a glance regardless of which space
the terminal lives on. End-to-end loop: agent completion hook → script walks the
process tree to find the terminal's window → yabai resolves that window's space
→ sketchybar custom event flashes the matching pill background → fades back to
default. Part 2 (future, separate phase) generalizes the same flash sink to any
macOS NotificationCenter event.

## Requirements

Decisions locked from the pre-spike discussion. Non-negotiable for the real build.

- Flash target: pill **background** (not icon/label color).
- Color: **per tool** — claude = orange, codex = periwinkle. Both **customizable**
  via `theme.local.sh` (CLI) and the SpaceTag GUI app.
- Focus behavior: **always flash by default**, including on the currently-focused
  space. Suppress-when-focused = optional toggle (CLI flag + GUI checkbox).
- All wiring lives in this branch — production paths untouched until spike verdict.

## Spikes

| # | Name | Type | Validates | Verdict | Tags |
|---|------|------|-----------|---------|------|
| 001 | e2e-claude-flash | standard | Given Claude Code finishes a turn in a terminal on space N, when its Stop hook fires a script that walks PPID → yabai window → space, then the pill for space N flashes orange (~1s) and reverts cleanly. | **VALIDATED ✓** | claude-code, hooks, ppid, yabai, sketchybar, flash, session-start |
| 002 | codex-hook-discovery | standard | Given the Codex CLI, when we inspect its config surface, then we either confirm a Stop-equivalent shell hook exists OR confirm we need a JSONL-tail-watcher fallback (and which file to tail). | **VALIDATED ✓** | codex, hooks, research, cross-tool-compat |
