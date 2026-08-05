# .zprofile -- login shells, after /etc/zprofile has run path_helper.
#
# path_helper rebuilds PATH from /etc/paths and /etc/paths.d, moving the system
# directories (/usr/local/bin among them) to the front. That silently undoes the
# ordering set in .zshenv, which is how Homebrew's python@3.11 ends up shadowing
# the uv-managed interpreter. Re-prepend here to win.
#
# `typeset -U path` in .zshenv keeps this from duplicating entries.

export PATH="$HOME/.local/bin:$HOME/.bin:$PATH"
