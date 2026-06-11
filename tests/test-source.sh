#!/bin/sh
# Source: shell reload. The binary can only print guidance (a child process
# can't exec the parent shell); the real behavior lives in the shim wrapper
# functions, tested here by sourcing the shims in throwaway shells with
# SPACE_TAG_AUTO=off (so the source-time autotag fire is a no-op) and
# SHELL=/usr/bin/true (so exec is observable without an interactive shell).
. "$(dirname "$0")/lib.sh"

t "binary source prints hook guidance and exits 1"
run source
assert_status 1; assert_out "exec \$SHELL"

if command -v zsh >/dev/null 2>&1; then
  t "zsh shim defines the space-tag wrapper function"
  OUT=$(SPACE_TAG_AUTO=off zsh -f -c ". '$ROOT/shell/space-tag.zsh'; whence -w space-tag" 2>&1); ST=$?
  assert_status 0; assert_out "space-tag: function"

  t "zsh wrapper forwards other subcommands to the binary"
  OUT=$(SPACE_TAG_AUTO=off zsh -f -c ". '$ROOT/shell/space-tag.zsh'; space-tag help" 2>&1); ST=$?
  assert_status 0; assert_out "usage:"

  t "zsh wrapper execs \$SHELL on source"
  OUT=$(SPACE_TAG_AUTO=off SHELL=/usr/bin/true zsh -f -c ". '$ROOT/shell/space-tag.zsh'; space-tag source; echo NOTREACHED" 2>&1); ST=$?
  assert_status 0; assert_no_out "NOTREACHED"
fi

if command -v bash >/dev/null 2>&1; then
  t "bash shim defines the space-tag wrapper function"
  OUT=$(SPACE_TAG_AUTO=off bash --noprofile --norc -c ". '$ROOT/shell/space-tag.bash'; type -t space-tag" 2>&1); ST=$?
  assert_status 0; assert_out "function"

  t "bash wrapper forwards other subcommands to the binary"
  OUT=$(SPACE_TAG_AUTO=off bash --noprofile --norc -c ". '$ROOT/shell/space-tag.bash'; space-tag help" 2>&1); ST=$?
  assert_status 0; assert_out "usage:"

  t "bash wrapper execs \$SHELL on source"
  OUT=$(SPACE_TAG_AUTO=off SHELL=/usr/bin/true bash --noprofile --norc -c ". '$ROOT/shell/space-tag.bash'; space-tag source; echo NOTREACHED" 2>&1); ST=$?
  assert_status 0; assert_no_out "NOTREACHED"
fi

finish
