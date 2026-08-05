# cd path
cdpath=($HOME $HOME/iot $HOME/Documents $HOME/Dropbox)
setopt NO_CASE_GLOB   # case insensitive completion
setopt AUTO_CD        # cd optional

# hostname
export HOSTNAME=`hostname`
substring=".local"
if [[ "$HOSTNAME" == *"$substring"* ]]; then
  HOSTNAME=${HOSTNAME//$substring/}
fi

# prompt (may be overridden by architecture-specific customization below)
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
SAVEHIST=10000
HISTSIZE=10000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_FIND_NO_DUPS
setopt HIST_EXPIRE_DUPS_FIRST

# Local bin path
export PATH="$HOME/.local/bin:$HOME/.bin:$PATH"

# helper ... source if file exists
function run_if() {
    [[ -f $1 ]] && . $1
}

# init packages
run_if "$HOME/.local/bin/env"

# pyenv (disabled in favor of uv-managed Python)
# export PYENV_ROOT="$HOME/.pyenv"
# command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
# eval "$(pyenv init -)"

# direnv
eval "$(direnv hook zsh)"

# alias commands
run_if "$HOME/.zsh_alias"

# cd aliases
alias iot='cd ~/iot'
alias blog49='cd ~/iot/blog49'
alias rails49='cd ~/iot/rails49'
alias blocks49='cd ~/iot/blocks49'

# Git Separation Ceiling
export GIT_CEILING_DIRECTORIES="$HOME"

# architecture specific customizations (e.g. .zshrc_Darwin, .zshrc_Linux)
run_if "$HOME/.zshrc_`uname`"

# Added by LM Studio CLI (lms)
export PATH="$PATH:$HOME/.lmstudio/bin"

# java (openjdk installed with brew)
# For the system Java wrappers to find this JDK, symlink it with
#   sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
# pnpm
export PNPM_HOME="/Users/ttmetro/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
