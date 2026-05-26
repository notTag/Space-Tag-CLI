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

# Pill position, remembered PER DISPLAY. Each physical display is keyed by its
# stable yabai UUID; setting a mode while focused on a display persists that
# display's choice to ~/.config/sketchybar/position.d/<uuid>. The single bar
# follows the focused display and layout.sh applies that display's mode, falling
# back to the shared default (~/.config/sketchybar/position), then center.
# Triggers position_change so the bar reflows immediately.
#   space-position                  → show THIS display's effective mode
#   space-position <mode>           → set THIS display's mode (persisted per display)
#   space-position <mode> --default → set the shared default (displays w/o an override)
#   space-position --default <mode> → same
#   space-position --clear          → drop THIS display's override (use the default)
#   space-position --list           → list the default + every per-display override
# <mode> ∈ {center | notch-left | notch-right | left | right}
#   center      → in menu bar, centered
#   notch-left  → flush left of the notch (2pt gap); on a flat display → left
#   notch-right → flush right of the notch (2pt gap); on a flat display → right
#   left        → below menu bar, left edge
#   right       → below menu bar, right edge
_space_position_valid() {
  case "$1" in center|notch-left|notch-right|left|right) return 0 ;; *) return 1 ;; esac
}
_space_position_uuid() {
  yabai -m query --displays --display 2>/dev/null | jq -r '.uuid // empty'
}
space-position() {
  local cfg="$HOME/.config/sketchybar"
  local pos_file="$cfg/position" pos_dir="$cfg/position.d"
  local usage="usage: space-position [<mode>|--default <mode>|--clear|--list]   mode ∈ {center,notch-left,notch-right,left,right}"
  local active; active=$(_space_position_uuid)

  case "$1" in
    "")  # show this display's effective mode + where it came from
      if [[ -n "$active" && -f "$pos_dir/$active" ]]; then
        echo "$(cat "$pos_dir/$active")  (this display)"
      else
        echo "$(cat "$pos_file" 2>/dev/null || echo center)  (default)"
      fi
      return 0
      ;;
    --list)
      echo "default      $(cat "$pos_file" 2>/dev/null || echo center)"
      local f u
      for f in "$pos_dir"/*(N); do
        u=${f:t}
        if [[ "$u" == "$active" ]]; then
          echo "$u  $(cat "$f")  <- this display"
        else
          echo "$u  $(cat "$f")"
        fi
      done
      return 0
      ;;
    --clear)
      [[ -z "$active" ]] && { echo "no active display (is yabai running?)" >&2; return 1; }
      rm -f "$pos_dir/$active"
      sketchybar --trigger position_change >/dev/null 2>&1 &!
      echo "this display ($active) → default"
      return 0
      ;;
    --default)
      _space_position_valid "$2" || { echo "$usage" >&2; return 1; }
      mkdir -p "$cfg"; printf '%s\n' "$2" > "$pos_file"
      sketchybar --trigger position_change >/dev/null 2>&1 &!
      echo "default position → $2"
      return 0
      ;;
  esac

  # space-position <mode> [--default]
  _space_position_valid "$1" || { echo "$usage" >&2; return 1; }
  if [[ "$2" == --default ]]; then
    mkdir -p "$cfg"; printf '%s\n' "$1" > "$pos_file"
    sketchybar --trigger position_change >/dev/null 2>&1 &!
    echo "default position → $1"
  else
    [[ -z "$active" ]] && { echo "no active display (is yabai running?)" >&2; return 1; }
    mkdir -p "$pos_dir"; printf '%s\n' "$1" > "$pos_dir/$active"
    sketchybar --trigger position_change >/dev/null 2>&1 &!
    echo "this display ($active) → $1"
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _space_label_current

# Fire once on shell startup for current dir.
_space_label_current
