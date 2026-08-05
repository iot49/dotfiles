# Global preferences

Read every session — keep this short. Project-specific rules belong in the
project's own CLAUDE.md.

## Python
- `uv` for versions and environments; run things with `uv run`.
- Ruff, Black, Pyright for lint/format/type-check, notebooks included.

## Web frontend
- TypeScript and pnpm.
- Lit for components: small and focused, split when they grow, tested.
- No inline CSS in HTML. 2-space indentation.

## Editor
- VS Code is the default editor (`code`).

## Working style
- Simplicity first: minimum code that does the job. No speculative
  abstractions or error handling for impossible cases.
- Surgical diffs: touch only what the task needs, match surrounding style,
  leave pre-existing dead code alone.
- After fixing a bug, add a test that would have caught it.
