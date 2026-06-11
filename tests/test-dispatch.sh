#!/bin/sh
# Dispatch: help variants, no-args, unknown options, bare --.
. "$(dirname "$0")/lib.sh"

t "no args prints usage and exits 1"
run; assert_status 1; assert_out "usage:"

t "help exits 0 with usage"
run help; assert_status 0; assert_out "position modes:"

t "-h exits 0"
run -h; assert_status 0; assert_out "usage:"

t "--help exits 0"
run --help; assert_status 0; assert_out "usage:"

t "unknown option is rejected with hint"
run -x; assert_status 1; assert_out "unknown option: -x"; assert_out "space-tag -- -x"

t "bare -- without a name is rejected"
run --; assert_status 1; assert_out "usage: space-tag -- <name>"

finish
