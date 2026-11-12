#!/usr/bin/env bash
# What skip_count reads from a gate's output: pytest's and vitest's summary
# lines, and `unknown` when the output names no tests at all. Starts nothing,
# needs no network.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
fail=0

eval "$(sed -n '/^skip_count() {/,/^}/p' "$SELF/implement-loop.sh")"

case_() { # case_ <name> <expected> <gate output>
  local f got
  f=$(mktemp "${TMPDIR:-/tmp}/il-skip.XXXXXX")
  printf '%s\n' "$3" > "$f"
  got=$(skip_count "$f")
  rm -f "$f"
  if [ "$got" = "$2" ]; then
    echo "ok   $1: $got"
  else
    echo "FAIL $1: expected '$2', got '$got'"; fail=1
  fi
}

case_ "pytest, some skipped" "2 skipped, 0 deselected" \
  "==== 40 passed, 2 skipped in 1.2s ===="
case_ "pytest, some deselected" "0 skipped, 3 deselected" \
  "==== 40 passed, 3 deselected in 1.2s ===="
case_ "vitest, none skipped" "0 skipped, 0 deselected" \
  " Test Files  14 passed (14)
      Tests  260 passed (260)"
case_ "vitest, some skipped" "3 skipped, 0 deselected" \
  " Test Files  13 passed | 1 skipped (14)
      Tests  257 passed | 3 skipped (260)"
case_ "no test summary" "unknown" \
  "=== shellcheck ===
green"

exit $fail
