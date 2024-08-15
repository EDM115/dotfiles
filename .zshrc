export AUTO_NOTIFY_TITLE="%command"
export AUTO_NOTIFY_BODY="\rTime : %elapsed seconds\rExit code : %exit_code"
export EDITOR='nano'
export NVM_DIR="$HOME/.nvm"
export PATH=~/.console-ninja/.bin:~/.local/bin:$PATH
export YSU_MESSAGE_FORMAT="$(tput bold)%alias_type found for $(tput setaf 1)%command$(tput sgr0)$(tput bold) : $(tput setaf 2)%alias$(tput sgr0)"
export ZSH="$HOME/.oh-my-zsh"

# export ARCHFLAGS="-arch x86_64"
# export LANG=fr_FR.UTF-8
# COMPLETION_WAITING_DOTS="true"
# DISABLE_UNTRACKED_FILES_DIRTY="true"
# ENABLE_CORRECTION="true"

plugins+=(git sudo fzf-tab zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search command-not-found vscode auto-notify npm ubuntu python pip docker docker-compose gh brew you-should-use)
source $ZSH/oh-my-zsh.sh

fpath+=(~/.zfunc ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src)
compinit

AUTO_NOTIFY_IGNORE+=("ghcs" "ghce" "npm run dev")
HISTDUP=erase
HISTFILE=~/.zsh_history
HISTSIZE=10000
HIST_STAMPS="dd/mm/yyyy"
SAVEHIST=$HISTSIZE
VSCODE=code-insiders
ZSH_THEME="dracula"

setopt appendhistory
setopt hist_find_no_dups
setopt hist_ignore_all_dups
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_save_no_dups
setopt sharehistory

zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu no
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'
zstyle ':omz:update' mode disabled

bindkey '^[[1;5A' history-substring-search-up
bindkey '^[[1;5B' history-substring-search-down

alias apt="apt-fast"
alias apt-get="apt-fast"
alias cln="sudo apt-fast autoremove && sudo apt-fast clean && brew cleanup && pip cache purge && npm cache clean --force && cargo cache -a && flatpak uninstall --unused"
alias cls="clear"
alias discord="sudo ~/Documents/launch-discord.sh -b ptb -bd true -u $(whoami)"
alias git-pulls='for d in ./*/; do (cd "$d" && git pull); done'
alias ls="ls -Ahosp --color=always --group-directories-first"
alias nano="nano -Scim --tabsize=2 --fill=-2"
alias upd="sudo apt-fast update && sudo apt-fast upgrade && brew update && brew upgrade && npm update -g && gh extension upgrade --all && rustup update && cargo install-update -a && sudo snap refresh && sudo flatpak update"
alias upd-extra="sudo curl -s https://ohmyposh.dev/install.sh | sudo bash -s && bash <(curl -sSL https://spotx-official.github.io/run.sh) -dhp --installdeb && omz update"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

eval "$(oh-my-posh init zsh --config ~/omp/EDM115-newline.omp.json)"
eval "$(zoxide init --cmd cd zsh)"
eval "$(gh copilot alias -- zsh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
