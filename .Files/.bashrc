# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi


# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi


# Setup History
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=erasedups:ignoredups:ignorespace
export HISTSIZE=2000
export HISTFILESIZE=2000


# Setup Editor
export EDITOR=nvim
export VISUAL=nvim


# Setup color
force_color_prompt=yes
export PS1="\033[36m\u\033[35m @ \033[36m\h\033[35m [ \033[32m\w \033[35m]\033[37m \n$ "


# Bash Completion
unset rc
source /etc/profile.d/bash_completion.sh
source /usr/share/fzf/shell/key-bindings.bash


# Aliases
alias ls="ls --color -A --group-directories-first"
alias ll="ls --color -lAthr --group-directories-first"
alias l.="ls -d .* --color --group-directories-first"
alias grep="grep --color"
alias vim="/usr/bin/nvim"
alias c..="cd ../.."
alias untar="tar -zxvf"
alias nao="sudo reboot now"

. "$HOME/.cargo/env"

# TMUX
# Bootstrap TPM in TMUX
[[ ! -d "~/.tmux/plugins/tpm" ]] && { git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm;}
# Connect to tmux when you launch the terminal
[ -z "$TMUX"  ] && { tmux attach || exec tmux new-session -s void;}


# Enable Powerlevel11k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
setopt beep extendedglob nomatch
unsetopt autocd
bindkey -e

# Add highlight enabled tab completion with colors
zstyle ':completion:*' menu select
eval "$(dircolors)"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Get bash's compgen
autoload -Uz compinit
compinit
autoload -Uz bashcompinit
bashcompinit

# Downloading and sourcing themes, plugins, etc.
# check if ~/.zsh exists
if [ ! -d "$HOME/.zsh" ]; then
    echo "Creating a .zsh folder in $HOME"
    echo "This can be copied elsewhere and then linked, preferrably using GNU stow"
    mkdir $HOME/.zsh
fi

# check if p10k exists
if [ ! -d "$HOME/.zsh/powerlevel10k" ]; then
    echo "Installing powerelevel10k theme."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.zsh/powerlevel10k
fi

source $HOME/.zsh/powerlevel10k/powerlevel10k.zsh-theme

# check if zsh autosuggest exists
if [ ! -d "$HOME/.zsh/zsh-autosuggestions" ]; then
    echo "Installing zsh autosuggestions."
    git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.zsh/zsh-autosuggestions
fi

source $HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# check if zsh syntax highlighting exists
if [ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]; then
    echo "Installing zsh syntax highlighting."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.zsh/zsh-syntax-highlighting
fi

source $HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# check if zsh history susbtring search
if [ ! -d "$HOME/.zsh/zsh-history-substring-search" ]; then
    echo "Installing zsh history substring search."
    git clone https://github.com/zsh-users/zsh-history-substring-search.git $HOME/.zsh/zsh-history-substring-search
fi

source $HOME/.zsh/zsh-history-substring-search/zsh-history-substring-search.zsh

# check if fzf dir navigator exists exists
if [ ! -d "$HOME/.zsh/fzf-dir-navigator" ]; then
    echo "Installing fzf dir navigator."
    git clone https://github.com/KulkarniKaustubh/fzf-dir-navigator.git $HOME/.zsh/fzf-dir-navigator
fi

source $HOME/.zsh/fzf-dir-navigator/fzf-dir-navigator.zsh

# Aliases:
alias ssh="kitty +kitten ssh"
alias ls='ls --color -A --group-directories-first'
alias ll='ls --color -lAthr --group-directories-first'
alias l.='ls -d .* --color --group-directories-first'
alias grep="grep -i --color"

# Source fuzzy
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# TMUX
# SSH straight to the tmux session, if a session does not exist create one
#[ -z "$TMUX"  ] && { tmux attach || exec tmux new-session;}
