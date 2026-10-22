#!/usr/bin/env bash
# The aborts before the run has a log of its own must still leave one, with
# the ABORT line, because the launcher sends stdout to /dev/null and reads
# only the log. Needs nothing but bash and python3; starts no run.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
fail=0

check() { # check <name> — expect a logged ABORT in the current dir
  local name=$1
  if grep -qs '^ABORT' "$PWD"/.implement-loop/run-*.log; then
    echo "ok   $name"
  else
    echo "FAIL $name: no run-*.log with an ABORT line"; fail=1
  fi
}

d=$(mktemp -d "${TMPDIR:-/tmp}/il-test.XXXXXX"); cd "$d" || exit 1
mkdir .implement-loop
python3 "$SELF/il-state.py" write .implement-loop/state.json \
  20260101-000000 implement-loop/20260101-000000 abc123 "1 2" "1:a:b" "" "" issues
bash "$SELF/implement-loop.sh" > /dev/null 2>&1
check "plain run over an unfinished one"

d=$(mktemp -d "${TMPDIR:-/tmp}/il-test.XXXXXX"); cd "$d" || exit 1
bash "$SELF/implement-loop.sh" --resume > /dev/null 2>&1
check "--resume with nothing to resume"

exit $fail
