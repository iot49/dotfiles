# cd path
cdpath=($HOME/Dropbox $HOME/Dropbox/iot $HOME/Dropbox/server)
setopt NO_CASE_GLOB   # case insensitive completion
setopt AUTO_CD        # cd optional

# prompt
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '%b '
setopt PROMPT_SUBST
PROMPT='%F{blue}%2~ %f$ '

# ls
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# load custom shell functions
fpath+=~/.zsh_func

# history
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
SAVEHIST=5000
HISTSIZE=2000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS

. "$HOME/.cargo/env"
. "$HOME/.local/bin/env"

alias ll='ls -l'
alias la='ls -la'

alias dc='docker compose'

alias server='ssh boser@server.local'
alias server='ssh boser@host.docker.internal'

# one of Darwin (mac), Linux (docker container)
export MACHINE=`uname`