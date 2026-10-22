---
name: implement-loop
description: Launch an unattended Ralph-style batch over ready-for-agent issues — cold sandboxed agent per issue, tool-less screening judge on every issue body and on the notes each agent leaves for the next, host-side gates and side effects, one review over the whole range, PR auto-merged on CI green, results as closed issues plus a loop-report summary issue.
disable-model-invocation: true
---

Launch `~/.claude/skills/implement-loop/implement-loop.sh` in the background,
from the repo the command was typed in, and get out of the way. The script is
self-contained; this skill is only the front door.

Arguments: issue numbers, or — the default — nothing at all. With nothing,
the batch is every open issue labelled `ready-for-agent`, and after a merged
batch the script re-queries the label and keeps going while anything new or
newly unblocked is runnable. Run the batch as given; a subset is the user's
to name. `--resume` and `--force-new` pass through to the script: they
continue or discard a run that stopped early, which a plain launch refuses to
overwrite.

## Before launching

Typing the command is the go-ahead: launch at once. The only thing that stops
a launch is one of the checks below failing, and a failed check is reported,
which ends the turn.

Check these cheaply, in this session, without starting anything heavy. Each is
a condition the run cannot recover from, so on a failure say what is wrong and
what fixes it, and stop.

1. `git status --porcelain` is empty, the current branch is the default
   branch, and `gh repo view` resolves. The script would refuse anyway, but
   failing here is faster and says more.
2. The repo has been set up: `gh api repos/{owner}/{repo}/rules/branches/<default> --jq '.[].type'`
   lists `pull_request` and `required_status_checks`, and
   `.github/workflows/ci.yml` exists. If not, tell the user to run
   `/implement-loop-setup` once and stop.
3. `~/.claude/skills/implement-loop/implement-loop.sh` exists and is
   executable.

An empty batch is not a failure to ask about: if nothing carries
`ready-for-agent` and no issues were named, say so and stop.

## Launch

Launch it with the Bash sandbox **disabled** (`dangerouslyDisableSandbox:
true`). This is not optional and not a retry-on-failure: the run drives its
agent inside a Docker sandbox, a backgrounded process inherits the sandbox of
the call that started it, and the sandbox denies `docker.sock`. Launched
inside it the run dies in its first seconds, before the container it needs
exists.

```
mkdir -p .implement-loop && touch .implement-loop/launch
nohup bash ~/.claude/skills/implement-loop/implement-loop.sh <args> \
  > /dev/null 2>&1 &
echo $!
```

The script tees its own log to `.implement-loop/run-<timestamp>.log`.

Confirm it got past the Docker smoke test before reporting, with this command
as it stands (foreground, sandbox on, `timeout: 180000`). It reads only a log
written since the launch, so an older run's log cannot answer for this one:

```
for i in $(seq 75); do
  log=$(find .implement-loop -maxdepth 1 -name 'run-*.log' -newer .implement-loop/launch | head -1)
  [ -n "$log" ] && grep -qE '^(== sandbox:|ABORT)' "$log" && break
  sleep 2
done
echo "${log:-no log since the launch}"; [ -n "$log" ] && head -20 "$log"
```

Started means the lines `== pre-flight`, `== gate:` and
`== sandbox: <container id>`. An `ABORT` line is a failed launch: report it,
with the commands it names. No log means the launch was sandboxed after all.

`implement-loop.sh --status`, run with the sandbox off, answers later
questions about a run.

On startup it prunes per-run artifacts in `.implement-loop/` older than
`IL_KEEP_DAYS` (default 14). `rulings.md` is never pruned; what happened to an
issue lives in the issue and its PR.

## Then report, and stop

Tell the user, in one pass, without asking anything:

- the PID and the log path, and that
  `tail -f .implement-loop/run-*.log` follows it;
- which issues the first batch contains (`gh issue list --label
  ready-for-agent --state open` if no arguments were given) — this is
  information about a run that has already started, not a proposal;
- that results arrive on GitHub: merged issues closed, failures and
  screened-out issues relabelled `ready-for-human` with the reason as a
  comment, and one `loop-report` summary issue whose top section is the
  action list, closed at once when the list holds nothing to act on;
- that the run works in its own git worktree under `.implement-loop/tree`,
  so the checkout it was started from stays on the default branch and is
  free to use while the batch runs;
- that the batch lands as one PR on a branch, auto-merged when CI is green,
  unless the diff touches protected paths (CI, gate, dependency manifests,
  test deletions) — then the PR is held for a human and the summary issue
  says so.

The report ends the turn. Nobody watches the run.
