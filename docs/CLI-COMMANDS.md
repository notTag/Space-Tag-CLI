# CLI command spec (final)

Single entry point: `bin/space-tag`, standalone POSIX script — no shell
dependency. Git-style subcommands; bare subcommand prints state.

```
space-tag <name> [space#]          # tag a space (current space if no number)
space-tag -- <name> [space#]       # literal name (escapes reserved words)
space-tag clear                    # clear the current space's tag
space-tag auto [on|off]            # get/set auto-tagging on cd
space-tag display [current|all]    # get/set which spaces the bar shows
space-tag position [<mode>]        # get/set pill placement for THIS display
space-tag position default <mode>  # set fallback for displays without their own setting
space-tag position clear           # drop this display's setting
space-tag position list            # default + every per-display override
space-tag reload                   # reload sketchybar (wraps `sketchybar --reload`)
space-tag uninstall [options]      # stop services and remove Space-Tag-CLI
space-tag source                   # reload your shell (exec $SHELL; via hook wrapper fn)
space-tag version                  # show installed release version (-v/--version also work)
space-tag help                     # usage (-h/--help also work)
```

position modes: `center | notch-left | notch-right | left | right`

## Decisions

- Subcommands over flags — kills the `-c`/`-C` case trap and optional-flag-arg
  parsing ambiguity from the original flag sketch.
- `display current|all` replaces `space-per-display on|off` — descriptive
  values. On-disk file keeps `on/off` (`current` = on) so `spaces.sh` reads it
  unchanged.
- Nested position verbs (`default`, `clear`, `list`) — no flag-modifying-flag.
- `--` escape hatch guards tags that collide with subcommand names.
- `reload` wraps `sketchybar --reload` so theme/config edits don't need a
  second tool on the user's fingers.
- `uninstall` delegates to the repository uninstaller. It accepts `--dry-run`,
  `--keep-brew`, and `--yes`.
- `source` lives in the hook shims as a `space-tag` wrapper function (rbenv
  style) — a child process can't exec its parent shell, so the binary only
  prints guidance when the hook isn't loaded.
- Clean break: no deprecated aliases for `space-untag` / `space-tag-auto` /
  `space-per-display` / `space-position`.
- Auto-tag-on-cd lives in `shell/space-tag.{zsh,bash,fish}` hooks, which call
  the hidden `space-tag __autotag` subcommand. Other shells can wire their own
  cd hook to the same call.
