#!/usr/bin/env bash
# devup — actualiza el entorno de desarrollo (dev environment):
#         paquetes del sistema (apt), firebase-tools, codex y claude
#
# Uso:
#   devup            Pregunta qué actualizar
#   devup -y         Actualiza todo sin preguntar (yes)
#   devup -l         Ligero (light): solo las interfaces de línea de comandos
#                    (CLI, Command Line Interface), sin apt; útil con datos móviles
#   devup --boot     Pregunta solo una vez por arranque (boot) de la máquina (lo usa ~/.bashrc)

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

set -uo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/devup"
LAST_FILE="$STATE_DIR/last-update"
TIMEOUT=15

online() { timeout 3 bash -c '</dev/tcp/1.1.1.1/443' 2>/dev/null; }

last_update() {
    [[ -f "$LAST_FILE" ]] || { echo "nunca (never)"; return; }
    local days=$(( ( $(date +%s) - $(stat -c %Y "$LAST_FILE") ) / 86400 ))
    case $days in 0) echo "hoy (today)" ;; 1) echo "ayer (yesterday)" ;; *) echo "hace $days días ($days days ago)" ;; esac
}

FAILED=()
step() {  # step "Nombre" comando args...
    local name=$1; shift
    if ! command -v "$1" &>/dev/null; then
        echo -e "${DIM}[-] $name: '$1' no instalado (not installed), omitido (skipped)${NC}"; return
    fi
    echo -e "\n${YELLOW}==> $name${NC}"
    "$@" || { FAILED+=("$name"); echo -e "${RED}[✗] $name falló (failed)${NC}"; }
}

run_updates() {  # $1 = full | light
    mkdir -p "$STATE_DIR" || return 1
    exec 9>"$STATE_DIR/update.lock" || return 1
    flock -n 9 || { echo 'devup: ya hay una actualización en curso.'; return 1; }
    FAILED=()
    if [[ $1 == full ]]; then
        step "Paquetes del sistema (apt, Advanced Package Tool)" bash -c 'sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'
    fi
    step "Herramientas de Firebase (firebase-tools, vía npm: Node Package Manager)" npm install -g firebase-tools@latest
    step "Codex (CLI, Command Line Interface)" codex update
    step "Claude Code (CLI, Command Line Interface)" claude update

    echo
    if (( ${#FAILED[@]} )); then
        echo -e "${RED}[✗] Fallaron (failed): ${FAILED[*]}${NC}"
        return 1
    fi
    [[ $1 == full ]] && touch "$LAST_FILE"
    echo -e "${GREEN}[✓] Entorno actualizado (up to date)${NC}"
}

ask() {
    [[ -t 0 ]] || { echo "devup: usa -y o -l para actualizar sin interacción."; return 0; }
    echo -e "${CYAN}󰚰 Actualizar entorno (update)${NC} ${DIM}· última completa (last full update): $(last_update)${NC}"
    echo -e "   ${GREEN}[s]${NC} todo (all)   ${GREEN}[l]${NC} ligero (light), sin apt   ${GREEN}[N]${NC} no\n   ${DIM}Tiempo de espera (timeout): ${TIMEOUT} s, luego toma 'no'${NC}"
    local r=''
    read -r -n 1 -t "$TIMEOUT" -p "   > " r; echo
    case ${r,,} in
        s|y) run_updates full ;;
        l)   run_updates light ;;
        *)   echo -e "${DIM}Omitido (skipped). Ejecuta 'devup' cuando quieras.${NC}" ;;
    esac
}

case ${1:-} in
    -y|--yes)   run_updates full ;;
    -l|--light) run_updates light ;;
    --boot)
        # Solo en terminales interactivas y una vez por arranque (el boot_id cambia al reiniciar WSL/la máquina).
        [[ -t 0 ]] || exit 0
        mkdir -p "$STATE_DIR" || exit 1
        stamp="$STATE_DIR/boot-$(cat /proc/sys/kernel/random/boot_id)"
        [[ -e "$stamp" ]] && exit 0
        online || { echo -e "${DIM}󰚰 devup: sin conexión (offline), se preguntará en la próxima terminal${NC}"; exit 0; }
        # Creación atómica: si abres varias terminales a la vez, solo una pregunta.
        ( set -C; : > "$stamp" ) 2>/dev/null || exit 0
        find "$STATE_DIR" -name 'boot-*' ! -newer "$stamp" ! -path "$stamp" -delete 2>/dev/null
        ask
        ;;
    -h|--help)  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
    '')         ask ;;
    *)          echo "devup: opción desconocida: $1" >&2; exit 2 ;;
esac
