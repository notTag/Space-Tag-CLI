# space-tag hook (bash) — auto-tag the active space with the current git
# project name on directory change. bash has no chpwd hook, so a
# PROMPT_COMMAND entry checks for a pwd change before each prompt. All logic
# lives in bin/space-tag; this shim only detects the change.

# Resolve bin/space-tag relative to this file so PATH setup isn't required.
_space_tag_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/space-tag"

# Starts empty so the first prompt fires once for the shell's starting dir.
_space_tag_pwd=""

_space_tag_prompt() {
  [[ "$PWD" == "$_space_tag_pwd" ]] && return
  _space_tag_pwd="$PWD"
  ("$_space_tag_bin" __autotag >/dev/null 2>&1 &)
}

PROMPT_COMMAND="_space_tag_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

# Wrapper fn: `space-tag source` must exec in THIS shell (a child process
# can't replace its parent); everything else forwards to the binary.
space-tag() {
  if [ "${1:-}" = source ]; then
    exec "${SHELL:-/bin/bash}"
  fi
  "$_space_tag_bin" "$@"
}
