# Phase 01 — Parallel Execution Workflow

Companion to `01-PLAN.md`. Tasks fan out into 7 waves based on the read/write
DAG; max 5 agents per wave.

## Wave map

```
wave 0 ── T0 (DONE — Hermes color locked at 0xff8dbf8a)
   │
wave 1 ──┬── T1 theme.sh                ─┐
         └── T2 state.sh                 ├─ no shared files; safe to run in parallel
                                         │
wave 2 ──┬── T3 session-start.sh         │
         ├── T5 flash-listener.sh        ├─ each writes a single new file under
         └── T7 adapters/common.sh       │  agent-hooks/; no cross-writes
                                         │
wave 3 ──┬── T4 turn-end.sh              │
         ├── T6 sketchybarrc + watcher   │
         ├── T8 adapters/claude.sh       ├─ T8/T9/T10 share /adapters/ but
         ├── T9 adapters/codex.sh        │  each writes a different file
         └── T10 adapters/hermes.sh     ─┘
   │
wave 4 ── T11 install.sh + uninstall.sh    (depends on all of wave 1+2+3; serial)
   │
wave 5 ──┬── T12 doctor.sh
         └── T15 spike teardown          (both depend on T11; independent files)
   │
wave 6 ── T13 smoke verification         (MANUAL — needs the user observing pills)
   │
wave 7 ── T14 README documentation       (depends on T13 confirmation)
```

## Commit discipline

Each task agent commits independently when its acceptance criteria pass. Format:

```
feat(agent-hooks): TaskNN — <one-line summary>

<body — what landed, key constraints honored>

Per .planning/phases/01-completion-flash/01-PLAN.md, Task NN.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Wave 6 (manual UAT) is logged in PLAN.md by appending a "Verified" line at
the bottom of the task's section rather than via commit (commit comes from
the README task in wave 7).

## Race safety

- All wave 1+2 tasks write **distinct new files** — git's per-blob storage
  makes concurrent commits safe.
- Wave 3 has 5 agents but each writes a single distinct file (turn-end.sh,
  sketchybarrc, claude.sh, codex.sh, hermes.sh). `sketchybarrc` is the only
  pre-existing file touched in wave 3 and only T6 writes to it.
- Inter-wave: orchestrator waits for ALL wave-N agents to return before
  dispatching wave N+1, so dep ordering is preserved at the wave boundary.

## Failure recovery

If an agent fails its acceptance criteria:
1. Inspect agent return + log.
2. Re-spawn with a delta prompt (only the failing criterion + the read_first
   files for it).
3. Do not advance to next wave until all tasks in current wave pass.

If a commit fails (e.g. pre-commit hook rejects):
- Surface the hook output to the user. Do not bypass with `--no-verify`
  unless explicitly authorized.

## State at each wave boundary

After wave N completes successfully:
- `git log --oneline -N` shows N new feat(agent-hooks) commits since the plan
  commit.
- Working tree is clean (`git status --short` empty).
- `doctor.sh` is not yet expected to pass until wave 4 finishes.
