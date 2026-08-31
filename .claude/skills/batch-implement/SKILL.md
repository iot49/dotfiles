---
name: batch-implement
description: Implement a batch of ready-for-agent issues unattended — one cold subagent per issue, a gate between each, and one review over the whole range at the end. Superseded by /implement-loop; use this only where the current branch takes direct pushes.
disable-model-invocation: true
---

Lands several issues while nobody is watching. Each issue gets its own cold
subagent, the parent gates the result before moving on, commits stay local
until the end, and a single review covers the whole range rather than each
step.

The shape earns its cost twice. A cold subagent per issue means the second
issue is not implemented through the lens of the first. A gate the *parent*
runs means the agent that wrote the code is not the one that decides it
passed.

## Superseded by `/implement-loop`

`/implement-loop` is this skill restructured. It keeps the gating, the
handoffs, the rulings and the give-up path, and adds: every agent runs cold in
a Docker sandbox with no credentials, all side effects stay on the host, and
the batch lands as a PR that CI must pass rather than a direct push. Prefer
it.

This one is still the right call in a repo whose branch takes direct pushes,
or when you want the batch inside your own session where you watch each gate.

Arguments: issue numbers, or nothing at all.

## Where it runs

Everything below is relative to the repo the command was typed in. Nothing
names a repo, and nothing should.

- **The repo** — `gh` resolves `{owner}` and `{repo}` from the checkout's
  remote, so every `gh api` call below is written with those placeholders and
  needs no substitution.
- **The gate** — one command that decides whether work is allowed to land.
  Take it from the repo's `CLAUDE.md` if it names one; otherwise the first of
  `./scripts/check.sh`, `make check`, or a `check` script in `package.json`
  that exists. Resolve it once here and call it *the gate* everywhere below.
  If nothing resolves, abort: a batch with no gate has nobody but the author
  of the code deciding it passed. The `<gate command>` in the per-issue prompt
  is this same command, substituted like `NN`.

## Check the push can land, first

This skill ends with `git push` to the current branch. If that branch is
protected — a ruleset requiring a pull request — the push is rejected, and the
batch sits local with nothing landed after a whole night's work. Check before
doing anything else:

```
branch=$(git rev-parse --abbrev-ref HEAD)
gh api "repos/{owner}/{repo}/rules/branches/$branch" --jq '.[].type'
```

If the output contains `pull_request`, abort. Say that the batch would build
green commits and then fail to push, and that `/implement-loop` is the skill
for this repo — it lands the same batch as a PR that CI must pass. Do not
route around it by landing on some other branch: a batch that lands somewhere
other than where the user asked is not what they typed.

## Pre-flight

Refuse to start unless all of these hold. Each is a way the run could destroy
work that is not its own.

- **Working tree clean** — `git status --porcelain` empty. The failure path
  below resets hard; anything in flight would go with it.
- **Nothing else writing into the working tree** — a dev server, watcher or
  editor that saves into the checkout cannot share a tree with a run that
  resets hard. If the repo's `CLAUDE.md` names a dev command, check whether it
  is up — its pidfile, or `lsof -nP -iTCP:<port> -sTCP:LISTEN` for the port it
  serves — and abort saying how to stop it.
- **`git pull --rebase` clean**, so the night's commits sit on the current tip.
- **The gate green** on the starting commit. A gate that was already red would
  blame the first subagent for something it did not do.

Record the starting SHA. It is the base for the final review.

## Choose the batch and order it

With no arguments, the batch is every open issue labelled `ready-for-agent`.
With arguments, it is exactly those numbers.

Order it either way by GitHub's native dependencies rather than by number —
number order agrees with dependency order only by luck:

```
gh api repos/{owner}/{repo}/issues/<n> --jq '.issue_dependencies_summary'
```

Read `blocked_by` for each issue in the batch and resolve the blockers with
`gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by`. Sort so a
blocker runs before what it blocks. An issue whose blocker is open and *not*
in the batch does not run at all — report it as skipped and why.

Print the ordered plan before dispatching anything.

## Per issue

Record `pre=$(git rev-parse HEAD)`. This is what the failure path returns to.

### Dispatch

One `Agent` call, `subagent_type: general-purpose`, running in the foreground —
the loop is serial on purpose, because issues in one batch usually touch the
same files.

The prompt carries `/implement`'s brief inline. It cannot be reached with the
Skill tool: `/implement` is marked `disable-model-invocation`, so only a human
typing it can invoke it.

> Implement issue #NN in this repo.
>
> Read it first: `gh issue view NN --comments`. Then, if this repo has them,
> read `CONTEXT.md` for the vocabulary and any ADR under `docs/adr/` touching
> the area — use the glossary's terms, not its listed synonyms.
>
> Use `/tdd` where the seams are already agreed. Typecheck and run the
> individual test files you are touching as you go.
>
> When you believe you are done, run `<gate command>` and get it green — it is
> the same gate that will be run against your work afterwards. Then run
> `/code-review` over your own change and act on what it finds.
>
> Commit to the current branch as `CLAUDE.md` requires: linear, each commit a
> reviewable step referencing #NN, any mechanical move in its own commit so
> the rename stays legible.
>
> Do not push. Do not close the issue. If the repo has a `scratch/`, do not
> write into it — that directory is the owner's.
>
> Report back any ruling you landed about a name or a contract — a word
> retired or introduced, a payload or command shape changed, an acceptance
> criterion you could not meet as written and what you did instead. One line
> each, or say there were none. The issues that run after yours were written
> before your commit landed.
>
> [handoff, when it applies]

### Handoff

Two kinds of entry cross between subagents, and nothing else. Both are
appended to the prompt above.

**The blocker that landed.** When this issue is blocked by another one *in
this batch* that has already landed:

> Issue #AA in this same batch blocked this one and has already landed as
> <sha…>. It <two sentences on what it changed and where>. Read that commit
> before starting; it is the only prior work in this run that bears on yours.

**The rulings the batch has made.** Every ruling collected so far goes to
every issue that runs after it, whether or not a dependency edge connects
them:

> The batch has already ruled on these, and your issue body was written before
> they landed:
>
> - <one or two lines per ruling>
>
> Where your issue body and one of these disagree about a word, a contract or
> what a criterion asks for, the ruling wins. Implement the ruling, and say so
> in the commit message: name the ruling and the line of the body it
> overrides.

A ruling qualifies when it was decided after the issues were written and
changes what a later one must do. Three kinds have come up:

- a **word** retired or introduced, or its meaning narrowed;
- a **contract** — a payload field, a command's output, an event's shape;
- a standing decision about **how to read an issue**, where the batch has
  already had to make one.

Collect them from what each subagent reports at the end of its result, plus
any the parent itself made at the gate or in the repair round. Carry the
ruling, not the issue: one or two lines saying what is now true. An issue that
was given up on and reset landed nothing, so its rulings are not true and do
not carry.

**What does not go in a handoff.** Anything that is not one of those two
entries. Not a summary of what each landed issue did, not code a later issue
does not depend on, not review findings or design opinion, and not anything
the issue's own body already says. That restraint is the point of the per-issue
split: a handoff that grows into a running digest of the batch brings back the
context drift a cold subagent exists to avoid.

Both entries earned their place from a run. The blocker edge is the piece of
prior *code* that bears on the next issue. The rulings entry is the piece of
prior *words*: #177 retired **closet** from the glossary, and #171 — written
before that landed, still saying "closet" in its own acceptance criteria — put
the word back in four places, because a cold agent following its issue body is
doing the right thing. No dependency edge joined the two, so no handoff fired.
The batch that filed this hit the shape again: one ruling about how to read a
criterion, needed three times over two issues, and one landed string change,
all injected by hand because `issue_dependencies_summary` was zero for every
one of its seven issues.

### Gate

Both of these, in this order:

1. **The gate** — the exit code is the verdict, no interpretation.
2. **Read `git diff $pre..HEAD` against the issue body.** Green tests say
   nothing broke; they cannot say the issue was addressed. Check each thing
   the issue actually asked for. Check too that the commit messages reference
   the issue — the final review resolves its spec sources from them.

### Repair, once

If either half fails, send the failing output back to the *same* subagent with
`SendMessage` — it still holds the context of what it tried. One round only. A
second cold attempt rarely beats the first, and an unbounded retry loop spends
the whole night on the issue that is fighting you.

### Give up

Still failing after the repair round:

```
git reset --hard $pre
git clean -fd            # untracked only; ignored paths survive
```

Then leave the morning's triage already done: `gh issue comment NN` with what
failed (the failing section of the check output, trimmed), and
`gh issue edit NN --remove-label ready-for-agent --add-label ready-for-human`.

Any issue in the batch blocked by this one is skipped too — its premise never
landed. Report it.

Then continue with the next issue. Two of three landing beats zero.

## After the last issue

### Review the whole range

Run `/code-review` — the mattpocock two-axis one — over `<start-sha>...HEAD`.
Its Spec axis resolves the originating issues from the `#NN` references in the
commit messages, which is why the gate checks they are there.

This is the first look at the *union*: issues in one batch touch overlapping
code, and each subagent only ever reviewed its own slice.

### What the findings do

A **Spec** finding that a requirement was not met holds everything: leave the
commits local, close nothing, file the report, and say plainly in the summary
that nothing was pushed and why. That claim is exactly the one under which a
commit must not land saying `Closes #NN`.

Anything else — **Standards** findings, smells, suggestions — is follow-up
work, not a reason to withhold a batch of green code. Push, then file them.

File findings as one issue:

```
gh label create needs-triage --description "Maintainer needs to evaluate this issue" --color FBCA04 2>/dev/null || true
gh issue create --label needs-triage --title "..." --body "..."
```

The label creation is idempotent because a repo that documents a label has
not necessarily created it.

### Push and close

```
git push
```

Rejected because the remote moved during the run: `git pull --rebase`, re-run
the gate, push again. If the rebase conflicts, stop and report —
resolving a conflict is not an unattended act.

Then `gh issue close NN --comment "..."` naming the commits, for each issue
that landed.

## Report

Close with a summary that stands on its own in the morning: what landed and as
which commits, what failed and what its issue now says, what was skipped and
why, whether the push happened, and the findings issue's number.
