#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

. "$HOME/.atuin/bin/env"
. /usr/share/z/z.sh

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"
eval "$(starship init bash)"
export PATH=$PATH:/home/zen/niribin

alias gpartes='xhost +SI:localuser:root && sudo -E env GTK_THEME=Adwaita gparted'
alias gpartex='sudo -E env GTK_THEME=Adwaita gparted'

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --bash)"

# File system
if command -v eza &> /dev/null; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

alias ff="fzf --preview 'bat --style=numbers --color=always {}'"

if command -v zoxide &> /dev/null; then
  alias cd="zd"
  zd() {
    if [ $# -eq 0 ]; then
      builtin cd ~ && return
    elif [ -d "$1" ]; then
      builtin cd "$1"
    else
      z "$@" && printf "\U000F17A9 " && pwd || echo "Error: Directory not found"
    fi
  }
fi
alias dotfiles='/usr/bin/git --git-dir=/home/zen/.dotfiles/ --work-tree=/home/zen'
