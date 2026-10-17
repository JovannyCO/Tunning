#!/usr/bin/env bash
# Instala configuraciones con respaldo; --target-dir permite preparar otro destino.
set -Eeuo pipefail

DIRECTORIO_REPOSITORIO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Conserva los marcadores históricos para reconocer instalaciones anteriores.
MARCADOR_INICIO='# === TUNNING TERMINAL SETUP - MATERIAL MD3 ==='
MARCADOR_FIN='## FIN TUNNING TERMINAL SETUP ##'
directorio_preparacion=''
directorio_respaldo=''
restauracion_habilitada=false
declare -a rutas_destino=() archivos_origen=() permisos=() archivos_modificados=()

detener_con_error() { printf 'Error: %s\n' "$*" >&2; exit 1; }

limpiar_temporales() {
    local codigo_salida=$?
    trap - ERR
    if [[ -n $directorio_preparacion ]]; then rm -rf -- "$directorio_preparacion"; fi
    return "$codigo_salida"
}

escribir_archivo_atomico() {
    local ruta_destino=$1 archivo_origen=$2 permiso=$3 directorio_padre archivo_temporal codigo_salida
    directorio_padre=$(dirname -- "$ruta_destino")
    mkdir -p -- "$directorio_padre" || return
    archivo_temporal=$(mktemp "$directorio_padre/.tunning-XXXXXX") || return
    if cp -- "$archivo_origen" "$archivo_temporal" && chmod "$permiso" "$archivo_temporal" && mv -fT -- "$archivo_temporal" "$ruta_destino"; then
        return 0
    else
        codigo_salida=$?
        rm -f -- "$archivo_temporal"
        return "$codigo_salida"
    fi
}

restaurar_archivos() {
    local indice ruta_destino archivo_respaldado restauracion_fallida=false
    for ((indice=${#archivos_modificados[@]} - 1; indice >= 0; indice--)); do
        ruta_destino=${archivos_modificados[indice]}
        archivo_respaldado="$directorio_respaldo/${ruta_destino#"$directorio_destino"/}"
        if [[ -L $archivo_respaldado ]]; then
            rm -f -- "$ruta_destino" && cp -a --no-dereference -- "$archivo_respaldado" "$ruta_destino" || restauracion_fallida=true
        elif [[ -e $archivo_respaldado ]]; then
            escribir_archivo_atomico "$ruta_destino" "$archivo_respaldado" "$(stat -c '%a' -- "$archivo_respaldado")" || restauracion_fallida=true
        else
            rm -f -- "$ruta_destino" || restauracion_fallida=true
        fi
    done
    if [[ $restauracion_fallida == true ]]; then
        printf 'Error: la restauración está incompleta; revisa el respaldo: %s\n' "$directorio_respaldo" >&2
    else
        printf 'Se restauraron los archivos modificados. Respaldo: %s\n' "$directorio_respaldo" >&2
    fi
}

manejar_error() {
    local codigo_salida=$1
    trap - ERR INT TERM
    set +e
    if [[ $restauracion_habilitada == true ]]; then restaurar_archivos; fi
    printf 'Error: no se completó la instalación (código %s).\n' "$codigo_salida" >&2
    exit "$codigo_salida"
}
trap limpiar_temporales EXIT
trap 'manejar_error "$?"' ERR
trap 'manejar_error 130' INT
trap 'manejar_error 143' TERM

mostrar_ayuda() {
    cat <<'AYUDA'
Uso: bash setup.sh [opciones]
  --profile auto|wsl|ubuntu|cloudshell  Detectar el entorno (predeterminado: auto).
  --prompt bash|starship              Seleccionar el indicador de la terminal.
  --extras                           Activar eza y fastfetch además de Starship.
  --no-extras                        Desactivar extras; requiere el indicador Bash.
  --no-packages                      Solo instalar configuración y comandos.
  --target-dir RUTA                   Preparar un destino alternativo.
  --dry-run                          Mostrar cambios sin escribir el destino.
  -h, --help                         Mostrar esta ayuda.
AYUDA
}

perfil_solicitado=auto
indicador_solicitado=''
extras_solicitados=''
omitir_paquetes=false
simular_instalacion=false
destino_solicitado=''
while (($#)); do
    case $1 in
        -h|--help) mostrar_ayuda; exit 0 ;;
        --profile|--prompt|--target-dir)
            opcion=$1
            (($# >= 2)) && [[ -n $2 && $2 != --* ]] || detener_con_error "$opcion requiere un valor."
            case $opcion in
                --profile) perfil_solicitado=$2 ;;
                --prompt) indicador_solicitado=$2 ;;
                --target-dir) destino_solicitado=$2 ;;
            esac
            shift 2 ;;
        --profile=*) perfil_solicitado=${1#*=}; shift ;;
        --prompt=*) indicador_solicitado=${1#*=}; [[ -n $indicador_solicitado ]] || detener_con_error '--prompt requiere un valor.'; shift ;;
        --target-dir=*) destino_solicitado=${1#*=}; [[ -n $destino_solicitado ]] || detener_con_error '--target-dir requiere un valor.'; shift ;;
        --extras)
            [[ $extras_solicitados != false ]] || detener_con_error '--extras y --no-extras son incompatibles.'
            extras_solicitados=true; shift ;;
        --no-extras)
            [[ $extras_solicitados != true ]] || detener_con_error '--extras y --no-extras son incompatibles.'
            extras_solicitados=false; shift ;;
        --no-packages) omitir_paquetes=true; shift ;;
        --dry-run) simular_instalacion=true; shift ;;
        *) detener_con_error "Opción desconocida: $1. Usa --help." ;;
    esac
done
case $perfil_solicitado in auto|wsl|ubuntu|cloudshell) ;; *) detener_con_error "--profile: valor inválido: $perfil_solicitado." ;; esac
case $indicador_solicitado in ''|bash|starship) ;; *) detener_con_error "--prompt: valor inválido: $indicador_solicitado." ;; esac

for herramienta_necesaria in git realpath mktemp cp mv chmod mkdir cmp cat stat rm date dirname uname; do
    command -v "$herramienta_necesaria" >/dev/null || detener_con_error "Se requiere el comando $herramienta_necesaria."
done

detectar_perfil() {
    local archivo_version_sistema=/etc/os-release linea distribucion_sistema='' version_distribucion='' valor version_nucleo
    if [[ -n ${CLOUD_SHELL:-} || -e /google/devshell/bashrc.google ]]; then
        perfil_detectado=cloudshell
        return
    fi
    [[ -r $archivo_version_sistema ]] || archivo_version_sistema=/usr/lib/os-release
    [[ -r $archivo_version_sistema ]] || detener_con_error 'No se pudo identificar el sistema operativo.'
    while IFS= read -r linea || [[ -n $linea ]]; do
        case $linea in
            ID=*|VERSION_ID=*)
                valor=${linea#*=}
                if [[ $valor == \"*\" || $valor == \'*\' ]]; then valor=${valor:1:${#valor}-2}; fi
                case $linea in ID=*) distribucion_sistema=$valor ;; VERSION_ID=*) version_distribucion=$valor ;; esac ;;
        esac
    done < "$archivo_version_sistema"
    [[ $distribucion_sistema == ubuntu && $version_distribucion == 26.04 ]] || detener_con_error 'Este instalador requiere Ubuntu 26.04 o Google Cloud Shell.'
    version_nucleo=$(uname -r)
    perfil_detectado=ubuntu
    if [[ ${version_nucleo,,} == *microsoft* ]]; then perfil_detectado=wsl; fi
}

# Analiza palabras literales sin evaluar variables, sustituciones ni comandos.
leer_palabras_literales() {
    local texto=$1 indice caracter siguiente_caracter palabra='' comilla='' palabra_iniciada=false
    palabras=()
    for ((indice=0; indice<${#texto}; indice++)); do
        caracter=${texto:indice:1}
        if [[ $comilla == "'" ]]; then
            if [[ $caracter == "'" ]]; then comilla=''; else palabra+=$caracter; fi
        elif [[ $caracter == \\ ]]; then
            ((indice + 1 < ${#texto})) || return 1
            ((indice+=1))
            siguiente_caracter=${texto:indice:1}
            if [[ $comilla == '"' && $siguiente_caracter != '$' && $siguiente_caracter != '`' && $siguiente_caracter != '"' && $siguiente_caracter != \\ ]]; then palabra+='\'; fi
            palabra+=$siguiente_caracter
            palabra_iniciada=true
        elif [[ $comilla == '"' ]]; then
            if [[ $caracter == '"' ]]; then comilla=''; else palabra+=$caracter; fi
        elif [[ $caracter == "'" || $caracter == '"' ]]; then
            comilla=$caracter
            palabra_iniciada=true
        elif [[ $caracter == '#' ]]; then
            break
        elif [[ $caracter == ' ' || $caracter == $'\t' || $caracter == $'\r' ]]; then
            if [[ $palabra_iniciada == true ]]; then palabras+=("$palabra"); palabra=''; palabra_iniciada=false; fi
        else
            palabra+=$caracter
            palabra_iniciada=true
        fi
    done
    [[ -z $comilla ]] || return 1
    if [[ $palabra_iniciada == true ]]; then palabras+=("$palabra"); fi
}

declare -A preferencias_guardadas=()
declare -a palabras=()
leer_preferencias_guardadas() {
    local ruta_archivo=$1 numero_linea=0 linea clave valor
    [[ -e $ruta_archivo ]] || return 0
    [[ -f $ruta_archivo && -r $ruta_archivo ]] || detener_con_error "No se puede leer el archivo de preferencias: $ruta_archivo."
    while IFS= read -r linea || [[ -n $linea ]]; do
        ((numero_linea+=1))
        leer_palabras_literales "$linea" || detener_con_error "$ruta_archivo:$numero_linea: comillas o escape sin cierre."
        ((${#palabras[@]})) || continue
        if [[ ${palabras[0]} == export ]]; then palabras=("${palabras[@]:1}"); fi
        ((${#palabras[@]} == 1)) && [[ ${palabras[0]} == *=* ]] || detener_con_error "$ruta_archivo:$numero_linea: se esperaba una preferencia literal."
        clave=${palabras[0]%%=*}
        valor=${palabras[0]#*=}
        case "$clave=$valor" in
            TUNNING_PROFILE=wsl|TUNNING_PROFILE=ubuntu|TUNNING_PROFILE=cloudshell|TUNNING_PROMPT=bash|TUNNING_PROMPT=starship|TUNNING_EXTRAS=true|TUNNING_EXTRAS=false) ;;
            *) detener_con_error "$ruta_archivo:$numero_linea: preferencia desconocida o inválida." ;;
        esac
        [[ ! -v preferencias_guardadas[$clave] ]] || detener_con_error "$ruta_archivo:$numero_linea: preferencia repetida."
        preferencias_guardadas[$clave]=$valor
    done < "$ruta_archivo"
}

proteger_literal_bash() {
    local valor=$1
    if [[ $valor =~ ^[a-zA-Z0-9_/@%+=:,.-]+$ ]]; then
        printf '%s' "$valor"
    else
        valor=${valor//\'/\'\\\'\'}
        printf "'%s'" "$valor"
    fi
}

preparar_archivo_bashrc() {
    local ruta_archivo=$1 linea linea_sin_espacios dentro_del_bloque=false contenido_ajeno='' arranque_anterior
    arranque_anterior='command -v devup &>/dev/null && [[ $- == *i* ]] && devup --boot'
    : > "$directorio_preparacion/bashrc-contenido_ajeno"
    if [[ -e $ruta_archivo ]]; then
        [[ -f $ruta_archivo && -r $ruta_archivo ]] || detener_con_error "No se puede leer el archivo de Bash: $ruta_archivo."
        while IFS= read -r linea || [[ -n $linea ]]; do
            linea_sin_espacios=${linea#"${linea%%[![:space:]]*}"}
            linea_sin_espacios=${linea_sin_espacios%"${linea_sin_espacios##*[![:space:]]}"}
            if [[ $linea_sin_espacios == "$MARCADOR_INICIO" ]]; then
                [[ $dentro_del_bloque == false ]] || detener_con_error '.bashrc contiene bloques de Terminal Tuning anidados; corrige los marcadores.'
                dentro_del_bloque=true
            elif [[ $linea_sin_espacios == "$MARCADOR_FIN" ]]; then
                [[ $dentro_del_bloque == true ]] || detener_con_error '.bashrc contiene un cierre de Terminal Tuning sin apertura.'
                dentro_del_bloque=false
            elif [[ $dentro_del_bloque == false && $linea_sin_espacios != "$arranque_anterior" ]]; then
                if [[ $perfil == cloudshell && ( $linea_sin_espacios == 'source /google/devshell/bashrc.google' || $linea_sin_espacios == '. /google/devshell/bashrc.google' ) ]]; then continue; fi
                printf '%s\n' "$linea" >> "$directorio_preparacion/bashrc-contenido_ajeno"
            fi
        done < "$ruta_archivo"
    fi
    [[ $dentro_del_bloque == false ]] || detener_con_error '.bashrc contiene un bloque de Terminal Tuning sin cierre; no se ha modificado.'
    contenido_ajeno=$(cat -- "$directorio_preparacion/bashrc-contenido_ajeno")
    {
        printf '%s\n\n%s\n' "$contenido_ajeno" "$MARCADOR_INICIO"
        if [[ $perfil == cloudshell ]]; then printf '%s\n' '[ ! -r /google/devshell/bashrc.google ] || . /google/devshell/bashrc.google'; fi
        printf '. %s\n%s\n' "$(proteger_literal_bash "$directorio_configuracion/bashrc_append.sh")" "$MARCADOR_FIN"
    } > "$directorio_preparacion/bashrc"
}

preparar_configuracion_git() {
    local ruta_archivo=$1 nombre_alias comando_alias codigo_salida valor
    if [[ -e $ruta_archivo ]]; then cp -- "$ruta_archivo" "$directorio_preparacion/gitconfig"; else : > "$directorio_preparacion/gitconfig"; fi
    comando_alias="!$(proteger_literal_bash "$directorio_destino/.local/bin/git-sync")"
    for nombre_alias in sync syncPR syncPRmerge; do
        if ! git config --file "$directorio_preparacion/gitconfig" "alias.$nombre_alias" "$comando_alias --tunning-mode=$nombre_alias"; then
            detener_con_error 'La configuración Git no es válida; no se ha modificado el destino.'
        fi
    done
    if git config --file "$directorio_preparacion/gitconfig" --get tunning.syncSign >/dev/null; then
        :
    else
        codigo_salida=$?
        [[ $codigo_salida == 1 ]] || detener_con_error 'No se pudo leer la configuración Git existente.'
        if [[ $perfil == cloudshell ]]; then valor=false; else valor=true; fi
        git config --file "$directorio_preparacion/gitconfig" tunning.syncSign "$valor"
    fi
}

agregar_archivo_al_plan() {
    local archivo_origen=$2 permiso=$3 ruta_destino="$directorio_destino/$1"
    [[ -f $archivo_origen && -r $archivo_origen ]] || detener_con_error "No se puede leer el archivo fuente: $archivo_origen."
    if [[ -L $ruta_destino || ! -e $ruta_destino ]] || ! cmp -s -- "$archivo_origen" "$ruta_destino" || [[ $(stat -c '%a' -- "$ruta_destino") != "$permiso" ]]; then
        rutas_destino+=("$ruta_destino")
        archivos_origen+=("$archivo_origen")
        permisos+=("$permiso")
    fi
}

aplicar_cambios() {
    local indice ruta_destino ruta_relativa existia separador=''
    directorio_respaldo="$directorio_destino/.local/state/tunning/backups/$(date '+%Y%m%d-%H%M%S-%N')-$$"
    mkdir -m 700 -p -- "$directorio_respaldo"
    printf '[\n' > "$directorio_respaldo/manifest.json"
    for ruta_destino in "${rutas_destino[@]}"; do
        ruta_relativa=${ruta_destino#"$directorio_destino"/}
        existia=false
        if [[ -e $ruta_destino || -L $ruta_destino ]]; then
            existia=true
            mkdir -p -- "$(dirname -- "$directorio_respaldo/$ruta_relativa")"
            cp -a --no-dereference -- "$ruta_destino" "$directorio_respaldo/$ruta_relativa"
        fi
        # Las rutas relativas del plan son constantes del instalador.
        printf '%s  {"path": "%s", "existed": %s}' "$separador" "$ruta_relativa" "$existia" >> "$directorio_respaldo/manifest.json"
        separador=$',\n'
    done
    printf '\n]\n' >> "$directorio_respaldo/manifest.json"
    restauracion_habilitada=true
    for ((indice=0; indice<${#rutas_destino[@]}; indice++)); do
        escribir_archivo_atomico "${rutas_destino[indice]}" "${archivos_origen[indice]}" "${permisos[indice]}"
        archivos_modificados+=("${rutas_destino[indice]}")
    done
    restauracion_habilitada=false
    printf 'Respaldo: %s\n' "$directorio_respaldo"
}

detectar_perfil
perfil=$perfil_solicitado
if [[ $perfil == auto ]]; then perfil=$perfil_detectado; fi
if [[ $perfil != "$perfil_detectado" && ( -z $destino_solicitado || $omitir_paquetes != true ) ]]; then
    detener_con_error "Perfil solicitado: $perfil; entorno detectado: $perfil_detectado."
fi
if [[ $destino_solicitado == '~' ]]; then destino_solicitado=$HOME;
elif [[ $destino_solicitado == '~/'* ]]; then destino_solicitado="$HOME/${destino_solicitado:2}"; fi
directorio_destino=$(realpath -ms -- "${destino_solicitado:-$HOME}")
directorio_configuracion="$directorio_destino/.config/tunning"
leer_preferencias_guardadas "$directorio_configuracion/settings.sh"
indicador_terminal=${indicador_solicitado:-${preferencias_guardadas[TUNNING_PROMPT]:-}}
if [[ -z $indicador_terminal ]]; then
    if [[ $perfil == cloudshell ]]; then indicador_terminal=starship; else indicador_terminal=bash; fi
fi
if [[ $indicador_terminal == starship && $extras_solicitados == false ]]; then
    detener_con_error 'Starship requiere extras. Para desactivarlos usa --prompt bash --no-extras.'
fi
activar_extras=${extras_solicitados:-${preferencias_guardadas[TUNNING_EXTRAS]:-false}}
if [[ $indicador_terminal == starship ]]; then activar_extras=true; fi
if [[ $perfil == cloudshell && $activar_extras == true && -n $destino_solicitado && $omitir_paquetes != true ]]; then
    detener_con_error 'Para preparar otro destino Cloud Shell usa --no-packages.'
fi
directorio_preparacion=$(mktemp -d /tmp/tunning-install.XXXXXX)
preparar_archivo_bashrc "$directorio_destino/.bashrc"
preparar_configuracion_git "$directorio_destino/.gitconfig"
printf 'export TUNNING_PROFILE=%s\nexport TUNNING_PROMPT=%s\nexport TUNNING_EXTRAS=%s\n' "$perfil" "$indicador_terminal" "$activar_extras" > "$directorio_preparacion/settings.sh"
agregar_archivo_al_plan '.config/tunning/settings.sh' "$directorio_preparacion/settings.sh" 644
for ruta_archivo in bashrc_append.sh prompt-bash.sh; do
    agregar_archivo_al_plan ".config/tunning/$ruta_archivo" "$DIRECTORIO_REPOSITORIO/configs/$ruta_archivo" 644
done
for comando_instalable in 'devup.sh:devup' 'git-sync.sh:git-sync' 'git-pr.sh:git-pr.sh' 'git-json.sh:git-json.sh'; do
    agregar_archivo_al_plan ".local/bin/${comando_instalable#*:}" "$DIRECTORIO_REPOSITORIO/scripts/${comando_instalable%%:*}" 755
done
if [[ $activar_extras == true ]]; then
    variante=''
    if [[ $perfil == cloudshell ]]; then variante=-cloudshell; fi
    agregar_archivo_al_plan '.config/starship.toml' "$DIRECTORIO_REPOSITORIO/configs/starship$variante.toml" 644
    agregar_archivo_al_plan '.config/fastfetch/config.jsonc' "$DIRECTORIO_REPOSITORIO/configs/fastfetch$variante.jsonc" 644
fi
# Activar los puntos de entrada cuando sus archivos de destino ya existen.
agregar_archivo_al_plan '.gitconfig' "$directorio_preparacion/gitconfig" 600
agregar_archivo_al_plan '.bashrc' "$directorio_preparacion/bashrc" 644
printf 'Entorno: %s; indicador: %s; extras: %s; destino: %s\n' "$perfil" "$indicador_terminal" "$activar_extras" "$directorio_destino"
for ruta_destino in "${rutas_destino[@]}"; do printf '  Actualizar: %s\n' "$ruta_destino"; done
if [[ $omitir_paquetes != true ]]; then
    printf 'Paquetes: git, curl, ca-certificates, bash-completion, util-linux, gnupg'
    if [[ $activar_extras == true ]]; then printf ' y herramientas opcionales'; fi
    printf '\n'
fi
if [[ $simular_instalacion == true ]]; then exit 0; fi
if [[ $omitir_paquetes != true ]]; then
    sudo apt-get update
    sudo apt-get install -y git curl ca-certificates bash-completion util-linux gnupg
    if [[ $activar_extras == true ]]; then
        if [[ $perfil == cloudshell ]]; then bash "$DIRECTORIO_REPOSITORIO/scripts/install-cloudshell-extras.sh";
        else sudo apt-get install -y starship eza fastfetch; fi
    elif [[ $perfil == cloudshell ]]; then bash "$DIRECTORIO_REPOSITORIO/scripts/install-cloudshell-extras.sh" --gh-only
    fi
fi
if ((${#rutas_destino[@]})); then aplicar_cambios;
else printf 'La configuración ya está actualizada.\n'; fi
printf 'Configuración completa. Abre una terminal nueva o ejecuta: source ~/.bashrc\n'
if [[ $perfil == wsl ]]; then printf 'Windows Terminal: importa el esquema y el perfil de configs/; consulta README.md.\n'; fi
