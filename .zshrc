# cd path
cdpath=($HOME/Documents $HOME/Documents/iot $HOME/Documents/server)
setopt NO_CASE_GLOB   # case insensitive completion
setopt AUTO_CD        # cd optional

# hostname
export HOSTNAME=`hostname`
substring=".local"
if [[ "$HOSTNAME" == *"$substring"* ]]; then
  HOSTNAME=${HOSTNAME//$substring/}
fi

# prompt
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats '%b '
setopt PROMPT_SUBST
PROMPT='%F{red}${HOSTNAME} %F{blue}%2~ %f$ '

# ls
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# history
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
SAVEHIST=5000
HISTSIZE=2000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS

PATH=~/.bin:$PATH

# helper ... source if file exists
function run_if() {
    [[ -f $1 ]] && . $1
}

# init packages
run_if "$HOME/.local/bin/env"
run_if "$HOME/.cargo/env"

# direnv
eval "$(direnv hook zsh)"

# alias commands
alias ll='ls -l'
alias la='ls -la'
alias server='ssh boser@server.local'

# docker
alias docker-compose='docker compose'
alias dc='docker compose'

# architecture specific customizations (e.g. .zshrc_Darwin, .zshrc_Linux)
run_if "$HOME/.zshrc_`uname`"
