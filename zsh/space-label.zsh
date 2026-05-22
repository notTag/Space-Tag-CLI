# space-label.zsh — auto-label current macOS space with current git project name.
# Hook fires on every `cd`. If you're in a git repo, the active yabai space
# gets labeled with the basename of the repo root. Sketchybar pill updates
# automatically via the space_change trigger.

_space_label_current() {
  command -v yabai >/dev/null 2>&1 || return
  command -v jq    >/dev/null 2>&1 || return

  local root name sid
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  name=${root:t}                       # basename, zsh modifier
  sid=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
  [[ -z "$sid" ]] && return

  yabai -m space "$sid" --label "$name" 2>/dev/null
  command -v sketchybar >/dev/null 2>&1 && \
    sketchybar --trigger space_change >/dev/null 2>&1 &!
}

# Manual override: `space-label <name>` to set arbitrary label on current space.
space-label() {
  local sid
  sid=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
  [[ -z "$sid" ]] && { echo "no active space" >&2; return 1; }
  yabai -m space "$sid" --label "$1"
  sketchybar --trigger space_change >/dev/null 2>&1 &!
  echo "space $sid → $1"
}

# Clear label on current space.
space-unlabel() {
  local sid
  sid=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
  [[ -z "$sid" ]] && { echo "no active space" >&2; return 1; }
  yabai -m space "$sid" --label ""
  sketchybar --trigger space_change >/dev/null 2>&1 &!
  echo "space $sid → (cleared)"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _space_label_current

# Fire once on shell startup for current dir.
_space_label_current
