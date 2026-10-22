#!/usr/bin/env bash
#
# implement-loop-setup — once per repo, before the first implement-loop run.
#
# Puts in place the three things implement-loop's pre-flight refuses to run
# without:
#   1. .github/workflows/ci.yml — runs the repo's `ci:` (else `gate:`) line
#      from CLAUDE.md with CI=true, on every PR. Committed and pushed here,
#      BEFORE the ruleset closes the door on direct pushes.
#   2. A ruleset on the default branch: PR required, status check `ci`
#      required, linear history, no deletion, no force-push. Bypass list is
#      EMPTY — it applies to you too. The host script pushes with your
#      credential; a rule you could bypass is a rule the script could bypass.
#   3. Repo settings: auto-merge on, rebase merge on, delete branch on merge.
#   4. Labels: ready-for-agent, ready-for-human, needs-triage, loop-report.
#
# Idempotent: re-running skips what exists.
#
# Tests that need local resources (hardware, local services) must skip
# themselves when CI=true; the workflow sets it, nothing else does.

set -eu

die() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "gh cannot resolve this repo"
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
[ "$(git branch --show-current)" = "$DEFAULT" ] || die "switch to $DEFAULT first"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
git pull --rebase
# the push below would carry them to $DEFAULT, past CI
[ -z "$(git rev-list "origin/$DEFAULT..HEAD")" ] \
  || die "$DEFAULT has commits not on origin. Push or drop them first, so this pushes only the workflow."

# ---- 1. workflow -----------------------------------------------------------
WF=.github/workflows/ci.yml
if [ -f "$WF" ]; then
  # checked before the ruleset exists: after it, a missing job blocks every PR
  grep -qE '^[[:space:]]+(ci:|name:[[:space:]]*ci)[[:space:]]*$' "$WF" \
    || die "$WF has no job named 'ci'. The ruleset requires that check, so every PR would wait for it forever. Name a job ci, or remove the file to have one written, then re-run."
  say "$WF exists, leaving it alone (it has the job 'ci' the ruleset requires)"
else
  say "writing $WF"
  mkdir -p .github/workflows
  cat > "$WF" <<YAML
name: ci
on:
  pull_request:
  push:
    branches: [$DEFAULT]
jobs:
  ci:
    runs-on: ubuntu-latest
    env:
      CI: "true"
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        if: hashFiles('pyproject.toml') != ''
      - run: uv sync
        if: hashFiles('pyproject.toml') != ''
      # action-setup fails with no pnpm version, and also when given one
      # beside package.json's packageManager; pass one only when that is absent
      - id: pnpm
        if: hashFiles('pnpm-lock.yaml') != ''
        run: grep -q '"packageManager"' package.json || echo "version=10" >> "\$GITHUB_OUTPUT"
      - uses: pnpm/action-setup@v4
        if: hashFiles('pnpm-lock.yaml') != ''
        with:
          version: \${{ steps.pnpm.outputs.version }}
      - uses: actions/setup-node@v4
        if: hashFiles('package.json') != ''
        with:
          node-version: 22
      - run: pnpm install --frozen-lockfile
        if: hashFiles('pnpm-lock.yaml') != ''
      - run: npm ci
        if: hashFiles('package-lock.json') != ''
      - name: gate
        run: |
          cmd=\$(sed -n 's/^ci:[[:space:]]*//p' CLAUDE.md 2>/dev/null | head -1)
          [ -n "\$cmd" ] || cmd=\$(sed -n 's/^[Gg]ate:[[:space:]]*//p' CLAUDE.md 2>/dev/null | head -1)
          [ -n "\$cmd" ] || { [ -x scripts/check.sh ] && cmd=./scripts/check.sh; }
          [ -n "\$cmd" ] || { grep -qE '^check:' Makefile 2>/dev/null && cmd="make check"; }
          [ -n "\$cmd" ] || { node -e 'process.exit(require("./package.json").scripts?.check ? 0 : 1)' 2>/dev/null && cmd="npm run check"; }
          [ -n "\$cmd" ] || { echo "no ci:/gate: line in CLAUDE.md, no scripts/check.sh, no make check, no npm check script"; exit 1; }
          echo "+ \$cmd"
          bash -c "\$cmd"
YAML
  git add "$WF"
  git commit -q -m "ci: gate on every PR (implement-loop-setup)"
  # a refused push must not leave the commit on $DEFAULT: a re-run would find
  # the file and skip the workflow that never reached the remote
  git push origin "$DEFAULT" || {
    git branch -f implement-loop-ci HEAD
    git reset -q --hard "origin/$DEFAULT"
    die "push to $DEFAULT refused — is it already protected? The workflow commit is on branch implement-loop-ci and $DEFAULT is back at origin. Land it with
    git push origin implement-loop-ci && gh pr create --fill --head implement-loop-ci
merge that PR once its ci check is green, then re-run."
  }
fi

# ---- 2. ruleset -----------------------------------------------------------
NAME="implement-loop: protect $DEFAULT"
if gh api "repos/$REPO/rulesets" --jq '.[].name' | grep -qxF "$NAME"; then
  say "ruleset '$NAME' exists"
else
  say "creating ruleset '$NAME'"
  gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null <<JSON
{
  "name": "$NAME",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": [{"context": "ci"}]}}
  ]
}
JSON
fi

# ---- 3. repo settings -----------------------------------------------------
say "repo settings: auto-merge, rebase merge, delete branch on merge"
gh api -X PATCH "repos/$REPO" -F allow_auto_merge=true -F allow_rebase_merge=true \
  -F delete_branch_on_merge=true >/dev/null

# ---- labels ---------------------------------------------------------------
gh label create ready-for-agent --description "implement-loop may take this" --color 0E8A16 2>/dev/null || true
gh label create ready-for-human --description "implement-loop gave up or held this" --color D93F0B 2>/dev/null || true
gh label create needs-triage --description "Maintainer needs to evaluate this issue" --color FBCA04 2>/dev/null || true
gh label create loop-report --description "implement-loop batch summary" --color C5DEF5 2>/dev/null || true

say "done. $DEFAULT now only moves by PR with the 'ci' check green — for you as well:"
echo "    git push origin <branch> && gh pr create --fill --head <branch> && gh pr merge --auto --rebase"
