#!/usr/bin/env bash

set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"

missing_brew=()
for dep in yabai sketchybar jq; do
  command -v "$dep" >/dev/null 2>&1 || missing_brew+=("$dep")
done
if [ "${#missing_brew[@]}" -gt 0 ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Missing dependencies: ${missing_brew[*]} — and Homebrew is not installed." >&2
    echo "Install Homebrew first: https://brew.sh" >&2
    exit 1
  fi
  echo "Installing missing dependencies: ${missing_brew[*]}"
  brew install "${missing_brew[@]}"
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Missing dependency: swift — run: xcode-select --install" >&2
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
link "$PROJ/sketchybar/plugins/layout.sh"        "$HOME/.config/sketchybar/plugins/layout.sh"
link "$PROJ/sketchybar/plugins/spaces.sh"        "$HOME/.config/sketchybar/plugins/spaces.sh"
link "$PROJ/sketchybar/plugins/space_click.sh"   "$HOME/.config/sketchybar/plugins/space_click.sh"
link "$PROJ/sketchybar/plugins/rename-overlay.swift" "$HOME/.config/sketchybar/plugins/rename-overlay.swift"

chmod +x "$PROJ/yabai/yabairc"
chmod +x "$PROJ/sketchybar/sketchybarrc"
chmod +x "$PROJ/sketchybar/plugins/"*.sh
chmod +x "$PROJ/bin/space-tag"

link "$PROJ/bin/space-tag" "$HOME/.local/bin/space-tag"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "warning: ~/.local/bin is not on your PATH — add it to use \`space-tag\` directly" >&2 ;;
esac

OLD_STATE="$HOME/.config/sketchybar/auto-label"
NEW_STATE="$HOME/.config/sketchybar/auto-tag"
if [ -f "$OLD_STATE" ] && [ ! -f "$NEW_STATE" ]; then
  mkdir -p "$HOME/.config/sketchybar"
  mv "$OLD_STATE" "$NEW_STATE"
  echo "migrated auto-label state → auto-tag"
fi

ZSH_LINE="source $PROJ/shell/space-tag.zsh"
BASH_LINE="source $PROJ/shell/space-tag.bash"
STALE_1="source $PROJ/zsh/space-label.zsh"
STALE_2="source $PROJ/zsh/space-tag.zsh"
OLD_COMMENT="# space-labels: auto-label macOS spaces from git project"
if [ -f "$HOME/.zshrc" ] && grep -qxF -e "$STALE_1" -e "$STALE_2" "$HOME/.zshrc"; then
  # Preserve dotfile symlinks by rewriting through the existing inode.
  tmp=$(mktemp)
  grep -vxF -e "$STALE_1" -e "$STALE_2" -e "$OLD_COMMENT" "$HOME/.zshrc" > "$tmp" || true
  cat "$tmp" > "$HOME/.zshrc"
  rm -f "$tmp"
  echo "removed stale hook source line(s) from ~/.zshrc"
fi
if ! grep -qxF "$ZSH_LINE" "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# space-tag-cli: auto-tag macOS spaces from git project\n%s\n' "$ZSH_LINE" >> "$HOME/.zshrc"
  echo "appended hook source line to ~/.zshrc"
else
  echo "~/.zshrc already sources the zsh hook"
fi
if [ -f "$HOME/.bashrc" ] && ! grep -qxF "$BASH_LINE" "$HOME/.bashrc"; then
  printf '\n# space-tag-cli: auto-tag macOS spaces from git project\n%s\n' "$BASH_LINE" >> "$HOME/.bashrc"
  echo "appended hook source line to ~/.bashrc"
fi
if [ -d "$HOME/.config/fish" ]; then
  link "$PROJ/shell/space-tag.fish" "$HOME/.config/fish/conf.d/space-tag.fish"
fi

CACHE="$HOME/.config/sketchybar/cache"
mkdir -p "$CACHE"
if swiftc -o "$CACHE/rename-overlay" "$PROJ/sketchybar/plugins/rename-overlay.swift" 2>/dev/null; then
  echo "compiled $CACHE/rename-overlay"
else
  echo "warning: rename-overlay precompile failed (right-click will rebuild on demand)" >&2
fi

echo
echo "Install done. Next:"
echo "  yabai --start-service"
echo "  brew services start sketchybar"
echo "  exec \$SHELL   # reload shell to pick up the auto-tag hook"
case " ${missing_brew[*]-} " in
  *" yabai "*)
    echo
    echo "yabai was freshly installed — grant it Accessibility when prompted"
    echo "(System Settings > Privacy & Security > Accessibility), then start the service."
    ;;
esac
