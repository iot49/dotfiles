---
name: implement-loop-setup
description: One-time per-repo setup for /implement-loop — CI workflow, default-branch ruleset (PR + ci check required, no bypass), auto-merge, labels. Runs implement-loop-setup.sh and confirms the first CI run is green.
disable-model-invocation: true
---

Run `~/.claude/skills/implement-loop/implement-loop-setup.sh` in the repo the
command was typed in, then confirm the result. The script is idempotent and
does the work; this skill is the front door and the post-check.

## Before running

Check cheaply, in this session:

1. `git status --porcelain` is empty, the current branch is the default
   branch, and `gh repo view` resolves. If not, report why and stop.
2. A gate resolves by one of the cases of the `gate` step in the workflow
   that `implement-loop-setup.sh` writes, or, when `.github/workflows/ci.yml`
   already exists, by what that file runs. If none does, ask the user what
   command should be the gate, add a `gate: <command>` line to `CLAUDE.md`,
   and commit and push it before running the script (it refuses a dirty
   tree, and after it runs the branch only takes PRs). CI without a gate
   fails every PR, which blocks every merge.
3. Tell the user, in three lines, what the script will do to this repo:
   commit and push `.github/workflows/ci.yml`; create a ruleset on the
   default branch that requires a PR and the `ci` check **with no bypass,
   for them too**; enable auto-merge and rebase merge. Ask for a one-word
   go-ahead — the ruleset changes how they push to this repo from now on.

## Run

```
~/.claude/skills/implement-loop/implement-loop-setup.sh
```

Foreground; it takes seconds.

## After running

1. If the script printed `ci.yml exists, leaving it alone`, it pushed
   nothing and no run was triggered. Confirm the file has a job named `ci`:
   the ruleset requires that check, and without the job every PR waits for
   it forever. Then go to step 2; the first PR is the first run.

   Otherwise its push of the workflow triggered CI on the default branch.
   Watch that run: `gh run list --workflow ci --commit $(git rev-parse HEAD)
   --json databaseId --jq '.[0].databaseId'` (it can take a few seconds to
   appear), then `gh run watch <id> --exit-status`. If it is red, read the
   log (`gh run view <id> --log-failed`) and fix the cause — a missing tool
   in the workflow, a test that needs a local resource and does not skip on
   `CI=true`, a gate that only works on this machine. A red first run means
   nothing can merge, including the fix, until it is green, and the default
   branch refuses direct pushes. Make the fix on a branch:
   `git switch -c ci-fix`, commit, then
   `git push origin ci-fix && gh pr create --fill --head ci-fix && gh pr merge --auto --rebase`.
   It merges once the check passes.
2. Report: the ruleset name, that auto-merge is on, the CI run result (or
   that none ran), and the user's new landing flow for their own work in
   this repo:
   `git push origin <branch> && gh pr create --fill --head <branch> && gh pr merge --auto --rebase`.
3. Remind them, once: tests that need hardware, local services, or secrets
   must skip themselves when the `CI` environment variable is set; that is
   the whole contract between the host gate and CI.

Then `/implement-loop` is ready to use in this repo.
