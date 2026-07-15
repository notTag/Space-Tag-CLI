#!/bin/sh

set -u

DIR=$(cd "$(dirname "$0")" && pwd)

TESTS=0; ASSERTS=0; FAILED=0; NGROUPS=0; BAD_GROUPS=0

for group in "$DIR"/test-*.sh; do
  NGROUPS=$((NGROUPS + 1))
  out=$("$group") || BAD_GROUPS=$((BAD_GROUPS + 1))
  echo "$out"
  summary=$(echo "$out" | tail -1)
  TESTS=$((TESTS + $(echo "$summary" | awk '{print $2}')))
  ASSERTS=$((ASSERTS + $(echo "$summary" | awk '{print $4}')))
  FAILED=$((FAILED + $(echo "$summary" | awk '{print $6}')))
done

echo "─────"
echo "total: $NGROUPS groups, $TESTS tests, $ASSERTS assertions, $FAILED failed"
[ "$BAD_GROUPS" -eq 0 ]
