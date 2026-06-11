# space-tag hook (zsh) — auto-tag the active space with the current git
# project name on every cd. All logic lives in bin/space-tag; this shim only
# wires the chpwd hook.

# Resolve bin/space-tag relative to this file so PATH setup isn't required.
_space_tag_bin="${${(%):-%x}:A:h:h}/bin/space-tag"

_space_tag_chpwd() { "$_space_tag_bin" __autotag >/dev/null 2>&1 &! }

# Wrapper fn: `space-tag source` must exec in THIS shell (a child process
# can't replace its parent); everything else forwards to the binary.
space-tag() {
  if [[ "${1:-}" == source ]]; then
    exec "${SHELL:-/bin/zsh}"
  fi
  "$_space_tag_bin" "$@"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _space_tag_chpwd

# Fire once on shell startup for the starting dir.
_space_tag_chpwd
