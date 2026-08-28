# implement-loop

Unattended batch implementation of GitHub issues. Successor to
`batch-implement`, restructured Ralph-style: a bash loop is the orchestrator,
every LLM step runs in a cold Docker-sandboxed `claude -p`, and all side
effects (git, gh) stay on the host.

Lineage: [batch-implement](../batch-implement/SKILL.md) (gating, handoffs,
rulings, the give-up path) crossed with
[Ralph Wiggum](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)
(cold context per unit of work, bash as the loop, Docker sandbox).

## Files

| File                | Purpose                                                        |
| ------------------- | -------------------------------------------------------------- |
| `implement-loop.sh` | The whole machine. Self-contained; runnable without the skill. |
| `SKILL.md`          | `/implement-loop` — thin launcher so the interface matches the other skills. Confirms the batch, `nohup`s the script, reports the log path. |

## What one run does

```
pre-flight   clean tree, pull --rebase, gate green, sandbox smoke test
batch        args, or every open issue labelled ready-for-agent;
             ordered by GitHub's native blocked-by dependencies
per issue    fetch issue body to a file (host)
             → cold sandboxed agent implements, commits locally
             → gate runs on the host: exit code is the verdict
             → second cold agent verifies the diff against the issue body
             → one repair round via --resume into the SAME session
             → landed, or: reset --hard, comment the failure on the
               issue, relabel ready-for-human, skip its dependents
after        one review over the whole range (start-sha...HEAD)
             → push (rebase-retry once; a conflict stops the push,
               never gets resolved unattended)
             → close issues that landed clean
             → summary issue, labelled needs-triage, action items first
```

## Design decisions

**Host does every side effect.** The container mounts only the working
directory and holds no credentials — issue bodies are pre-fetched to files, so
it never needs `gh`. Pushing, closing, labelling, and the hard resets are done
by bash on the host, under your normal keychain. A runaway agent can write
files; it cannot touch GitHub, and the agent that just failed is never the one
executing the reset.

**Cold context per issue** (Ralph's property). The second issue is not
implemented through the lens of the first, and the final review starts from
zero instead of from a 200k-token session. The two things that legitimately
cross between issues are carried explicitly, in files:

- `.implement-loop/rulings.md` — decisions the batch made that later issue
  bodies predate (a word retired, a contract changed). Injected into every
  later prompt; the ruling wins over the issue body.
- per-issue handoffs — when a blocker landed in the same batch, its author's
  two-sentence summary and SHA go to the dependent issue. Nothing else does.

**The gate is mechanical, the checks are separated.** The gate's exit code is
the verdict, no interpretation. The diff-vs-issue-body judgment is made by a
*different* cold agent than the one that wrote the code — same principle as
batch-implement's parent-runs-the-gate, kept across the process split.

**A Spec finding holds the claim, not the push.** If the final review finds a
requirement not met on #NN, the commits still push (they are gate-green and
reviewed), but #NN is not closed — no commit gets to assert `Closes #NN` under
a false claim. It goes back to `ready-for-human` with the finding.

**Repair resumes, never retries cold.** `claude -p --output-format json`
returns a `session_id`; the repair prompt goes back into that session with
`--resume`, because the agent that holds the context of what it tried beats a
second cold attempt. One round only, then give up — two of three landing beats
zero, and an unbounded retry spends the night on the issue that is fighting
you.

## Setup

Once per machine/workspace:

```sh
docker sandbox run claude        # authenticate the sandbox interactively once
```

Once per repo:

```sh
npx skills add mattpocock/skills # puts /tdd and /code-review INSIDE the repo,
                                 # which is all the sandbox can see
```

(The run works without them — the prompts carry fallbacks — but reviews are
better with them.)

The gate resolves, in order: `IL_GATE` env var → a `gate: <command>` line in
`CLAUDE.md` → `./scripts/check.sh` → `make check` → an npm `check` script.
No gate, no run: a batch with no gate has nobody but the author of the code
deciding it passed.

Labels used: `ready-for-agent` (input), `ready-for-human` (failures/holds),
`needs-triage` (summary issue; created idempotently).

## Usage

From a Claude Code session in the target repo:

```
/implement-loop            # the whole ready-for-agent backlog
/implement-loop 42 43 51   # exactly these
```

Or directly, no LLM in the outer loop at all:

```sh
~/.claude/skills/implement-loop/implement-loop.sh 42 43 51
```

Environment:

| Variable        | Effect                                                  |
| --------------- | ------------------------------------------------------- |
| `IL_GATE`       | Override gate resolution with an explicit command.      |
| `IL_EXTRA_ARGS` | Extra args for every claude call, e.g. `--model opus`.  |

Everything the run produces on disk lives in `.implement-loop/` (logs,
prompts, diffs, verdicts, rulings). The directory is added to
`.git/info/exclude`, so it is ignored without touching `.gitignore` and
survives the failure path's `git clean -fd`.

## What comes back

- Landed issues: closed, with the commit range in the closing comment.
- Failed issues: reset to their pre-SHA, failing output as a comment,
  relabelled `ready-for-human`; their in-batch dependents are skipped.
- Spec-flagged issues: pushed but left open, relabelled `ready-for-human`.
- One `needs-triage` summary issue whose **first section is the action list**:
  what needs a human, or "Nothing" when everything landed, pushed, and closed.
  Below it: what landed, the rulings the batch made, and the full review.

## First-run checklist

Run a two-issue batch in a low-stakes repo, watching
`tail -f .implement-loop/run-*.log`, and confirm:

1. **`--resume` bridges container invocations.** Kill after a dispatch, then
   `docker sandbox run claude -p --resume <sid> "what did you just do"`. If
   sessions don't persist in the sandbox, the repair round is silently a cold
   retry.
2. **JSON survives docker's stdout.** First runs can prepend setup noise; the
   parser skips to the first valid `{`, but verify on this machine.
3. **Gate parity.** The gate runs on the host; the agent also runs it inside
   the container. A toolchain version mismatch makes the agent green and the
   host red, burning the repair round on environment rather than code. Force
   one red run to see what the failure path looks like.
