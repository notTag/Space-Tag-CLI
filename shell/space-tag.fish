
set -g _space_tag_bin (path resolve (status filename) | path dirname | path dirname)/bin/space-tag

function _space_tag_chpwd --on-variable PWD
    $_space_tag_bin __autotag >/dev/null 2>&1 &
    disown 2>/dev/null
end

_space_tag_chpwd

function space-tag
    if test "$argv[1]" = source
        # A child process cannot replace its parent shell.
        if set -q SHELL[1]
            exec $SHELL
        else
            exec fish
        end
    end
    $_space_tag_bin $argv
end
