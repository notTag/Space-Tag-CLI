#!/bin/sh
# tests/run.sh — runs every test group (tests/test-*.sh) and aggregates the
# results. Each group is independently runnable too (e.g. tests/test-tag.sh
# to iterate on one command); the shared harness lives in tests/lib.sh.
#
# Pass SPACE_TAG_BIN=<path> to test a different binary (used for coverage
# instrumentation).

set -u

DIR=$(cd "$(dirname "$0")" && pwd)

# NGROUPS, not GROUPS: GROUPS is readonly in bash, and macOS /bin/sh (bash in
# POSIX mode) treats assigning to it as a fatal — and silent — error.
TESTS=0; ASSERTS=0; FAILED=0; NGROUPS=0; BAD_GROUPS=0

for group in "$DIR"/test-*.sh; do
  NGROUPS=$((NGROUPS + 1))
  out=$("$group") || BAD_GROUPS=$((BAD_GROUPS + 1))
  echo "$out"
  # Last line is the group summary: "<name>: N tests, A assertions, F failed"
  summary=$(echo "$out" | tail -1)
  TESTS=$((TESTS + $(echo "$summary" | awk '{print $2}')))
  ASSERTS=$((ASSERTS + $(echo "$summary" | awk '{print $4}')))
  FAILED=$((FAILED + $(echo "$summary" | awk '{print $6}')))
done

echo "─────"
echo "total: $NGROUPS groups, $TESTS tests, $ASSERTS assertions, $FAILED failed"
[ "$BAD_GROUPS" -eq 0 ]
