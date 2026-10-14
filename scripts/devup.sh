#!/usr/bin/env bash
# devup — actualiza el entorno de desarrollo:
#         paquetes del sistema (apt), firebase-tools, codex y claude
#
# Uso:
#   devup            Pregunta qué actualizar
#   devup -y         Actualiza todo sin preguntar
#   devup -l         Ligero: solo las herramientas de línea de comandos,
#                    sin apt; útil con datos móviles
#   devup --boot     Pregunta una vez por arranque de la máquina (lo usa ~/.bashrc)

CIAN='\033[0;36m'; VERDE='\033[0;32m'; AMARILLO='\033[1;33m'; ROJO='\033[0;31m'; TENUE='\033[2m'; RESTABLECER_COLOR='\033[0m'

set -uo pipefail

DIRECTORIO_ESTADO="${XDG_CACHE_HOME:-$HOME/.cache}/devup"
ARCHIVO_ULTIMA_ACTUALIZACION="$DIRECTORIO_ESTADO/last-update"
TIEMPO_ESPERA=15

hay_conexion() { timeout 3 bash -c '</dev/tcp/1.1.1.1/443' 2>/dev/null; }

ultima_actualizacion() {
    [[ -f "$ARCHIVO_ULTIMA_ACTUALIZACION" ]] || { echo 'nunca'; return; }
    local dias=$(( ( $(date +%s) - $(stat -c %Y "$ARCHIVO_ULTIMA_ACTUALIZACION") ) / 86400 ))
    case $dias in 0) echo 'hoy' ;; 1) echo 'ayer' ;; *) echo "hace $dias días" ;; esac
}

FALLAS=()
ejecutar_paso() {  # ejecutar_paso "Nombre" comando args...
    local nombre=$1; shift
    if ! command -v "$1" &>/dev/null; then
        echo -e "${TENUE}[-] $nombre: '$1' no está instalado; se omite.${RESTABLECER_COLOR}"; return
    fi
    echo -e "\n${AMARILLO}==> $nombre${RESTABLECER_COLOR}"
    "$@" || { FALLAS+=("$nombre"); echo -e "${ROJO}[✗] $nombre falló${RESTABLECER_COLOR}"; }
}

actualizar_herramientas() {  # $1 = full | light
    mkdir -p "$DIRECTORIO_ESTADO" || return 1
    exec 9>"$DIRECTORIO_ESTADO/update.lock" || return 1
    flock -n 9 || { echo 'devup: ya hay una actualización en curso.'; return 1; }
    FALLAS=()
    if [[ $1 == full ]]; then
        ejecutar_paso 'Paquetes del sistema mediante apt' bash -c 'sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'
    fi
    ejecutar_paso 'Herramientas de Firebase mediante npm' npm install -g firebase-tools@latest
    ejecutar_paso 'Codex' codex update
    ejecutar_paso 'Claude Code' claude update

    echo
    if (( ${#FALLAS[@]} )); then
        echo -e "${ROJO}[✗] Fallaron: ${FALLAS[*]}${RESTABLECER_COLOR}"
        return 1
    fi
    [[ $1 == full ]] && touch "$ARCHIVO_ULTIMA_ACTUALIZACION"
    echo -e "${VERDE}[✓] Entorno actualizado${RESTABLECER_COLOR}"
}

preguntar_actualizacion() {
    [[ -t 0 ]] || { echo "devup: usa -y o -l para actualizar sin interacción."; return 0; }
    echo -e "${CIAN}󰚰 Actualizar entorno${RESTABLECER_COLOR} ${TENUE}· última actualización completa: $(ultima_actualizacion)${RESTABLECER_COLOR}"
    echo -e "   ${VERDE}[s]${RESTABLECER_COLOR} todo   ${VERDE}[l]${RESTABLECER_COLOR} ligero, sin apt   ${VERDE}[N]${RESTABLECER_COLOR} no\n   ${TENUE}Tiempo de espera: ${TIEMPO_ESPERA} s, luego toma 'no'${RESTABLECER_COLOR}"
    local respuesta=''
    read -r -n 1 -t "$TIEMPO_ESPERA" -p "   > " respuesta; echo
    case ${respuesta,,} in
        s|y) actualizar_herramientas full ;;
        l)   actualizar_herramientas light ;;
        *)   echo -e "${TENUE}Omitido. Ejecuta 'devup' cuando quieras.${RESTABLECER_COLOR}" ;;
    esac
}

case ${1:-} in
    -y|--yes)   actualizar_herramientas full ;;
    -l|--light) actualizar_herramientas light ;;
    --boot)
        # Solo en terminales interactivas y una vez por arranque (el boot_id cambia al reiniciar WSL/la máquina).
        [[ -t 0 ]] || exit 0
        mkdir -p "$DIRECTORIO_ESTADO" || exit 1
        marca="$DIRECTORIO_ESTADO/boot-$(cat /proc/sys/kernel/random/boot_id)"
        [[ -e "$marca" ]] && exit 0
        hay_conexion || { echo -e "${TENUE}󰚰 devup: sin conexión; se preguntará en la próxima terminal${RESTABLECER_COLOR}"; exit 0; }
        # Creación atómica: si abres varias terminales a la vez, solo una pregunta.
        ( set -C; : > "$marca" ) 2>/dev/null || exit 0
        find "$DIRECTORIO_ESTADO" -name 'boot-*' ! -newer "$marca" ! -path "$marca" -delete 2>/dev/null
        preguntar_actualizacion
        ;;
    -h|--help)  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
    '')         preguntar_actualizacion ;;
    *)          echo "devup: opción desconocida: $1" >&2; exit 2 ;;
esac
