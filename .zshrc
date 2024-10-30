export AUTO_NOTIFY_TITLE="%command"
export AUTO_NOTIFY_BODY="\rTime : %elapsed seconds\rExit code : %exit_code"
export BAT_THEME="Dracula"
export EDITOR="nano"
export HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
export HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
export INFOPATH="/home/linuxbrew/.linuxbrew/share/info:${INFOPATH:-}"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export MAVEN_HOME=/opt/maven
export YSU_MESSAGE_FORMAT="$(tput bold)%alias_type found for $(tput setaf 1)%command$(tput sgr0)$(tput bold) : $(tput setaf 2)%alias$(tput sgr0)"
export ZSH="$HOME/.oh-my-zsh"

[ -z "${MANPATH-}" ] || export MANPATH=":${MANPATH#:}"
[ -z "${XDG_DATA_DIRS-}" ] || export XDG_DATA_DIRS="/home/linuxbrew/.linuxbrew/share:${XDG_DATA_DIRS-}"

# export ARCHFLAGS="-arch x86_64"
# export LANG=fr_FR.UTF-8

# Function to add a directory to PATH conditionally
add_to_path() {
    case ":$PATH:" in
        *:"$1":*)
            ;;
        *)
            export PATH="$PATH:$1"
            ;;
    esac
}

add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.cargo/bin"
add_to_path "$JAVA_HOME/bin"
add_to_path "$MAVEN_HOME/bin"
add_to_path "/home/linuxbrew/.linuxbrew/bin"
add_to_path "/home/linuxbrew/.linuxbrew/sbin"
add_to_path "$HOME/.local/share/fnm"
add_to_path "$HOME/.spicetify"
add_to_path "$HOME/.console-ninja/.bin"
add_to_path "/opt/docker-desktop/bin"
add_to_path "/opt/warpdotdev/warp-terminal"
add_to_path "/opt/sonar-scanner/bin"

plugins+=(git sudo fzf-tab zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search command-not-found vscode auto-notify npm ubuntu python pip docker docker-compose gh brew you-should-use)
source $ZSH/oh-my-zsh.sh

fpath+=($HOME/.zfunc ${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions/src)
compinit
source $HOME/.fzf.zsh

AUTO_NOTIFY_IGNORE+=("ghcs" "ghce" "npm run dev" "docker")
COMPLETION_WAITING_DOTS="true"
ENABLE_CORRECTION=true
FNM_PATH="$HOME/.local/share/fnm"
HISTDUP=erase
HISTFILE=$HOME/.zsh_history
HISTSIZE=10000
HIST_STAMPS="dd/mm/yyyy"
HYPHEN_INSENSITIVE=true
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

zstyle ":completion:*" list-colors "${(s.:.)LS_COLORS}"
zstyle ":completion:*" matcher-list "m:{a-z}={A-Za-z}"
zstyle ":completion:*" menu no
zstyle ":completion:*:*:docker:*" option-stacking yes
zstyle ":completion:*:*:docker-*:*" option-stacking yes
zstyle ":fzf-tab:complete:cd:*" fzf-preview "ls --color $realpath"
zstyle ":fzf-tab:complete:__zoxide_z:*" fzf-preview "ls --color $realpath"
zstyle ":omz:update" mode disabled

bindkey "^[[1;5A" history-substring-search-up
bindkey "^[[1;5B" history-substring-search-down

alias apt="apt-fast"
alias apt-get="apt-fast"
alias cln="sudo apt-fast autoremove && sudo apt-fast clean && sudo journalctl --vacuum-size=100M && brew cleanup && pip cache purge && npm cache clean --force && cargo cache -a && flatpak uninstall --unused"
alias cls="clear"
alias code="code-insiders"
alias discord-upgrade="sudo $HOME/Documents/upgrade-discord.sh -b stable -bd false -u $(whoami)"
alias get-path="echo $PATH | tr ':' '\n'"
alias get-zshrc="cat $HOME/.zshrc"
alias git-pulls='for d in ./*/; do (cd "$d" && git pull); done'
alias ls="ls -Ahosp --color=always --group-directories-first"
alias nano="nano -Scim --tabsize=2 --fill=-2"
alias upd="sudo apt-fast update && sudo apt-fast upgrade && brew update && brew upgrade && npm update -g && gh extension upgrade --all && rustup update && cargo install-update -a && sudo snap refresh && sudo flatpak update"
alias upd-extra="sudo oh-my-posh upgrade --force && bash <(curl -sSL https://spotx-official.github.io/run.sh) -dhp --installdeb && spicetify update backup apply && cd $ZSH/custom/plugins && git-pulls && omz update"
alias vencord='sh -c "$(curl -sS https://raw.githubusercontent.com/Vendicated/VencordInstaller/main/install.sh)"'

eval "$(oh-my-posh init zsh --config $HOME/omp/EDM115-newline.omp.json)"
eval "$(zoxide init --cmd cd zsh)"
eval "$(fnm env --use-on-cd --version-file-strategy=recursive --shell zsh)"
eval "$(gh copilot alias -- zsh)"
eval "$(thefuck --alias)"
