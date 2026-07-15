
_space_tag_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/space-tag"

_space_tag_pwd=""

_space_tag_prompt() {
  [[ "$PWD" == "$_space_tag_pwd" ]] && return
  _space_tag_pwd="$PWD"
  ("$_space_tag_bin" __autotag >/dev/null 2>&1 &)
}

PROMPT_COMMAND="_space_tag_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

space-tag() {
  if [ "${1:-}" = source ]; then
    # A child process cannot replace its parent shell.
    exec "${SHELL:-/bin/bash}"
  fi
  "$_space_tag_bin" "$@"
}
