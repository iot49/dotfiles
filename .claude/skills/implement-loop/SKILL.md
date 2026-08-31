---
name: implement-loop
description: Launch an unattended Ralph-style batch over ready-for-agent issues — cold sandboxed agent per issue, tool-less screening judge on every input and reply, host-side gates and side effects, one review over the whole range, PR auto-merged on CI green, results as closed issues plus a needs-triage summary issue.
disable-model-invocation: true
---

Launch `~/.claude/skills/implement-loop/implement-loop.sh` in the background,
from the repo the command was typed in, and get out of the way. The script is
self-contained; this skill is only the front door.

Arguments: issue numbers, or — the default — nothing at all. With nothing,
the batch is every open issue labelled `ready-for-agent`, and after a merged
batch the script re-queries the label and keeps going while anything new or
newly unblocked is runnable. Do not narrow the batch on the user's behalf;
if they wanted a subset they would have named it.

## Before launching

Launch without asking. Typing the command is the go-ahead; a run that waits
for a second one is not unattended. Do not confirm the batch, do not present a
plan for approval, do not offer to narrow or reorder anything. The only thing
that stops a launch is one of the checks below failing, and a failed check is
reported, never turned into a question.

Check these cheaply, in this session, without starting anything heavy. Each is
a condition the run cannot recover from, so on a failure say what is wrong and
what fixes it, and stop.

1. `git status --porcelain` is empty, the current branch is the default
   branch, and `gh repo view` resolves. The script would refuse anyway, but
   failing here is faster and says more.
2. The repo has been set up: `gh api repos/{owner}/{repo}/rules/branches/<default> --jq '.[].type'`
   lists `pull_request` and `required_status_checks`, and
   `.github/workflows/ci.yml` exists. If not, tell the user to run
   `~/.claude/skills/implement-loop/implement-loop-setup.sh` once and stop.
3. `~/.claude/skills/implement-loop/implement-loop.sh` exists and is
   executable.

An empty batch is not a failure to ask about: if nothing carries
`ready-for-agent` and no issues were named, say so and stop.

## Launch

```
mkdir -p .implement-loop
nohup bash ~/.claude/skills/implement-loop/implement-loop.sh <args> \
  > /dev/null 2>&1 &
echo $!
```

The script tees its own log to `.implement-loop/run-<timestamp>.log`.

## Then report, and stop

Tell the user, in one pass, without asking anything:

- the PID and the log path, and that
  `tail -f .implement-loop/run-*.log` follows it;
- which issues the first batch contains (`gh issue list --label
  ready-for-agent --state open` if no arguments were given) — this is
  information about a run that has already started, not a proposal;
- that results arrive on GitHub: merged issues closed, failures and
  screened-out issues relabelled `ready-for-human` with the reason as a
  comment, and one `needs-triage` summary issue whose top section is the
  action list;
- that the batch lands as one PR on a branch, auto-merged when CI is green,
  unless the diff touches protected paths (CI, gate, dependency manifests,
  test deletions) — then the PR is held for a human and the summary issue
  says so.

Do not wait for the run, poll the log, or offer to babysit it. The whole
point is that nobody watches.

## One-time setup (per machine / per repo)

- `docker sandbox run claude` once interactively in the workspace, so the
  sandbox is authenticated. The script smoke-tests this and aborts with this
  instruction if it fails.
- `implement-loop-setup.sh` once per repo: writes and pushes the CI
  workflow, creates the default-branch ruleset (PR + `ci` check required, no
  bypass — applies to the user too), enables auto-merge and rebase merge,
  creates the labels.
- The sandbox loads only what is inside the repo: install the skills the
  implementer uses (`/tdd`, `/code-review`) into the project with
  `npx skills add mattpocock/skills`. If they are absent the run still works —
  the prompts carry fallbacks — but the reviews are better with them.
- The gate resolves as: `IL_GATE` env var, a `gate: <command>` line in
  `CLAUDE.md`, `./scripts/check.sh`, `make check`, then an npm `check` script.
  No gate, no run. CI runs the `ci:` line if present, else the same gate,
  with `CI=true` set so local-resource tests can skip themselves.
