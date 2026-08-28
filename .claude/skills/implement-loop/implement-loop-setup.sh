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

# ---- 1. workflow -----------------------------------------------------------
WF=.github/workflows/ci.yml
if [ -f "$WF" ]; then
  say "$WF exists, leaving it alone (the required check is the job named 'ci')"
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
      - uses: pnpm/action-setup@v4
        if: hashFiles('pnpm-lock.yaml') != ''
      - uses: actions/setup-node@v4
        if: hashFiles('package.json') != ''
        with:
          node-version: 22
      - run: pnpm install --frozen-lockfile
        if: hashFiles('pnpm-lock.yaml') != ''
      - name: gate
        run: |
          cmd=\$(sed -n 's/^ci:[[:space:]]*//p' CLAUDE.md 2>/dev/null | head -1)
          [ -n "\$cmd" ] || cmd=\$(sed -n 's/^[Gg]ate:[[:space:]]*//p' CLAUDE.md 2>/dev/null | head -1)
          [ -n "\$cmd" ] || { [ -x scripts/check.sh ] && cmd=./scripts/check.sh; }
          [ -n "\$cmd" ] || { grep -qE '^check:' Makefile 2>/dev/null && cmd="make check"; }
          [ -n "\$cmd" ] || { echo "no ci:/gate: line in CLAUDE.md, no scripts/check.sh, no make check"; exit 1; }
          echo "+ \$cmd"
          bash -c "\$cmd"
YAML
  git add "$WF"
  git commit -q -m "ci: gate on every PR (implement-loop-setup)"
  git push || die "push failed — is $DEFAULT already protected? Open a PR for $WF by hand, then re-run."
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

say "done. $DEFAULT now only moves by PR with the 'ci' check green — for you as well:"
echo "    git push -u origin <branch> && gh pr create --fill && gh pr merge --auto --rebase"
