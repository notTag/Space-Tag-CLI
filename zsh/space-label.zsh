# space-label.zsh — auto-label current macOS space with current git project name.
# Hook fires on every `cd`. If you're in a git repo, the active yabai space
# gets labeled with the basename of the repo root. Sketchybar pill updates
# automatically via the space_change trigger.

_space_label_current() {
  # Honor the auto-label toggle: SPACE_LABEL_AUTO env var wins (per-shell
  # override), otherwise fall back to the persisted state. Empty means on.
  local auto=${SPACE_LABEL_AUTO:-$(cat "$HOME/.config/sketchybar/auto-label" 2>/dev/null)}
  [[ "$auto" == off ]] && return

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

# Manual override: set an arbitrary label on a space.
#   space-label <name>          → label the current space
#   space-label <name> <number> → label the space with that index
space-label() {
  local name="$1" sid="$2"
  if [[ -n "$sid" ]]; then
    [[ "$sid" == <-> ]] || { echo "space number must be numeric: $sid" >&2; return 1; }
  else
    sid=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
    [[ -z "$sid" ]] && { echo "no active space" >&2; return 1; }
  fi
  yabai -m space "$sid" --label "$name" || return 1
  sketchybar --trigger space_change >/dev/null 2>&1 &!
  echo "space $sid → $name"
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

# Toggle automatic labeling on cd. State persists to
# ~/.config/sketchybar/auto-label so it survives new shells. For a one-off
# override in the current shell, export SPACE_LABEL_AUTO=off instead.
#   space-label-auto            → print current state
#   space-label-auto on         → enable cd auto-labeling (default)
#   space-label-auto off        → disable cd auto-labeling
space-label-auto() {
  local state="$1" file="$HOME/.config/sketchybar/auto-label"
  if [[ -z "$state" ]]; then
    [[ "$(cat "$file" 2>/dev/null)" == off ]] && echo off || echo on
    return
  fi
  case "$state" in
    on|off) ;;
    *) echo "usage: space-label-auto {on|off}" >&2; return 1 ;;
  esac
  mkdir -p "$HOME/.config/sketchybar"
  printf '%s\n' "$state" > "$file"
  echo "auto-label → $state"
}

# Set pill position. Persists to ~/.config/sketchybar/position so the layout
# survives sketchybar reloads, then triggers position_change so the bar +
# pills reflow without waiting for a display switch.
#   space-position                 → print current mode
#   space-position center          → default (in menu bar, centered)
#   space-position notch-left      → flush left of the notch, 2pt gap
#   space-position notch-right     → flush right of the notch, 2pt gap
#   space-position left            → below menu bar, left edge, 2pt gap
#   space-position right           → below menu bar, right edge, 2pt gap
space-position() {
  local pos="$1"
  if [[ -z "$pos" ]]; then
    cat "$HOME/.config/sketchybar/position" 2>/dev/null || echo center
    return
  fi
  case "$pos" in
    center|notch-left|notch-right|left|right) ;;
    *)
      echo "usage: space-position {center|notch-left|notch-right|left|right}" >&2
      return 1
      ;;
  esac
  mkdir -p "$HOME/.config/sketchybar"
  printf '%s\n' "$pos" > "$HOME/.config/sketchybar/position"
  sketchybar --trigger position_change >/dev/null 2>&1 &!
  echo "label position → $pos"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _space_label_current

# Fire once on shell startup for current dir.
_space_label_current
