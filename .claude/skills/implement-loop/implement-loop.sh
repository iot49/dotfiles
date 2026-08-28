#!/usr/bin/env bash
#
# implement-loop — batch-implement, Ralph-style.
#
# The host (this script) does every side effect: git resets, pushes, gh
# comments, labels, the summary issue. Every LLM step runs COLD inside a
# Docker sandbox (`docker sandbox run claude -p`), which mounts only the
# working directory and holds no credentials. Issue bodies are pre-fetched
# to files so the container never needs `gh` auth.
#
# Usage:
#   implement-loop.sh [issue numbers...]
#   No arguments: every open issue labelled ready-for-agent.
#
# Host requirements: git, gh (authenticated), python3, Docker Desktop with
# sandboxes, and ONE prior interactive `docker sandbox run claude` in this
# workspace so the sandbox is authenticated.
#
# Per-issue flow:
#   dispatch cold agent -> gate (host) -> verify diff vs issue body (cold
#   agent) -> one repair round via --resume -> land, or reset to $pre.
# After the batch:
#   one review over the whole range -> push -> close what landed -> file a
#   summary issue labelled needs-triage, action items first.
#
# Spec rule: a Spec finding on #NN does not hold the push; it holds the
# CLAIM. The commits land, #NN stays open and goes back to ready-for-human.
#
# Config (env):
#   IL_EXTRA_ARGS   extra args for every claude call (e.g. "--model opus")
#   IL_GATE         override gate resolution with an explicit command

set -u  # not -e: one failing issue must not kill the batch; errors are handled

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------
WORKDIR=".implement-loop"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$WORKDIR/run-$TS.log"
RULINGS="$WORKDIR/rulings.md"
FAILED="$WORKDIR/failed-$TS.txt"     # issues that did not land (failed or skipped)

mkdir -p "$WORKDIR"
touch "$FAILED"
# keep the workdir out of git without touching .gitignore; also makes
# `git clean -fd` (no -x) leave it alone
if [ -d .git ]; then
  grep -qxF "$WORKDIR/" .git/info/exclude 2>/dev/null || echo "$WORKDIR/" >> .git/info/exclude
fi
exec > >(tee -a "$LOG") 2>&1

die() { echo "ABORT: $*" >&2; exit 1; }
say() { echo; echo "== $*"; }

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# Run a cold claude in the sandbox. Prints the raw stdout (JSON expected).
sb() { # sb <promptfile>
  docker sandbox run claude --dangerously-skip-permissions \
    ${IL_EXTRA_ARGS:-} -p "$(cat "$1")" --output-format json
}

# Resume a session in the sandbox (the repair round).
sb_resume() { # sb_resume <session_id> <promptfile>
  docker sandbox run claude --dangerously-skip-permissions \
    ${IL_EXTRA_ARGS:-} -p --resume "$1" "$(cat "$2")" --output-format json
}

# Pull one field out of the (possibly noise-prefixed) JSON on stdin.
jget() { # jget <field>
  python3 -c '
import json, sys
field = sys.argv[1]
raw = sys.stdin.read()
# docker may prepend setup noise; parse from the first "{" that yields JSON
for i, ch in enumerate(raw):
    if ch == "{":
        try:
            print(json.loads(raw[i:]).get(field, ""))
            sys.exit(0)
        except Exception:
            continue
print("")
' "$1"
}

# Extract a <tag>...</tag> block from text on stdin.
extract_tag() { # extract_tag <tagname>
  python3 -c '
import re, sys
tag = sys.argv[1]
m = re.search(r"<%s>(.*?)</%s>" % (tag, tag), sys.stdin.read(), re.S)
print(m.group(1).strip() if m else "")
' "$1"
}

resolve_gate() {
  if [ -n "${IL_GATE:-}" ]; then echo "$IL_GATE"; return 0; fi
  if [ -f CLAUDE.md ]; then
    local g
    g=$(sed -n 's/^[Gg]ate:[[:space:]]*//p' CLAUDE.md | head -1)
    if [ -n "$g" ]; then echo "$g"; return 0; fi
  fi
  if [ -x scripts/check.sh ]; then echo "./scripts/check.sh"; return 0; fi
  if [ -f Makefile ] && grep -qE '^check:' Makefile; then echo "make check"; return 0; fi
  if [ -f package.json ] && python3 -c '
import json, sys
sys.exit(0 if "check" in json.load(open("package.json")).get("scripts", {}) else 1)
' 2>/dev/null; then echo "npm run check"; return 0; fi
  return 1
}

run_gate() { # -> exit code is the verdict; output captured to $1
  bash -c "$GATE" > "$1" 2>&1
}

# ---------------------------------------------------------------------------
# pre-flight — each is a way the run could destroy work that is not its own
# ---------------------------------------------------------------------------
say "pre-flight"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo"
gh repo view --json nameWithOwner --jq .nameWithOwner >/dev/null 2>&1 \
  || die "gh cannot resolve this repo (auth? remote?)"

[ -z "$(git status --porcelain)" ] || die "working tree not clean — the failure path resets hard"

git pull --rebase || die "pull --rebase failed"

GATE=$(resolve_gate) || die "no gate resolved (IL_GATE, CLAUDE.md 'gate:', scripts/check.sh, make check, npm run check). A batch with no gate has nobody but the author deciding it passed."
say "gate: $GATE"

run_gate "$WORKDIR/gate-preflight.txt" \
  || { tail -20 "$WORKDIR/gate-preflight.txt"; die "gate red on the starting commit"; }

# sandbox smoke test (also verifies auth); needs `timeout` or `gtimeout` if present
TO=""
command -v timeout  >/dev/null && TO="timeout 180"
command -v gtimeout >/dev/null && TO="gtimeout 180"
echo "Reply with exactly: OK" > "$WORKDIR/smoke.md"
SMOKE=$($TO docker sandbox run claude --dangerously-skip-permissions -p "$(cat "$WORKDIR/smoke.md")" --output-format json 2>&1)
echo "$SMOKE" | jget result | grep -q "OK" \
  || die "sandbox smoke test failed — run 'docker sandbox run claude' once interactively to authenticate. Output: $SMOKE"

START_SHA=$(git rev-parse HEAD)
say "starting at $START_SHA"

# ---------------------------------------------------------------------------
# choose the batch and order it by GitHub's native dependencies
# ---------------------------------------------------------------------------
say "batch"

if [ $# -gt 0 ]; then
  ISSUES="$*"
else
  ISSUES=$(gh issue list --label ready-for-agent --state open --json number --jq '.[].number' | tr '\n' ' ')
fi
[ -n "${ISSUES// /}" ] || die "no issues in batch"

# python does the gh dependency calls and the topological sort; emits:
#   line 1: ordered issue numbers (space separated)
#   line 2: pre-skipped numbers (blocker open outside the batch)
#   rest:   "N: b1 b2" in-batch blocker edges, one line per issue
python3 - $ISSUES > "$WORKDIR/deps.txt" <<'PY'
import json, subprocess, sys
batch = [int(x) for x in sys.argv[1:]]
def blocked_by(n):
    try:
        out = subprocess.run(
            ["gh", "api", "repos/{owner}/{repo}/issues/%d/dependencies/blocked_by" % n],
            capture_output=True, text=True, check=True).stdout
        return [(d["number"], d.get("state", "open")) for d in (json.loads(out) or [])]
    except Exception:
        return []
blk = {n: blocked_by(n) for n in batch}
# pre-skip: blocker open and not in the batch, cascading
skipped = set()
changed = True
while changed:
    changed = False
    for n in batch:
        if n in skipped: continue
        for b, st in blk[n]:
            if (st == "open" and b not in batch) or (b in skipped):
                skipped.add(n); changed = True
live = [n for n in batch if n not in skipped]
edges = {n: [b for b, _ in blk[n] if b in live] for n in live}
order, pend = [], dict(edges)
while pend:
    ready = sorted(n for n, bs in pend.items() if all(b in order for b in bs))
    if not ready:  # cycle: fall back to number order
        ready = sorted(pend)
    for n in ready:
        order.append(n); pend.pop(n)
print(" ".join(str(n) for n in order))
print(" ".join(str(n) for n in sorted(skipped)))
for n in live:
    print("%d: %s" % (n, " ".join(str(b) for b in edges[n])))
PY

ORDER=$(sed -n 1p "$WORKDIR/deps.txt")
PRESKIP=$(sed -n 2p "$WORKDIR/deps.txt")

for n in $PRESKIP; do
  echo "$n" >> "$FAILED"
  gh issue comment "$n" --body "implement-loop: skipped — blocked by an open issue outside this batch." || true
done

say "plan: $ORDER"
[ -n "$PRESKIP" ] && say "pre-skipped (open blocker outside batch): $PRESKIP"
[ -n "${ORDER// /}" ] || die "nothing runnable after dependency resolution"

touch "$RULINGS"
LANDED=""          # "NN:presha:postsha ..."

# ---------------------------------------------------------------------------
# per issue
# ---------------------------------------------------------------------------
for NN in $ORDER; do
  say "issue #$NN"

  # skip if an in-batch blocker did not land — its premise never landed
  BLK=$(grep "^$NN:" "$WORKDIR/deps.txt" | cut -d: -f2)
  SKIP_REASON=""
  for b in $BLK; do
    grep -qx "$b" "$FAILED" && SKIP_REASON="blocker #$b did not land"
  done
  if [ -n "$SKIP_REASON" ]; then
    echo "skip #$NN: $SKIP_REASON"
    echo "$NN" >> "$FAILED"
    gh issue comment "$NN" --body "implement-loop: skipped — $SKIP_REASON." || true
    continue
  fi

  PRE=$(git rev-parse HEAD)
  gh issue view "$NN" --comments > "$WORKDIR/issue-$NN.md" \
    || { echo "$NN" >> "$FAILED"; echo "could not fetch #$NN, skipping"; continue; }

  # ---- build the prompt ---------------------------------------------------
  P="$WORKDIR/prompt-$NN.md"
  {
    echo "Implement issue #$NN in this repo."
    echo
    echo "The issue body and comments are at $WORKDIR/issue-$NN.md — read that"
    echo "first. \`gh\` and the network are NOT available here; everything you"
    echo "need is in the working directory."
    echo
    echo "Then, if this repo has them, read CONTEXT.md for the vocabulary and"
    echo "any ADR under docs/adr/ touching the area — use the glossary's terms,"
    echo "not its listed synonyms."
    echo
    echo "Use /tdd where the seams are already agreed, if that skill is"
    echo "available in this repo. Typecheck and run the individual test files"
    echo "you touch as you go."
    echo
    echo "When you believe you are done, run \`$GATE\` and get it green — the"
    echo "same gate runs against your work afterwards, outside this session."
    echo
    echo "Commit to the current branch as CLAUDE.md requires: linear, each"
    echo "commit a reviewable step referencing #$NN, any mechanical move in its"
    echo "own commit so the rename stays legible."
    echo
    echo "Do not push. Do not close the issue. If the repo has a scratch/, do"
    echo "not write into it. Do not modify $WORKDIR/ yourself."

    # handoff: the blocker that landed (only edges inside this batch)
    for b in $BLK; do
      for entry in $LANDED; do
        case "$entry" in
          "$b":*)
            bsha=${entry##*:}
            echo
            echo "Issue #$b in this same batch blocked this one and has already"
            echo "landed as $bsha. Its author summarised it as:"
            sed 's/^/> /' "$WORKDIR/handoff-$b.txt" 2>/dev/null
            echo "Read that commit before starting; it is the only prior work"
            echo "in this run that bears on yours."
            ;;
        esac
      done
    done

    # handoff: the rulings the batch has made
    if [ -s "$RULINGS" ]; then
      echo
      echo "The batch has already ruled on these, and your issue body was"
      echo "written before they landed:"
      echo
      sed 's/^/- /' "$RULINGS"
      echo
      echo "Where your issue body and one of these disagree about a word, a"
      echo "contract, or what a criterion asks for, the ruling wins. Implement"
      echo "the ruling, and say so in the commit message."
    fi

    echo
    echo "End your reply with exactly these two blocks (empty is fine):"
    echo
    echo "<handoff>"
    echo "Two sentences on what this change did and where, for an agent"
    echo "implementing a dependent issue."
    echo "</handoff>"
    echo "<rulings>"
    echo "One line each: a word retired or introduced, a payload or command"
    echo "shape changed, an acceptance criterion you could not meet as written"
    echo "and what you did instead. Leave empty if none."
    echo "</rulings>"
  } > "$P"

  # ---- dispatch -----------------------------------------------------------
  RES=$(sb "$P")
  SID=$(echo "$RES" | jget session_id)
  TXT=$(echo "$RES" | jget result)
  echo "$TXT" > "$WORKDIR/result-$NN.txt"

  # ---- gate, then verify --------------------------------------------------
  check_issue() { # -> 0 ok; 1 fail; failure text in $WORKDIR/failure-$NN.txt
    if ! run_gate "$WORKDIR/gate-$NN.txt"; then
      { echo "The gate (\`$GATE\`) failed on your work:"; echo; tail -60 "$WORKDIR/gate-$NN.txt"; } \
        > "$WORKDIR/failure-$NN.txt"
      return 1
    fi
    git diff "$PRE"..HEAD > "$WORKDIR/diff-$NN.patch"
    if [ ! -s "$WORKDIR/diff-$NN.patch" ]; then
      echo "No commits landed for #$NN." > "$WORKDIR/failure-$NN.txt"
      return 1
    fi
    V="$WORKDIR/verify-prompt-$NN.md"
    {
      echo "You are the gatekeeper, not the author. Judge the work for issue #$NN."
      echo
      echo "Read $WORKDIR/issue-$NN.md (what was asked) and"
      echo "$WORKDIR/diff-$NN.patch (what was done). Also run:"
      echo "  git log --oneline $PRE..HEAD"
      echo
      echo "The test gate is already green; that says nothing broke. Judge only:"
      echo "1. Is each thing the issue actually asks for addressed in the diff?"
      echo "2. Does every commit message reference #$NN? (The final review"
      echo "   resolves its spec sources from those references.)"
      echo
      echo "First line of your reply must be exactly 'VERDICT: PASS' or"
      echo "'VERDICT: FAIL', then your reasons."
    } > "$V"
    VOUT=$(sb "$V" | jget result)
    echo "$VOUT" > "$WORKDIR/verify-$NN.txt"
    if ! echo "$VOUT" | head -3 | grep -q "VERDICT: PASS"; then
      { echo "An independent check read your diff against the issue body and failed it:"; echo; echo "$VOUT"; } \
        > "$WORKDIR/failure-$NN.txt"
      return 1
    fi
    return 0
  }

  OK=0
  if check_issue; then OK=1; else
    # ---- repair, once: same session still holds the context of what it tried
    say "issue #$NN: repair round"
    R="$WORKDIR/repair-prompt-$NN.md"
    { cat "$WORKDIR/failure-$NN.txt"; echo; echo "Fix this, re-run \`$GATE\` until green, and commit. Then update your <handoff> and <rulings> blocks."; } > "$R"
    RRES=$(sb_resume "$SID" "$R")
    RTXT=$(echo "$RRES" | jget result)
    echo "$RTXT" >> "$WORKDIR/result-$NN.txt"
    check_issue && OK=1
  fi

  if [ "$OK" = 1 ]; then
    POST=$(git rev-parse HEAD)
    LANDED="$LANDED $NN:$PRE:$POST"
    cat "$WORKDIR/result-$NN.txt" | extract_tag handoff > "$WORKDIR/handoff-$NN.txt"
    RUL=$(cat "$WORKDIR/result-$NN.txt" | extract_tag rulings)
    [ -n "$RUL" ] && echo "$RUL" >> "$RULINGS"
    say "issue #$NN landed ($PRE..$POST)"
  else
    # ---- give up: leave the morning's triage already done -------------------
    say "issue #$NN: giving up, resetting to $PRE"
    git reset --hard "$PRE"
    git clean -fd     # untracked only; $WORKDIR is ignored and survives
    echo "$NN" >> "$FAILED"
    gh issue comment "$NN" --body "$(printf 'implement-loop: failed after one repair round. Work was reset; nothing landed.\n\n```\n%s\n```' "$(tail -40 "$WORKDIR/failure-$NN.txt")")" || true
    gh issue edit "$NN" --remove-label ready-for-agent --add-label ready-for-human 2>/dev/null || true
  fi
done

# ---------------------------------------------------------------------------
# after the last issue: review the whole range
# ---------------------------------------------------------------------------
SPEC_FAILS=""
if [ -n "${LANDED// /}" ]; then
  say "final review over $START_SHA..HEAD"
  RV="$WORKDIR/review-prompt.md"
  {
    echo "Review the range $START_SHA...HEAD — the union of a batch. Each"
    echo "change was reviewed alone; this is the first look at the whole,"
    echo "and issues in one batch touch overlapping code."
    echo
    echo "If the /code-review skill is available in this repo, use it over"
    echo "that range. Otherwise run the same two-axis review yourself:"
    echo "- Standards: does the code follow this repo's documented standards"
    echo "  (CLAUDE.md, docs/)?"
    echo "- Spec: does it faithfully implement the originating issues?"
    echo "  Resolve issue numbers from the #NN references in"
    echo "  \`git log $START_SHA..HEAD\`; the issue bodies are pre-fetched at"
    echo "  $WORKDIR/issue-<n>.md. \`gh\` and the network are NOT available."
    echo
    echo "Write the full report to $WORKDIR/review.md."
    echo
    echo "End your reply with exactly this block: the numbers of issues with a"
    echo "requirement that was NOT met, space separated, or empty:"
    echo "<spec-failures></spec-failures>"
  } > "$RV"
  RVOUT=$(sb "$RV" | jget result)
  SPEC_FAILS=$(echo "$RVOUT" | extract_tag spec-failures)
  [ -f "$WORKDIR/review.md" ] || echo "$RVOUT" > "$WORKDIR/review.md"
  say "spec failures: '${SPEC_FAILS:-none}'"
fi

# ---------------------------------------------------------------------------
# push — a Spec finding holds the claim, not the push
# ---------------------------------------------------------------------------
PUSHED=no
if [ -n "${LANDED// /}" ]; then
  say "push"
  if git push; then PUSHED=yes
  else
    if git pull --rebase && run_gate "$WORKDIR/gate-postrebase.txt" && git push; then
      PUSHED=yes
    else
      git rebase --abort 2>/dev/null || true
      say "push failed (remote moved, rebase not clean) — commits stay local; resolving a conflict is not an unattended act"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# close what landed; hold the claim where the review said the spec was missed
# ---------------------------------------------------------------------------
if [ "$PUSHED" = yes ]; then
  for entry in $LANDED; do
    NN=${entry%%:*}; rest=${entry#*:}; PRE=${rest%%:*}; POST=${rest##*:}
    if echo " $SPEC_FAILS " | grep -q " $NN "; then
      gh issue comment "$NN" --body "$(printf 'implement-loop: commits %s..%s landed and were pushed, but the final review found a requirement not met — see the summary issue. Leaving this open.' "$PRE" "$POST")" || true
      gh issue edit "$NN" --remove-label ready-for-agent --add-label ready-for-human 2>/dev/null || true
    else
      gh issue close "$NN" --comment "implement-loop: landed as $PRE..$POST." || true
    fi
  done
fi

# ---------------------------------------------------------------------------
# summary issue — action items first, so the morning starts at the top
# ---------------------------------------------------------------------------
say "summary issue"
gh label create needs-triage --description "Maintainer needs to evaluate this issue" --color FBCA04 2>/dev/null || true

BODY="$WORKDIR/summary-$TS.md"
{
  echo "## Do this first"
  [ "$PUSHED" = no ] && [ -n "${LANDED// /}" ] \
    && echo "- **Nothing was pushed** (remote moved and the rebase was not clean). Commits are local on this branch — rebase and push by hand."
  for n in $SPEC_FAILS; do
    echo "- #$n landed but a requirement was **not met** — it is back on \`ready-for-human\`. See the review below."
  done
  while read -r n; do
    [ -n "$n" ] && echo "- #$n did not land — see its issue comment for the failing output (\`ready-for-human\`)."
  done < <(sort -un "$FAILED")
  [ -z "${SPEC_FAILS// /}" ] && [ ! -s "$FAILED" ] && [ "$PUSHED" = yes ] \
    && echo "- Nothing. Everything landed, was pushed, and is closed."
  echo
  echo "## What landed"
  if [ -n "${LANDED// /}" ]; then
    for entry in $LANDED; do
      NN=${entry%%:*}; rest=${entry#*:}; PRE=${rest%%:*}; POST=${rest##*:}
      echo "- #$NN: \`$PRE..$POST\`"
    done
    echo "- pushed: $PUSHED"
  else
    echo "- nothing"
  fi
  if [ -s "$RULINGS" ]; then
    echo
    echo "## Rulings this batch made"
    sed 's/^/- /' "$RULINGS"
  fi
  if [ -f "$WORKDIR/review.md" ]; then
    echo
    echo "## Final review ($START_SHA...HEAD)"
    cat "$WORKDIR/review.md"
  fi
  echo
  echo "_Log: \`$LOG\` (local, not committed)._"
} > "$BODY"

SUMMARY_URL=$(gh issue create --label needs-triage \
  --title "implement-loop $TS: $(echo $ORDER | wc -w | tr -d ' ') issues attempted" \
  --body-file "$BODY") || SUMMARY_URL="(issue creation failed — summary at $BODY)"

say "done. summary: $SUMMARY_URL"
