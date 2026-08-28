---
name: implement-loop
description: Launch an unattended Ralph-style batch over ready-for-agent issues — cold sandboxed agent per issue, host-side gates and side effects, one review over the whole range, automatic push, results as closed issues plus a needs-triage summary issue.
disable-model-invocation: true
---

Launch `~/.claude/skills/implement-loop/implement-loop.sh` in the background,
from the repo the command was typed in, and get out of the way. The script is
self-contained; this skill is only the front door.

Arguments: issue numbers, or nothing at all (nothing = every open issue
labelled `ready-for-agent`).

## Before launching

Check cheaply, in this session, without starting anything heavy:

1. `git status --porcelain` is empty and `gh repo view` resolves. If not,
   report why and stop — the script would refuse anyway, but failing here is
   friendlier.
2. `~/.claude/skills/implement-loop/implement-loop.sh` exists and is
   executable.
3. Tell the user which issues the batch will contain (run
   `gh issue list --label ready-for-agent --state open` if no arguments were
   given) and which gate will likely resolve, then ask for a one-word go-ahead.
   This is the only human touchpoint; after it, the run is unattended through
   to the push.

## Launch

```
mkdir -p .implement-loop
nohup bash ~/.claude/skills/implement-loop/implement-loop.sh <args> \
  > /dev/null 2>&1 &
echo $!
```

The script tees its own log to `.implement-loop/run-<timestamp>.log`.

## Then report, and stop

Tell the user:

- the PID and the log path, and that
  `tail -f .implement-loop/run-*.log` follows it;
- that results arrive on GitHub: landed issues closed, failures relabelled
  `ready-for-human` with the failing output as a comment, and one
  `needs-triage` summary issue whose top section is the action list;
- that the commits push automatically unless the remote moved and the rebase
  conflicted, in which case the summary issue says so.

Do not wait for the run, poll the log, or offer to babysit it. The whole
point is that nobody watches.

## One-time setup (per machine / per repo)

- `docker sandbox run claude` once interactively in the workspace, so the
  sandbox is authenticated. The script smoke-tests this and aborts with this
  instruction if it fails.
- The sandbox loads only what is inside the repo: install the skills the
  implementer uses (`/tdd`, `/code-review`) into the project with
  `npx skills add mattpocock/skills`. If they are absent the run still works —
  the prompts carry fallbacks — but the reviews are better with them.
- The gate resolves as: `IL_GATE` env var, a `gate: <command>` line in
  `CLAUDE.md`, `./scripts/check.sh`, `make check`, then an npm `check` script.
  No gate, no run.
