
_space_tag_bin="${${(%):-%x}:A:h:h}/bin/space-tag"

_space_tag_chpwd() { "$_space_tag_bin" __autotag >/dev/null 2>&1 &! }

space-tag() {
  if [[ "${1:-}" == source ]]; then
    # A child process cannot replace its parent shell.
    exec "${SHELL:-/bin/zsh}"
  fi
  "$_space_tag_bin" "$@"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _space_tag_chpwd

_space_tag_chpwd
