#!/usr/bin/env bash

set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
KEEP_BREW=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --keep-brew) KEEP_BREW=1 ;;
    --yes)       ASSUME_YES=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@" || true
  fi
}

remove_path() {
  local p="$1"
  case "$p" in
    ""|/|"$HOME") echo "REFUSING to remove '$p'" >&2; return 1 ;;
  esac
  if [ -e "$p" ] || [ -L "$p" ]; then
    run rm -rf "$p"
  fi
}

strip_rc_hook() {
  local rc="$1" src_line="$2"
  local comment="# space-tag-cli: auto-tag macOS spaces from git project"
  [ -f "$rc" ] || return 0
  grep -qxF "$src_line" "$rc" 2>/dev/null || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] strip hook lines from $rc"
    return 0
  fi
  local tmp
  # Preserve dotfile symlinks by rewriting through the existing inode.
  tmp=$(mktemp)
  grep -vxF -e "$src_line" -e "$comment" "$rc" > "$tmp" || true
  cat "$tmp" > "$rc"
  rm -f "$tmp"
  echo "stripped hook lines from $rc"
}

echo "Space-Tag-CLI uninstall"
echo "  removes: config symlinks, state files, shell hooks, ~/.local/bin/space-tag,"
echo "           agent-hooks plugin + adapters, ~/Library/Application Support/spacetag,"
echo "           yabai + sketchybar services$( [ "$KEEP_BREW" -eq 1 ] && echo ' (keeping brew packages)' || echo ', brew packages (sketchybar yabai)')"
echo "  sudo needed for: yabai --uninstall-sa (if present), tccutil Accessibility reset"
echo
if [ "$ASSUME_YES" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in [Yy]*) ;; *) echo "aborted"; exit 0 ;; esac
fi

if command -v yabai >/dev/null 2>&1; then
  run yabai --stop-service
  run yabai --uninstall-service
fi
if command -v brew >/dev/null 2>&1; then
  run brew services stop sketchybar
fi
run pkill -x sketchybar
run pkill -x yabai
run pkill -f "$HOME/.config/sketchybar/cache/rename-overlay"

UID_NUM="$(id -u)"
for label in com.koekeishiya.yabai homebrew.mxcl.sketchybar; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  if launchctl print "gui/$UID_NUM/$label" >/dev/null 2>&1; then
    run launchctl bootout "gui/$UID_NUM/$label"
  fi
  remove_path "$plist"
done

if command -v yabai >/dev/null 2>&1 && [ -e "/Library/ScriptingAdditions/yabai.osax" ]; then
  echo "yabai scripting addition detected — removing (needs sudo)"
  run sudo yabai --uninstall-sa
fi

if [ "$KEEP_BREW" -ne 1 ] && command -v brew >/dev/null 2>&1; then
  for pkg in sketchybar yabai; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      run brew uninstall "$pkg"
    fi
  done
fi

AGENT_HOOKS_UNINSTALL="$PROJ/sketchybar/plugins/agent-hooks/uninstall.sh"
if [ -d "$HOME/.config/sketchybar/plugins/agent-hooks" ] && [ -x "$AGENT_HOOKS_UNINSTALL" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] $AGENT_HOOKS_UNINSTALL"
  else
    run "$AGENT_HOOKS_UNINSTALL"
  fi
fi
remove_path "$HOME/.config/sketchybar/plugins/agent-hooks"

remove_path "$HOME/.config/yabai/yabairc"
remove_path "$HOME/.config/sketchybar/sketchybarrc"
remove_path "$HOME/.config/sketchybar/theme.sh"
remove_path "$HOME/.config/sketchybar/plugins/space.sh"
remove_path "$HOME/.config/sketchybar/plugins/clock.sh"
remove_path "$HOME/.config/sketchybar/plugins/layout.sh"
remove_path "$HOME/.config/sketchybar/plugins/spaces.sh"
remove_path "$HOME/.config/sketchybar/plugins/space_click.sh"
remove_path "$HOME/.config/sketchybar/plugins/rename-overlay.swift"
remove_path "$HOME/.local/bin/space-tag"
remove_path "$HOME/.config/fish/conf.d/space-tag.fish"

remove_path "$HOME/.config/sketchybar/theme.local.sh"
remove_path "$HOME/.config/sketchybar/auto-tag"
remove_path "$HOME/.config/sketchybar/auto-label"
remove_path "$HOME/.config/sketchybar/per-display-spaces"
remove_path "$HOME/.config/sketchybar/position"
remove_path "$HOME/.config/sketchybar/position.d"
remove_path "$HOME/.config/sketchybar/cache"
remove_path "$HOME/Library/Application Support/spacetag"
remove_path "/tmp/agent-hooks.log"

for d in "$HOME/.config/sketchybar/plugins" "$HOME/.config/sketchybar" "$HOME/.config/yabai"; do
  [ -d "$d" ] && run rmdir "$d"
done

strip_rc_hook "$HOME/.zshrc"  "source $PROJ/shell/space-tag.zsh"
strip_rc_hook "$HOME/.bashrc" "source $PROJ/shell/space-tag.bash"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] sudo tccutil reset Accessibility com.koekeishiya.yabai"
else
  echo "Resetting Accessibility grant for yabai (needs sudo)"
  sudo tccutil reset Accessibility com.koekeishiya.yabai || \
    echo "warning: tccutil reset failed — remove yabai manually in System Settings > Privacy & Security > Accessibility" >&2
fi

echo
leftovers=0
for p in \
  "$HOME/.config/sketchybar/sketchybarrc" \
  "$HOME/.config/sketchybar/plugins/agent-hooks" \
  "$HOME/.config/yabai/yabairc" \
  "$HOME/Library/Application Support/spacetag" \
  "$HOME/.local/bin/space-tag" \
  "$HOME/.config/fish/conf.d/space-tag.fish" \
  "$HOME/Library/LaunchAgents/com.koekeishiya.yabai.plist" \
  "$HOME/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist"; do
  if [ -e "$p" ] || [ -L "$p" ]; then echo "still present: $p"; leftovers=1; fi
done
if grep -q "space-tag" "$HOME/.zshrc" 2>/dev/null; then
  echo "still present: space-tag lines in ~/.zshrc"; leftovers=1
fi
if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run complete — nothing was removed."
elif [ "$leftovers" -eq 0 ]; then
  echo "Uninstall complete. Reload your shell: exec \$SHELL"
else
  echo "Uninstall finished with leftovers listed above."
fi
