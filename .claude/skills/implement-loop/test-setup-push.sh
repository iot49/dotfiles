#!/usr/bin/env bash
# What implement-loop-setup.sh pushes, and what it leaves when it stops. Runs
# against a local bare repo as origin and a stub gh on PATH; needs no network.
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }

# a stub gh: answers the repo lookups, logs every call, accepts the rest
STUB=$(mktemp -d "${TMPDIR:-/tmp}/il-gh.XXXXXX"); cd "$STUB" || exit 1
cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$*" in
  *nameWithOwner*)    echo o/r ;;
  *defaultBranchRef*) echo main ;;
esac
case "$*" in *--input*) cat > /dev/null ;; esac
exit 0
SH
chmod +x "$STUB/gh"

fresh() { # fresh — origin with one commit, a clone of it as the cwd
  local d; d=$(mktemp -d "${TMPDIR:-/tmp}/il-setup.XXXXXX")
  git init -q --bare -b main "$d/origin.git"
  git clone -q "$d/origin.git" "$d/work" 2>/dev/null; cd "$d/work" || exit 1
  git commit -q --allow-empty -m init && git push -q origin main
  ORIGIN="$d/origin.git"; OUT="$d/out.txt"; export GH_LOG="$d/gh.log"; : > "$GH_LOG"
}
setup() { PATH="$STUB:$PATH" bash "$SELF/implement-loop-setup.sh" > "$OUT" 2>&1; }

fresh
printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
setup && no "refused push: script succeeded"
if [ ! -e .github/workflows/ci.yml ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
   && git cat-file -e implement-loop-ci:.github/workflows/ci.yml 2>/dev/null; then
  ok "refused push: main back at origin, workflow on implement-loop-ci"
else
  no "refused push: main or the branch is not as expected"
fi

fresh
git commit -q --allow-empty -m local
before=$(git -C "$ORIGIN" rev-parse main)
setup && no "unpushed commit: script succeeded"
[ "$(git -C "$ORIGIN" rev-parse main)" = "$before" ] \
  && ok "unpushed commit: nothing pushed" || no "unpushed commit: origin moved"

fresh
mkdir -p .github/workflows
printf 'name: ci\non: push\njobs:\n  test:\n    runs-on: ubuntu-latest\n' > .github/workflows/ci.yml
git add . && git commit -q -m wf && git push -q origin main
setup && no "no ci job: script succeeded"
grep -q 'POST.*rulesets' "$GH_LOG" && no "no ci job: ruleset created" || ok "no ci job: stopped before the ruleset"

fresh
if setup && git -C "$ORIGIN" cat-file -e main:.github/workflows/ci.yml 2>/dev/null \
   && grep -q 'POST.*rulesets' "$GH_LOG"; then
  ok "clean repo: workflow pushed, ruleset created"
else
  no "clean repo: $(tail -3 "$OUT")"
fi

exit $fail
