# Prompt Material MD3 de la terminal WSL2 de referencia.
# Se carga solo en sesiones Bash interactivas.

__git_ps1_md3() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    [[ $branch == HEAD ]] && branch=$(git rev-parse --short HEAD 2>/dev/null)

    local ahead=0 behind=0
    if git rev-parse --abbrev-ref '@{u}' &>/dev/null; then
        ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
        behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    fi

    local s=''
    git diff --cached --quiet 2>/dev/null || s+=' '
    git diff --quiet          2>/dev/null || s+=' '
    git ls-files --others --exclude-standard 2>/dev/null | grep -q . && s+=' '
    (( ahead  > 0 )) && s+="  ${ahead} "
    (( behind > 0 )) && s+="  ${behind} "

    printf '%s' "${branch}|${s}"
}

__build_ps1() {
    local _x=$?
    local E=$'\e' NP=$'\001' EP=$'\002'

    __a()  { printf '%s' "${NP}${E}[$*m${EP}"; }
    __fg() { printf '%s' "${NP}${E}[38;2;$1;$2;$3m${EP}"; }
    __bg() { printf '%s' "${NP}${E}[48;2;$1;$2;$3m${EP}"; }

    local R=$(__a 0) B=$(__a 1) DIM=$(__a 2)
    local ofg=$(__fg 255 109   0) obg=$(__bg 255 109   0)
    local dfg=$(__fg  43  41  48) dbg=$(__bg  43  41  48)
    local tfg=$(__fg   0 137 123) tbg=$(__bg   0 137 123)
    local ffg=$(__fg  73  69  79) kfg=$(__fg  28  27  31)
    local tertiary_fg=$(__fg 2 188 249) wfg=$(__fg 255 255 255)
    local yfg=$(__fg 255 215  64) gfg=$(__fg 105 240 174)
    local efg=$(__fg 207 102 121)

    local CL='' CR=''   # U+E0B0 / U+E0B2 sharp powerline arrows

    local user=${USER} host=${HOSTNAME%%.*} dir="${PWD/#$HOME/\~}"
    local chroot="${debian_chroot:+($debian_chroot) }"
    local folder='󰉋' clock='󱑂'
    if [[ ${TUNNING_PROFILE:-} == cloudshell || -n ${CLOUD_SHELL:-} ]]; then
        host=CSE
        folder='dir'
        clock='hora'
    fi

    # Orange capsule
    local L="${ofg}${CL}${R}${obg}${kfg}${B}  ${chroot}${user}@${host} ${R}"

    # Dark capsule
    L+="${ofg}${CR}${R} ${dfg}${CL}${R}${dbg}${tertiary_fg}${B} ${folder} ${dir} ${R}"

    # Teal capsule (git, conditional)
    local gi; gi=$(__git_ps1_md3 2>/dev/null) || gi=''
    if [[ -n $gi ]]; then
        local gbr="${gi%%|*}" gst="${gi##*|}"
        L+="${dfg}${CR}${R}${tfg}${CL}${R}${tbg}${wfg}${B}  ${gbr} ${R}"
        [[ -n $gst ]] && L+="${tbg}${yfg}${B}${gst}${R}"
        L+="${tfg}${CR}${R}"
    else
        L+="${dfg}${CR}${R}"
    fi

    # Visible width: strip NP..EP blocks (ANSI sequences) then count chars
    local Lv; Lv=$(printf '%s' "$L" | sed $'s/\001[^\002]*\002//g' | wc -m)

    # Medir también el reloj: los rótulos Cloud Shell no requieren Nerd Font.
    local ts; ts=$(date +%H:%M)
    local RT="${dfg}${CL}${R}${obg}${kfg}${B} ${clock} ${ts} ${R}${ofg}${CR}${R}"
    local Rv; Rv=$(printf '%s' "$RT" | sed $'s/\001[^\002]*\002//g' | wc -m)

    # Fill ─────────────────────────────────────────────────────────────
    local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    local fn=$(( cols - Lv - Rv )); (( fn < 1 )) && fn=1
    local fs; fs=$(printf '─%.0s' $(seq 1 "$fn"))

    # Line 2: ╰ ❯ (green on success, red on error)
    local csym; [[ $_x -eq 0 ]] && csym="${gfg}❯${R}" || csym="${efg}❯${R}"

    local title=''
    case $TERM in
        xterm*|rxvt*) title="${NP}${E}]0;${user}@${host}: ${dir}${E}\\${EP}" ;;
    esac

    # Expandir una variable una sola vez conserva la apariencia y evita ejecutar
    # sustituciones de comandos presentes en nombres de directorios o ramas.
    __tunning_prompt_rendered="${title}${L}${ffg}${fs}${R}${RT}"$'\n'"${ofg}${DIM}╰ ${R}${csym} "
    PS1='${__tunning_prompt_rendered}'
}

PROMPT_COMMAND='__build_ps1'
