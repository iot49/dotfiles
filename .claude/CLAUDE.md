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

## Git
- The sandbox blocks writes to `.git/config`. Push with
  `git push origin <branch>`, not `-u` or `--set-upstream-to`; pass
  `--head <branch>` to `gh pr create`.
- Run `git branch -D` with the sandbox disabled, so git can drop the
  branch's `.git/config` sections.

## Shell
- The Bash tool runs zsh: `$var` does not split into words, and a glob that
  matches nothing is an error. Quote globs.
- Sandboxed and unsandboxed commands see different `$TMPDIR`s. Write logs of
  unsandboxed commands to the scratchpad directory.

## Secrets
- `~` is a public git repo. Never put a secret in a config file, `.env`, or
  anything under `~` -- including editor settings, which get committed.
- Secrets live in 1Password. Read them at the point of use, never copy them
  to disk:
  ```bash
  op read "op://rails49/Cloudflare Pages/credential"  # one value
  op run -- some-command                              # inject a whole env
  ```
- If a command needs a secret, prefer `op run` over exporting it, so it never
  lands in shell history or a dotfile.
- In Claude Code, `op` runs as the "Claude Code" service account (the `op`
  function in `~/.zshrc` sets `OP_SERVICE_ACCOUNT_TOKEN` when `CLAUDECODE`
  is set).
  It reads only the `rails49` vault, read-only. Ask the user to move any
  other secret there.
- In a plain terminal, `op` uses the desktop app and unlocks with Touch ID.

## Working style
- Simplicity first: minimum code that does the job. No speculative
  abstractions or error handling for impossible cases.
- Surgical diffs: touch only what the task needs, match surrounding style,
  leave pre-existing dead code alone.
- After fixing a bug, add a test that would have caught it.
- Subagents that only search or read files run at low effort. Only a
  subagent that reasons over their results gets high effort.

## Writing
- Plain English. Short declarative sentences, ordinary words.
- No coined terms, metaphors, or branded vocabulary -- not mine, not a
  skill's. If a skill uses jargon, say the same thing in normal words.
- No filler openers ("Great question", "You're absolutely right").
- Terse and technical. State the fact and the pointer, nothing else.
- No intensifiers or emphasis words (loudly, silently, really, exactly,
  crucially); no bold for emphasis.
- Don't justify a design inside a status line or code comment.
  A decision gets an ADR only if it is hard to reverse, surprising
  without context, and the result of a real trade-off. Any other choice
  keeps its reason in the issue that made it, and the behaviour it
  produces goes in the doc or docstring that describes the code now.
- Don't answer objections nobody raised.
