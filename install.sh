#!/usr/bin/env bash
# install.sh — idempotent symlink installer for Space-Tag-CLI.
# Safe to re-run; replaces existing symlinks but refuses to clobber real files.

set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"

# ─── prereqs: auto-install brew deps, check-only for swift ───────────────
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
# swift ships with Xcode CLT — can't brew-install it.
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

# CLI on PATH: symlink into ~/.local/bin so `space-tag` works from any shell.
link "$PROJ/bin/space-tag" "$HOME/.local/bin/space-tag"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "warning: ~/.local/bin is not on your PATH — add it to use \`space-tag\` directly" >&2 ;;
esac

# Migrate the legacy auto-label state file to the renamed auto-tag path, so a
# previously-disabled toggle (the old `space-label-auto off`) is preserved
# instead of silently re-enabling on the next shell.
OLD_STATE="$HOME/.config/sketchybar/auto-label"
NEW_STATE="$HOME/.config/sketchybar/auto-tag"
if [ -f "$OLD_STATE" ] && [ ! -f "$NEW_STATE" ]; then
  mkdir -p "$HOME/.config/sketchybar"
  mv "$OLD_STATE" "$NEW_STATE"
  echo "migrated auto-label state → auto-tag"
fi

# Idempotent rc-file hook lines. First strip stale lines from retired paths
# (zsh/space-label.zsh, zsh/space-tag.zsh): those files no longer exist, so
# sourcing them errors on every new shell. Rewrite via temp + cat so a
# dotfiles symlink is preserved (mv would replace the symlink with a regular
# file). The hook shims only wire auto-tag-on-cd; the CLI itself is the
# standalone bin/space-tag.
ZSH_LINE="source $PROJ/shell/space-tag.zsh"
BASH_LINE="source $PROJ/shell/space-tag.bash"
STALE_1="source $PROJ/zsh/space-label.zsh"
STALE_2="source $PROJ/zsh/space-tag.zsh"
OLD_COMMENT="# space-labels: auto-label macOS spaces from git project"
if [ -f "$HOME/.zshrc" ] && grep -qxF -e "$STALE_1" -e "$STALE_2" "$HOME/.zshrc"; then
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
# bash hook: only if the user actually has a .bashrc.
if [ -f "$HOME/.bashrc" ] && ! grep -qxF "$BASH_LINE" "$HOME/.bashrc"; then
  printf '\n# space-tag-cli: auto-tag macOS spaces from git project\n%s\n' "$BASH_LINE" >> "$HOME/.bashrc"
  echo "appended hook source line to ~/.bashrc"
fi
# fish hook: only if the user actually has a fish config. conf.d files are
# sourced automatically, so a symlink is the whole installation.
if [ -d "$HOME/.config/fish" ]; then
  link "$PROJ/shell/space-tag.fish" "$HOME/.config/fish/conf.d/space-tag.fish"
fi

# Precompile the rename overlay into ~/.config/sketchybar/cache/ so the very
# first right-click is fast. Without this the click_script falls back to
# `/usr/bin/swift <file>` which JIT-compiles on every invocation (~1-2s lag).
# Falls back gracefully (the click_script will rebuild on demand) if this fails.
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
