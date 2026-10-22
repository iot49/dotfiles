#!/usr/bin/env bash
# The loop's gate and the gate step of the CI workflow that setup writes must
# pick the same command, or a repo passes the loop and fails every PR. Runs
# both resolutions over one repo per case; starts nothing, needs no network.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
fail=0

eval "$(sed -n '/^resolve_gate() {/,/^}/p' "$SELF/implement-loop.sh")"
# the workflow's gate step, unescaped from its heredoc, without the final run
CI_GATE=$(sed -n '/- name: gate/,/^YAML$/p' "$SELF/implement-loop-setup.sh" \
  | sed '1,2d;$d' | sed 's/^          //; s/\\\$/$/g' | grep -v '^bash -c')

case_() { # case_ <name> <setup command> — run in a fresh dir
  local name=$1 d loop ci
  d=$(mktemp -d "${TMPDIR:-/tmp}/il-gate.XXXXXX"); cd "$d" || exit 1
  eval "$2"
  loop=$(resolve_gate)
  ci=$(bash -c "$CI_GATE" | sed -n 's/^+ //p')
  if [ -n "$loop" ] && [ "$loop" = "$ci" ]; then
    echo "ok   $name: $loop"
  else
    echo "FAIL $name: loop '${loop}', ci '${ci}'"; fail=1
  fi
}

case_ "gate: line" 'echo "gate: echo g" > CLAUDE.md'
case_ "scripts/check.sh" 'mkdir scripts; printf "#!/bin/sh\n" > scripts/check.sh; chmod +x scripts/check.sh'
case_ "make check" 'printf "check:\n\ttrue\n" > Makefile'
case_ "npm check script" 'echo "{\"scripts\": {\"check\": \"true\"}}" > package.json'

exit $fail
