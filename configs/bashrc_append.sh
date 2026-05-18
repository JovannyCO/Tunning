# ── Historia ────────────────────────────────────────────────────────────
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%F %T  "
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
shopt -s cdspell

# ── Completado ──────────────────────────────────────────────────────────
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# ── Colores ─────────────────────────────────────────────────────────────
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

export GREP_COLORS='ms=01;38;5;214:mc=01;38;5;214:sl=:cx=:fn=38;5;39:ln=38;5;82:bn=38;5;82:se=38;5;245'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# ── Paginador con colores ────────────────────────────────────────────────
export LESS='-R --use-color -Dd+r$Du+b'
export MANPAGER="less -R --use-color -Dd+r -Du+b"

# ── Aliases: navegación ──────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# ── Aliases: listado de archivos (eza) ───────────────────────────────────
if command -v eza &>/dev/null; then
    alias ls='eza --icons=always --group-directories-first --color=always'
    alias ll='eza -la --icons=always --group-directories-first --color=always --git --header'
    alias la='eza -a --icons=always --group-directories-first --color=always'
    alias lt='eza -T --icons=always --color=always --level=3'
    alias l='eza -1 --icons=always --color=always'
    alias lg='eza -la --icons=always --git --git-ignore --color=always'
else
    alias ls='ls --color=auto'
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
fi

# ── Aliases: git ─────────────────────────────────────────────────────────
alias g='git'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --color'
alias gd='git diff --color'
alias gco='git checkout'
alias gb='git branch -a'

# ── Aliases: utilidades ──────────────────────────────────────────────────
alias cls='clear'
alias h='history | grep'
alias ports='ss -tulnp'
alias myip='curl -s https://api.ipify.org && echo'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias top='htop 2>/dev/null || top'

# ── Aliases: editores ────────────────────────────────────────────────────
alias v='vim'
alias c='code .'

# ── Funciones útiles ─────────────────────────────────────────────────────
mkcd() { mkdir -p "$1" && cd "$1"; }
extract() {
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;;
        *.tar.gz)  tar xzf "$1" ;;
        *.tar.xz)  tar xJf "$1" ;;
        *.zip)     unzip "$1" ;;
        *.gz)      gunzip "$1" ;;
        *.7z)      7z x "$1" ;;
        *) echo "No sé cómo extraer '$1'" ;;
    esac
}

# ── Variables de entorno ─────────────────────────────────────────────────
export EDITOR='vim'
export VISUAL='vim'
export LANG='C.UTF-8'
export LC_ALL='C.UTF-8'
export COLORTERM=truecolor
export TERM=xterm-256color

# ── NVM ──────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ── PATH ─────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ── Bienvenida (fastfetch al abrir terminal) ─────────────────────────────
if command -v fastfetch &>/dev/null && [[ $- == *i* ]] && [[ -z "$FASTFETCH_SHOWN" ]]; then
    export FASTFETCH_SHOWN=1
    fastfetch
fi

# ── Starship prompt ───────────────────────────────────────────────────────
eval "$(starship init bash)"
