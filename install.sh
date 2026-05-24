#!/usr/bin/env bash
# install.sh — idempotent symlink installer for space-labels.
# Safe to re-run; replaces existing symlinks but refuses to clobber real files.

set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"

# ─── prereq check ────────────────────────────────────────────────────────
missing=()
for dep in yabai sketchybar jq swift; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing dependencies: ${missing[*]}" >&2
  echo "Install with: brew install yabai sketchybar jq    # swift ships with Xcode CLT" >&2
  exit 1
fi

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    echo "REFUSING to clobber real file at $dst — move it aside first." >&2
    exit 1
  fi
  ln -s "$src" "$dst"
  echo "linked $dst → $src"
}

link "$PROJ/yabai/yabairc"                       "$HOME/.config/yabai/yabairc"
link "$PROJ/sketchybar/sketchybarrc"             "$HOME/.config/sketchybar/sketchybarrc"
link "$PROJ/sketchybar/theme.sh"                 "$HOME/.config/sketchybar/theme.sh"
link "$PROJ/sketchybar/plugins/space.sh"         "$HOME/.config/sketchybar/plugins/space.sh"
link "$PROJ/sketchybar/plugins/clock.sh"         "$HOME/.config/sketchybar/plugins/clock.sh"
link "$PROJ/sketchybar/plugins/y_offset.sh"      "$HOME/.config/sketchybar/plugins/y_offset.sh"
link "$PROJ/sketchybar/plugins/position.sh"      "$HOME/.config/sketchybar/plugins/position.sh"

chmod +x "$PROJ/yabai/yabairc"
chmod +x "$PROJ/sketchybar/sketchybarrc"
chmod +x "$PROJ/sketchybar/plugins/"*.sh

# Idempotent .zshrc source line.
ZSH_LINE="source $PROJ/zsh/space-label.zsh"
if ! grep -qxF "$ZSH_LINE" "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# space-labels: auto-label macOS spaces from git project\n%s\n' "$ZSH_LINE" >> "$HOME/.zshrc"
  echo "appended source line to ~/.zshrc"
else
  echo "~/.zshrc already sources space-label.zsh"
fi

echo
echo "Install done. Next:"
echo "  yabai --start-service"
echo "  brew services start sketchybar"
echo "  exec zsh   # reload shell to pick up hook"
