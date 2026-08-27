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

## Secrets
- `~` is a public git repo. Never put a secret in a config file, `.env`, or
  anything under `~` -- including editor settings, which get committed.
- Secrets live in 1Password. Read them at the point of use, never copy them
  to disk:
  ```bash
  op read "op://Private/OpenRouter/credential"        # one value
  op run -- some-command                              # inject a whole env
  ```
- If a command needs a secret, prefer `op run` over exporting it, so it never
  lands in shell history or a dotfile.
- Requires 1Password -> Settings -> Developer -> "Integrate with 1Password
  CLI"; `op` then unlocks with Touch ID, so no manual `op signin` per session.

## Working style
- Simplicity first: minimum code that does the job. No speculative
  abstractions or error handling for impossible cases.
- Surgical diffs: touch only what the task needs, match surrounding style,
  leave pre-existing dead code alone.
- After fixing a bug, add a test that would have caught it.
