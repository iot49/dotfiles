# .zshenv -- read by EVERY zsh: interactive, non-interactive, scripts, subshells.
#
# PATH lives here rather than in .zshrc (which only runs for interactive shells)
# so that Makefiles, `sh -c`, subprocess calls, cron and launchd jobs resolve the
# same python/tools as an interactive terminal. Without this, `python3` means
# uv 3.12 in a terminal but Homebrew 3.11 in a script.
#
# Login shells additionally run /etc/zprofile -> path_helper, which hoists the
# system directories back to the front and undoes the ordering below. ~/.zprofile
# re-prepends afterwards to restore it. Both files are needed.

. "$HOME/.cargo/env"

# Keep PATH entries unique; the first occurrence wins, so re-prepending later is
# idempotent rather than producing duplicates.
typeset -U path PATH

export PATH="$HOME/.local/bin:$HOME/.bin:$PATH"
