#!/usr/bin/env bash
# Spike 002 — captures Codex's Stop hook stdin payload + env so we can verify
# the schema matches Claude Code's (specifically: does it carry session_id?).
# Additive: installed alongside the existing vibe-island-bridge entry, doesn't
# replace it. Logs to /tmp/spike-002-codex.log.

set -u
LOG="/tmp/spike-002-codex.log"
{
  printf '\n=== %s pid=%s ppid=%s ===\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$PPID"
  printf -- '--- env (selected) ---\n'
  env | grep -E '^(CODEX|CLAUDE|SESSION|HOOK)' | sort
  printf -- '--- stdin payload ---\n'
  cat
  printf '\n--- end ---\n'
} >> "$LOG" 2>&1
exit 0
