# implement-loop: four changes

Written 2026-09-06 after five batches in `rails49/control` landed 17 issues in
one morning. Each section states what goes wrong today, with the evidence, then
the change and how to tell it works. Line numbers are against
`implement-loop.sh` as of that date.

`README.md` holds the design and its known holes. None of these four are in
that list: they are drift found by running it, not risks the design accepted.

## 1. A run that aborts can be resumed

### What goes wrong

There is no trap, so `die()` leaves the worktree and the branch in place. The
*next* run then force-removes that worktree and cuts a fresh branch from the
default branch:

```
466  git worktree remove --force "$WT" 2>/dev/null
468  git worktree add -q "$WT" -b "$BRANCH" "$START_SHA" || die ...
```

Commits are not lost — `mirror_branch()` (154) pushes after every landed issue,
and the draft PR opened after the first one holds them. But the issues are
still open and still `ready-for-agent`, because they are closed only in the
landing path. So the next run re-plans the same issues and implements them a
second time, against a different starting commit.

The cost is real and has been paid twice. `rails49/control#458` records a run
stopped mid-batch: *"the batch was rebuilt by hand, all five cherry-picks
clean."* And PR #467 in that repo has been sitting open in draft since
2026-09-05, the residue of a run killed at issue #445 — nothing points at it,
and nothing will clean it up.

Unit exhaustion is the expected trigger. The script already sleeps and retries
up to `LIMIT_WAITS` (254-276) and then lets the run stop, which is right; what
is missing is picking the run back up afterwards.

### The change

Write `.implement-loop/state.json` after each issue lands and after each phase
boundary, holding: `ts`, `branch`, `start_sha`, `order`, `landed`
(the `NN:pre:post` list), `failed`, `preskip`, `pr_url`, and `phase` — one of
`issues`, `review`, `hold`, `land`.

`implement-loop.sh --resume` reads it and continues instead of starting over:

- reuse `branch` and re-create the worktree **at the branch tip**, not at
  `start_sha`;
- drop from `order` every issue already in `landed` or `failed`;
- reuse `pr_url` rather than opening a second draft PR;
- if `phase` is past `issues`, skip straight to that phase — a run that died
  in the hold check has no issues left to implement.

A fresh run with no `--resume` must **refuse to start** when `state.json`
describes an unfinished run, naming the branch, the PR and the resume command.
Today it silently destroys that worktree, which is how #467 was orphaned.
`--force-new` overrides, and says what it is discarding.

`state.json` is exempt from the `IL_KEEP_DAYS` prune, like `rulings.md`.

### Acceptance

1. Kill a run between two issues. `--resume` continues from the next issue,
   the branch keeps its earlier commits, and no issue is implemented twice.
2. The same kill, then a plain run: it refuses, and names the branch, the PR
   and `--resume`.
3. A run that completes and merges removes `state.json`, so the next plain run
   starts normally.
4. Killing during the range review resumes into the review, not into the
   issues.

## 2. The backlog re-query does not trust GitHub's index

### What goes wrong

After a merged batch the script re-queries the label and restarts itself:

```
1086  NEXT=$(gh issue list --label ready-for-agent --state open ...)
1090  say "backlog still has $NEXT — going again"
1091  exec "$0"
```

The query runs within a second of closing the batch's issues, and GitHub's
issue index lags the close. Both runs on 2026-09-06 hit it: one reported
`backlog still has 472`, the other `backlog still has 456 454`, in each case
naming an issue closed seconds earlier. Neither did damage, because the
restarted run re-queries from scratch, but each burned a full pre-flight gate
run — several minutes — deciding to do nothing.

This is what is left of "parallel work without interference". The file-level
half is already fixed: batches run in a `git worktree` under
`.implement-loop/tree`, so the checkout the run was started from stays on the
default branch and is usable while a batch runs (`58c778d`, recorded in
`rails49/control#458`).

### The change

Subtract the issues this run just closed from `NEXT`, the same way `PRESKIP`
is already subtracted. The run knows their numbers: they are in `landed`.

### Acceptance

1. A batch that closes every open `ready-for-agent` issue ends without
   restarting, and says the backlog is empty.
2. A batch that leaves one unblocked issue restarts with exactly that issue.
3. No run reports "backlog still has N" for an `N` it closed itself.

## 3. The gate reports what it skipped

### What goes wrong

Nothing here is broken; what is missing is visibility. `scripts/check.sh` runs
three times over a batch — per issue, again on the union of the whole range at
the final review, and again in CI — and benchmarks are ordinary parametrized
tests, so they are in all three. That is already the comprehensive run.

What no one sees is what did not run. The Python suite skips ~68 tests locally
(broker, hardware). CI sets `CI=true`, under which the broker fixture fails
rather than skips, so CI is stricter than the sandbox — and the difference is
invisible in the log. A test that starts skipping because a fixture broke looks
exactly like a test that always skipped.

### The change

Parse the skip count out of the gate output at two points that already exist —
the pre-flight run and the range-review run — and record both. When they
differ, say so in the log and in the summary issue: a batch that turned tests
off is the case worth catching.

Naming the individual tests needs `pytest -rs`, which is the repo's gate
command and not this script's to change. Count first; a repo that wants names
can add `-rs` to its own gate and the report carries them.

### Acceptance

1. The summary issue carries the skip count from pre-flight and from the range
   review.
2. A batch where the two differ says so in the log, at the range review.
3. A gate whose output has no recognisable skip line degrades to "unknown"
   rather than failing the run.

## 4. Range-review findings become issues

### What goes wrong

The loop files exactly one issue per batch — the summary, labelled
`needs-triage` (1075) — and relabels failures `ready-for-human` via
`hand_back()` (137). Findings from the range review are prose inside that
summary.

`rails49/control#476` is the worked example: its action list was eleven
bullets, each pointing at a `scope-NNN.txt` file on the operator's local disk.
Nothing was filed, so nothing was tracked, and the paths are meaningless to
anyone reading the issue on GitHub. The findings that *did* become issues that
week — #454 through #457 — were filed by hand afterwards.

### The change

Ask the range review to emit findings in a tagged block, using the
`extract_tag()` machinery that already exists (310). File one issue per
finding, and link each from the summary.

**Every filed issue gets `needs-triage` and nothing else.** Not
`ready-for-agent`: that label asserts every decision is made, and the thing
asserting it would be the same judge that returned "work beyond the issue" on
eleven of the twelve issues in that batch — a verdict that fired on nearly
everything and so separated nothing. A follow-up promoted by the loop would
run unattended in the next batch on the strength of that. The review may
*suggest* a state in the issue body — including that it needs grilling — and a
human or a triage pass promotes it.

Findings must carry file, change and why. A finding that cannot name a file is
a note for the summary, not an issue.

### Acceptance

1. A range review that reports three findings files three issues, each
   `needs-triage`, each naming a file.
2. The summary links them instead of pointing at local paths.
3. No issue the loop files carries `ready-for-agent`.
4. A review with no findings files nothing.

## Not in scope

- **One PR per issue instead of one per batch.** It would make an abort cost at
  most one issue, but costs the two properties the design rests on: one CI run
  per batch, and a range review over the batch as a unit.
- **Letting the loop promote its own follow-ups.** See section 4.
- **A scenario replay or a benchmark comparison against `benchmarks/expected/`
  as a separate stage.** Those are already tests in the gate.
