
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="${SPACE_TAG_BIN:-$ROOT/bin/space-tag}"
STUBS="$ROOT/tests/stubs"
GROUP=$(basename "$0" .sh)
GROUP=${GROUP#test-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

REAL_JQ=$(command -v jq) || { echo "jq is required to run the tests" >&2; exit 1; }


mkpathdir() {
  d="$WORK/$1"; mkdir -p "$d"; shift
  for tool in "$@"; do
    case "$tool" in
      jq) ln -s "$REAL_JQ" "$d/jq" ;;
      *)  ln -s "$STUBS/$tool" "$d/$tool" ;;
    esac
  done
}
SYS=/usr/bin:/bin
mkpathdir bin-all          yabai sketchybar git jq
mkpathdir bin-noyabai      sketchybar git jq
mkpathdir bin-nojq         yabai sketchybar git
mkpathdir bin-nosketchybar yabai git jq
PATH_ALL="$WORK/bin-all:$SYS"
PATH_NOYABAI="$WORK/bin-noyabai:$SYS"
PATH_NOJQ="$WORK/bin-nojq:$SYS"
PATH_NOSKETCHYBAR="$WORK/bin-nosketchybar:$SYS"


PASS=0; FAIL=0; N=0; CUR=""

t() {
  N=$((N+1)); CUR="$1"
  THOME="$WORK/h$N"; mkdir -p "$THOME"
  CFGDIR="$THOME/.config/sketchybar"
  LOG="$WORK/log$N"; : > "$LOG"
  EXTRA=""
  USE_PATH="$PATH_ALL"
}

cfg() { mkdir -p "$CFGDIR"; }

run() {
  # shellcheck disable=SC2086
  OUT=$(env -i HOME="$THOME" PATH="$USE_PATH" STUB_LOG="$LOG" $EXTRA "$BIN" "$@" 2>&1)
  ST=$?
}

ok()    { PASS=$((PASS+1)); }
nope()  { FAIL=$((FAIL+1)); printf 'FAIL %s — %s\n' "$CUR" "$1"; }

assert_status() { [ "$ST" -eq "$1" ] && ok || nope "exit $ST, expected $1 (out: $OUT)"; }
assert_out()    { case "$OUT" in *"$1"*) ok ;; *) nope "output missing '$1' (out: $OUT)" ;; esac; }
assert_no_out() { case "$OUT" in *"$1"*) nope "output unexpectedly contains '$1'" ;; *) ok ;; esac; }
assert_eq()     { [ "$OUT" = "$1" ] && ok || nope "output '$OUT', expected '$1'"; }
assert_file()   { v=$(cat "$CFGDIR/$1" 2>/dev/null); [ "$v" = "$2" ] && ok || nope "$1 contains '$v', expected '$2'"; }
assert_gone()   { [ ! -e "$CFGDIR/$1" ] && ok || nope "$1 still exists"; }

assert_log() {
  i=0
  while [ $i -lt 50 ]; do
    grep -qF -- "$1" "$LOG" 2>/dev/null && { ok; return; }
    sleep 0.02; i=$((i+1))
  done
  nope "stub log missing '$1' (log: $(tr '\n' '; ' < "$LOG"))"
}
assert_no_log() {
  sleep 0.05
  if grep -qF -- "$1" "$LOG" 2>/dev/null; then
    nope "stub log unexpectedly contains '$1'"
  else ok; fi
}

finish() {
  printf '%s: %d tests, %d assertions, %d failed\n' "$GROUP" "$N" "$((PASS + FAIL))" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
