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
export PS1="\033[36m\u\033[35m @ \033[36m\h\033[35m [ \033[32m\w \033[35m]\033[32m \$? \033[37m  \n$ "

# Bash Completion
[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] && \
    . /usr/share/bash-completion/bash_completion

# Aliases
alias ssh="kitty +kitten ssh"
alias ls="ls --color -A --group-directories-first"
alias ll="ls --color -lAthr --group-directories-first"
alias l.="ls -d .* --color --group-directories-first"
alias grep="grep --color"
alias vim="/usr/bin/nvim"
alias c..="cd ../.."
alias untar="tar -zxvf"
alias nao="sudo reboot now"
alias snao="sudo shutdown -h now"

# Fuzzy
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
