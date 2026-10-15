# ── PATH ─────────────────────────────────────────────────────────────────
# Debe ir primero: starship/eza/fastfetch viven en ~/.local/bin, y los
# bloques de abajo (alias de eza, etc.) hacen `command -v` sobre ellos.
# Si esto se exporta después (como antes, junto a "Starship prompt"),
# `command -v eza` falla en una shell nueva y el alias cae al `ls` plano.
[[ $- == *i* ]] || return 0
DIRECTORIO_CONFIG_TUNNING="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f $DIRECTORIO_CONFIG_TUNNING/settings.sh ]]; then
    . "$DIRECTORIO_CONFIG_TUNNING/settings.sh"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# ── Historia ────────────────────────────────────────────────────────────
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
HISTTIMEFORMAT="%F %T  "
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar
shopt -s cdspell
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind 'TAB: menu-complete'
bind '"\e[Z": menu-complete-backward'

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
# Cloud Shell no puede pintar íconos Nerd Font: el selector de fuente del
# panel de terminal es una lista fija sin fuentes personalizadas (se
# verificó con el usuario), así que con --icons=always todo se ve con
# rectángulos. Se detecta el entorno (var oficial de Cloud Shell) y se
# desactivan los íconos solo ahí; WSL2 conserva los íconos normales.
if [[ ${TUNNING_PROFILE:-} == cloudshell || -n ${CLOUD_SHELL:-} ]]; then
    ICONOS_EZA='never'
else
    ICONOS_EZA='always'
fi

if [[ ${TUNNING_EXTRAS:-false} == true ]] && command -v eza &>/dev/null; then
    alias ls="eza --icons=$ICONOS_EZA --group-directories-first --color=always"
    alias ll="eza -la --icons=$ICONOS_EZA --group-directories-first --color=always --git --header"
    alias la="eza -a --icons=$ICONOS_EZA --group-directories-first --color=always"
    alias lt="eza -T --icons=$ICONOS_EZA --color=always --level=3"
    alias l="eza -1 --icons=$ICONOS_EZA --color=always"
    alias lg="eza -la --icons=$ICONOS_EZA --git --git-ignore --color=always"
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
crear_y_entrar() { mkdir -p "$1" && cd "$1"; }
extraer() {
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

# Cloud Shell conserva la preferencia Colombia; Ubuntu/WSL conserva su zona.
if [[ ${TUNNING_PROFILE:-} == cloudshell || -n ${CLOUD_SHELL:-} ]]; then
    export TZ="${TZ:-America/Bogota}"
fi

# ── NVM ──────────────────────────────────────────────────────────────────
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if ! declare -F nvm >/dev/null; then
    [ ! -s "$NVM_DIR/nvm.sh" ] || \. "$NVM_DIR/nvm.sh"
    [ ! -s "$NVM_DIR/bash_completion" ] || \. "$NVM_DIR/bash_completion"
fi

# Firma de commits desde terminales interactivas.
if [[ -t 0 ]]; then
    GPG_TTY=$(tty)
    export GPG_TTY
fi

# El fallo de una actualización no interrumpe la carga del prompt.
if [[ ${TUNNING_DEVUP_BOOT:-1} != 0 ]] && command -v devup &>/dev/null; then
    devup --boot || true
fi

# ── Bienvenida (fastfetch al abrir terminal) ─────────────────────────────
if [[ ${TUNNING_EXTRAS:-false} == true ]] && command -v fastfetch &>/dev/null && [[ -z ${FASTFETCH_MOSTRADO:-} ]]; then
    export FASTFETCH_MOSTRADO=1
    fastfetch
fi

# ── Starship prompt ───────────────────────────────────────────────────────
if [[ ${TUNNING_PROMPT:-bash} == starship ]] && command -v starship &>/dev/null; then
    eval "$(starship init bash)"
else
    . "$DIRECTORIO_CONFIG_TUNNING/prompt-bash.sh"
fi
