# space-tag hook (fish) — auto-tag the active space with the current git
# project name on directory change. All logic lives in bin/space-tag; this
# shim only wires the hook. Needs fish ≥ 3.5 (the `path` builtin).
#
# install.sh symlinks this into ~/.config/fish/conf.d/, which fish sources
# automatically — `path resolve` follows the symlink back to the repo so
# bin/space-tag is found without PATH setup.

set -g _space_tag_bin (path resolve (status filename) | path dirname | path dirname)/bin/space-tag

function _space_tag_chpwd --on-variable PWD
    $_space_tag_bin __autotag >/dev/null 2>&1 &
    disown 2>/dev/null
end

# Fire once on shell startup for the starting dir.
_space_tag_chpwd

# Wrapper fn: `space-tag source` must exec in THIS shell (a child process
# can't replace its parent); everything else forwards to the binary.
function space-tag
    if test "$argv[1]" = source
        if set -q SHELL[1]
            exec $SHELL
        else
            exec fish
        end
    end
    $_space_tag_bin $argv
end
