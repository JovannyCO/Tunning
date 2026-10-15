#!/usr/bin/env bash
# Implementación Bash de los alias Git; el instalador conserva este archivo y su módulo PR.
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    printf '%s\n' 'git sync necesita Bash 4.4 o posterior.' >&2
    exit 1
fi
shopt -s inherit_errexit

AYUDA='Uso: git sync ["mensaje"]
     git syncPR ["mensaje"] [--issue N]
     git syncPRmerge ["mensaje"] [--issue N]
Los alias usan Bash y Git. sync publica; syncPR prepara PR;
syncPRmerge exige evidencia vigente y auditoría independiente para fusionar.
Valida e inicializa submódulos recursivos en sus commits registrados.
Exceptúa .brand y repositorios __*: solo registra el SHA elegido, sin modificarlos.
De hijos a padres: agrega cambios, crea commits, integra mediante merge la rama
remota y production (si existe), y publica únicamente cada rama de trabajo.
HEAD separado necesita submodule.<nombre>.branch; branch=. usa la rama padre.
Se respetan firmas, remotos, ramas activas y configuración por repositorio.
Los modos PR necesitan gh autenticado en github.com y una rama distinta de la
base (tunning.prBase o rama predeterminada real). No crean ramas arbitrarias.
Política/auditorías externas: tunning.prPolicy y tunning.auditReport.
Comprobaciones: tunning.testCommands (JSON de arrays de argumentos) o
bash scripts/verify.sh cuando existe. Un fallo bloquea el push y sus padres.
Ver docs/GIT-PR.md para evidencia, firmas, comprobaciones y reanudación.'
MODO=sync
if [[ ${1-} == --tunning-mode=* ]]; then MODO=${1#*=}; shift; fi
if [[ ${1-} == --help || ${1-} == -h ]]; then printf '%s\n' "$AYUDA"; exit 0; fi
RAIZ= MENSAJE= OPCIONES='{}' TEMPORALES= ESTADO_GIT=0
PID_SINCRONIZACION=$BASHPID
CONTADOR_CAPTURAS=0
# Las claves son rutas absolutas. Los valores estructurados usan el módulo JSON Bash.
declare -a REPOSITORIOS=()
declare -Ag RAMA=() CABEZA_SEPARADA=() FIRMA=() INTEGRAR_PRODUCCION=() REMOTO=()
declare -Ag REMOTO_PUBLICACION=() REFERENCIA_REMOTA=() URL_PUBLICACION=() CABEZAS_REMOTAS=()
declare -Ag PUNTA_RAMA=() CONFIGURACION_MODULOS=() HIJOS=() CONFIRMACIONES_CREADAS=()
declare -Ag MODULOS_LECTURA=()
declare -Ag RESULTADOS_COMPROBACIONES=() PUBLICADOS=() SOLICITUDES_CAMBIO=() FUSIONADOS=()
declare -Ag BASE=() SHA_BASE=() BASE_PREDETERMINADA=() METADATOS=()
declare -Ag RESPONSABLE=() INCIDENCIA=() REPOSITORIO_GITHUB=()

rotulo() {
    local ruta=$1
    if [[ -n $RAIZ && $ruta == "$RAIZ" ]]; then printf '.'
    elif [[ -n $RAIZ && $ruta == "$RAIZ/"* ]]; then printf '%s' "${ruta#"$RAIZ/"}"
    else printf '%s' "$ruta"; fi
}
fallar() { printf 'git %s: [%s] %s\n' "$MODO" "$(rotulo "$1")" "$2" >&2; exit 1; }
esta_dentro() { [[ $1 == "$2" || $1 == "$2/"* ]]; }
huella_archivo() { local suma; suma=$(sha256sum -- "$1") || return; printf '%s' "${suma%% *}"; }
huella_texto() { local suma; suma=$(printf '%s' "$1" | sha256sum) || return; printf '%s' "${suma%% *}"; }
# La sustitución normal de Bash recorta saltos de línea finales de los datos.
capturar_texto() {
    local _texto_destino=$1 _texto_capturado; shift
    _texto_capturado=$("$@"; printf '\034')
    _texto_capturado=${_texto_capturado%$'\034'}
    printf -v "$_texto_destino" '%s' "$_texto_capturado"
}
ruta_real() { local _ruta_resuelta; capturar_texto _ruta_resuelta realpath -m -- "$1"; printf '%s' "${_ruta_resuelta%$'\n'}"; }
resolver_ruta() { if [[ $2 == /* ]]; then ruta_real "$2"; else ruta_real "$1/$2"; fi; }

# Capturar sin evaluación shell. Los estados permitidos se declaran en cada llamada.
capturar_git() {
    local _captura_ruta=$1 _captura_destino=$2 _captura_codigos=$3 _captura_archivo _captura_error _captura_estado _captura_texto _captura_comando
    shift 3
    CONTADOR_CAPTURAS=$((CONTADOR_CAPTURAS + 1))
    _captura_archivo="$TEMPORALES/git-$BASHPID-$CONTADOR_CAPTURAS.salida"
    _captura_error="$TEMPORALES/git-$BASHPID-$CONTADOR_CAPTURAS.error"
    if GIT_LITERAL_PATHSPECS=1 git -C "$_captura_ruta" -c submodule.recurse=false -c fetch.recurseSubmodules=false "$@" >"$_captura_archivo" 2>"$_captura_error"; then _captura_estado=0; else _captura_estado=$?; fi
    ESTADO_GIT=$_captura_estado
    if [[ " $_captura_codigos " != *" $_captura_estado "* ]]; then
        _captura_comando=$1
        if [[ $_captura_comando == -c ]]; then local -a _captura_argumentos=("$@"); local _captura_indice=0; while [[ ${_captura_argumentos[$_captura_indice]} == -c ]]; do _captura_indice=$((_captura_indice + 2)); done; _captura_comando=${_captura_argumentos[$_captura_indice]}; fi
        _captura_texto=$(<"$_captura_error")
        fallar "$_captura_ruta" "$_captura_comando falló (código $_captura_estado).${_captura_texto:+$'\n'$_captura_texto}"
    fi
    capturar_texto _captura_texto cat -- "$_captura_archivo"
    _captura_texto=${_captura_texto%$'\n'}
    printf -v "$_captura_destino" '%s' "$_captura_texto"
}
# Variante binaria para las listas NUL; el destino pertenece al directorio temporal.
guardar_salida_git() {
    local ruta=$1 salida=$2; shift 2
    if GIT_LITERAL_PATHSPECS=1 git -C "$ruta" -c submodule.recurse=false -c fetch.recurseSubmodules=false "$@" >"$salida"; then return 0; else fallar "$ruta" "${1-} falló al leer datos Git."; fi
}
ejecutar_git() {
    local ruta=$1 codigo; shift
    if GIT_LITERAL_PATHSPECS=1 git -C "$ruta" -c submodule.recurse=false -c fetch.recurseSubmodules=false "$@"; then return 0; else codigo=$?; fallar "$ruta" "${1-} falló (código $codigo)."; fi
}
valor_configuracion() {
    local ruta=$1 clave=$2 archivo=${3-} entrada resultado= primero= encontrado=false
    local salida; salida=$(mktemp "$TEMPORALES/config.XXXXXX")
    local -a argumentos=(config); [[ -z $archivo ]] || argumentos+=(--file "$archivo")
    if GIT_LITERAL_PATHSPECS=1 git -C "$ruta" -c submodule.recurse=false -c fetch.recurseSubmodules=false "${argumentos[@]}" --null --get-all "$clave" >"$salida"; then :
    else local codigo=$?; [[ $codigo == 1 ]] || fallar "$ruta" "No se pudo leer $clave."; return 0; fi
    while IFS= read -r -d '' entrada; do
        if [[ -n $archivo && $encontrado == true && $entrada != "$primero" ]]; then fallar "$ruta" "Configuración ambigua: $clave en $archivo."; fi
        primero=$entrada; encontrado=true; resultado=$entrada
    done <"$salida"
    printf '%s' "$resultado"
}
valor_booleano() {
    local resultado; capturar_git "$1" resultado '0 1' config --type=bool --get "$2"
    if [[ $ESTADO_GIT == 1 || $resultado == true ]]; then printf true; else printf false; fi
}
obtener_sha() { local resultado; capturar_git "$1" resultado 0 rev-parse --verify HEAD; printf '%s' "$resultado"; }
nombre_solo_lectura() {
    local nombre=${1%%[?#]*}; nombre=${nombre%/}; nombre=${nombre##*/}; nombre=${nombre##*:}; nombre=${nombre%.git}
    [[ $nombre == .brand || $nombre == __* ]]
}
repositorio_solo_lectura() {
    local ruta=$1 remotos entrada
    if nombre_solo_lectura "$ruta"; then return 0; fi
    capturar_git "$ruta" remotos '0 1' config --get-regexp '^remote\..*\.(url|pushurl)$'
    while IFS= read -r entrada; do
        if nombre_solo_lectura "${entrada#* }"; then return 0; fi
    done <<< "$remotos"
    return 1
}
es_ancestro() { local resultado; capturar_git "$1" resultado '0 1' merge-base --is-ancestor "$2" "$3"; [[ $ESTADO_GIT == 0 ]]; }
referencias_remotas() {
    local ruta=$1 remoto=$2; shift 2
    local resultado identificador referencia datos_json='{}'; capturar_git "$ruta" resultado 0 ls-remote --heads -- "$remoto" "$@"
    while IFS=$'\t' read -r identificador referencia; do [[ -n $identificador ]] || continue; datos_json=$(asignar_clave_json "$datos_json" "$referencia" "$(citar_json "$identificador")"); done <<< "$resultado"
    printf '%s' "$datos_json"
}
referencias_y_etiquetas_remotas() {
    local ruta=$1 remoto=$2 resultado identificador referencia datos_json='{}'; capturar_git "$ruta" resultado 0 ls-remote --heads --tags -- "$remoto"
    while IFS=$'\t' read -r identificador referencia; do [[ -n $identificador ]] || continue; datos_json=$(asignar_clave_json "$datos_json" "$referencia" "$(citar_json "$identificador")"); done <<< "$resultado"
    printf '%s' "$datos_json"
}
referencias_modulos() {
    local ruta=$1 confirmados=${2-false} salida entrada metadatos nombre modo tipo identificador datos_json='{}'
    salida=$(mktemp "$TEMPORALES/referencias_modulos.XXXXXX")
    if [[ $confirmados == true ]]; then guardar_salida_git "$ruta" "$salida" ls-tree -rz HEAD; else guardar_salida_git "$ruta" "$salida" ls-files --stage -z; fi
    while IFS= read -r -d '' entrada; do
        metadatos=${entrada%%$'\t'*}; nombre=${entrada#*$'\t'}; read -r modo tipo identificador <<< "$metadatos"
        if [[ $confirmados == true ]]; then [[ $modo == 160000 ]] || continue
        elif [[ $identificador != 0 ]]; then fallar "$ruta" "Hay conflictos sin resolver en $(printf '%q' "$nombre")."
        elif [[ $modo == 160000 ]]; then identificador=$tipo
        else continue; fi
        datos_json=$(asignar_clave_json "$datos_json" "$nombre" "$(citar_json "$identificador")")
    done <"$salida"
    printf '%s' "$datos_json"
}
contenido_modulos() {
    local nombre_archivo="$1/.gitmodules"
    [[ ! -L $nombre_archivo ]] || fallar "$1" '.gitmodules no puede ser un enlace simbólico.'
    if [[ -f $nombre_archivo ]]; then huella_archivo "$nombre_archivo"; else huella_texto ''; fi
}
huella_repositorio() { agregar_json "$(agregar_json '[]' "$(referencias_modulos "$1")")" "$(citar_json "$(contenido_modulos "$1")")"; }
rama_configurada() {
    local padre=$1 nombre=$2 hijo=$3 clave="submodule.$2.branch" salida entrada rama= primero= encontrado=false
    salida=$(mktemp "$TEMPORALES/rama.XXXXXX")
    if git -C "$padre" config --local --null --get-all "$clave" >"$salida"; then
        while IFS= read -r -d '' entrada; do
            [[ $encontrado == false || $entrada == "$primero" ]] || fallar "$hijo" "Hay varias ramas locales configuradas en $clave."
            primero=$entrada; encontrado=true
        done <"$salida"
    else local codigo=$?; [[ $codigo == 1 ]] || fallar "$hijo" "No se pudo leer $clave."; fi
    capturar_git "$padre" rama '0 1' config --get "$clave"
    # Un valor local vacío también es una preferencia: no lo reemplaza .gitmodules.
    if [[ $ESTADO_GIT == 1 ]]; then rama=$(valor_configuracion "$padre" "$clave" .gitmodules); fi
    if [[ $rama == . ]]; then printf '%s' "${RAMA[$padre]}"; else printf '%s' "$rama"; fi
}
normalizar_ruta_remota() {
    local ruta=$1 parte resto=$1 resultado= absoluta=false; local -a pila=() partes=()
    [[ $ruta != /* ]] || absoluta=true
    while [[ $resto == */* ]]; do partes+=("${resto%%/*}"); resto=${resto#*/}; done
    partes+=("$resto")
    for parte in "${partes[@]}"; do
        case "$parte" in ''|.) ;; ..) if ((${#pila[@]})) && [[ ${pila[-1]} != .. ]]; then unset 'pila[-1]'; elif [[ $absoluta == false ]]; then pila+=(..); fi ;; *) pila+=("$parte") ;; esac
    done
    local IFS=/; resultado="${pila[*]}"; if [[ $absoluta == true ]]; then resultado="/$resultado"; fi
    printf '%s' "${resultado:-.}"
}
url_absoluta() {
    local padre=$1 direccion=$2 remoto base prefijo ruta normalizada sufijo=
    if [[ $direccion != ./* && $direccion != ../* ]]; then printf '%s' "$direccion"; return; fi
    if [[ ${CABEZA_SEPARADA[$padre]} == true ]]; then remoto=origin; else remoto=${REMOTO[$padre]}; fi
    capturar_git "$padre" base 0 remote get-url -- "$remoto"
    if [[ $base == *://* ]]; then
        local esquema=${base%%://*} resto=${base#*://} autoridad
        autoridad=${resto%%/*}; ruta=${resto#"$autoridad"}; prefijo="$esquema://$autoridad"
        if [[ $ruta == *\?* || $ruta == *\#* ]]; then sufijo=${ruta#"${ruta%%[?#]*}"}; ruta=${ruta%%[?#]*}; fi
        capturar_texto normalizada normalizar_ruta_remota "$ruta/$direccion"
        printf '%s%s%s' "$prefijo" "$normalizada" "$sufijo"
    elif [[ $base == *:* && $base != /* ]]; then capturar_texto normalizada normalizar_ruta_remota "${base#*:}/$direccion"; printf '%s:%s' "${base%%:*}" "$normalizada"
    else capturar_texto ruta resolver_ruta "$padre" "$base"; ruta_real "$ruta/$direccion"; fi
}
ruta_estado() { local comun; capturar_git "$1" comun 0 rev-parse --git-common-dir; capturar_texto comun resolver_ruta "$1" "$comun"; printf '%s/tunning-sync/state.json' "$comun"; }
leer_estado() { local nombre_archivo; nombre_archivo=$(ruta_estado "$1"); if [[ -f $nombre_archivo ]]; then canonizar_json "$(<"$nombre_archivo")"; else printf '{}'; fi; }
guardar_estado() {
    local ruta=$1 datos=$2 nombre_archivo directorio temporal; nombre_archivo=$(ruta_estado "$ruta"); directorio=${nombre_archivo%/*}
    mkdir -p -m 700 -- "$directorio"; temporal=$(mktemp "$directorio/.estado.XXXXXX")
    canonizar_json "$datos" >"$temporal"; chmod 600 "$temporal"; mv -f -- "$temporal" "$nombre_archivo"
}
comandos_comprobacion() {
    local ruta=$1 resultado
    capturar_git "$ruta" resultado '0 1' config --get tunning.testCommands
    if [[ $ESTADO_GIT == 1 ]]; then if [[ -f $ruta/scripts/verify.sh ]]; then printf '[["bash","scripts/verify.sh"]]'; else printf '[]'; fi; return; fi
    comandos_validos "$resultado" || fallar "$ruta" 'tunning.testCommands necesita un JSON no vacío de arrays de argumentos.'
    canonizar_json "$resultado"
}
comandos_validos() {
    local comandos=$1 orden argumento
    json_valido "$comandos" && [[ $(tipo_json "$comandos") == array && $(longitud_json "$comandos") -gt 0 ]] || return 1
    while IFS= read -r orden; do
        [[ $(tipo_json "$orden") == array && $(longitud_json "$orden") -gt 0 ]] || return 1
        while IFS= read -r argumento; do [[ $(tipo_json "$argumento") == string && -n $(obtener_texto_json "$argumento" '') ]] || return 1; done < <(elementos_json "$orden")
    done < <(elementos_json "$comandos")
}
inventariar_repositorio() {
    local ruta=$1 indice resultado confirmados archivos nombre_archivo entrada detalle modo archivos_json='{}'
    capturar_git "$ruta" indice 0 rev-parse --git-path index
    capturar_texto indice resolver_ruta "$ruta" "$indice"
    if [[ -f $indice ]]; then indice=$(huella_archivo "$indice"); else indice=; fi
    confirmados=$(referencias_modulos "$ruta" true); archivos=$(mktemp "$TEMPORALES/inventario.XXXXXX")
    guardar_salida_git "$ruta" "$archivos" ls-files --cached --others --exclude-standard -z
    while IFS= read -r -d '' nombre_archivo; do
        [[ -n $nombre_archivo ]] || continue; entrada="$ruta/$nombre_archivo"
        if tiene_clave_json "$confirmados" "$nombre_archivo"; then
            if [[ -n ${MODULOS_LECTURA[$ruta]-} ]] && tiene_clave_json "${MODULOS_LECTURA[$ruta]}" "$nombre_archivo"; then
                detalle=$(obtener_clave_json "${MODULOS_LECTURA[$ruta]}" "$nombre_archivo")
                archivos_json=$(asignar_clave_json "$archivos_json" "$nombre_archivo" "$detalle")
                continue
            fi
            [[ -e $entrada/.git ]] || fallar "$entrada" 'La auditoría exige un módulo inicializado; no modifica checkouts para prepararlo.'
            detalle=$(inventariar_repositorio "$entrada")
        elif [[ -L $entrada ]]; then
            local destino_enlace; capturar_texto destino_enlace readlink -- "$entrada"; destino_enlace=${destino_enlace%$'\n'}
            detalle=$(agregar_json '["symlink"]' "$(citar_json "$destino_enlace")")
        elif [[ -f $entrada ]]; then modo=$(stat -c %a -- "$entrada"); modo=$((8#$modo & 0777)); detalle=$(agregar_json "[$modo]" "$(citar_json "$(huella_archivo "$entrada")")")
        else detalle=null; fi
        archivos_json=$(asignar_clave_json "$archivos_json" "$nombre_archivo" "$detalle")
    done <"$archivos"
    if [[ -n $indice ]]; then indice=$(citar_json "$indice"); else indice=null; fi
    objeto_json head "$(citar_json "$(obtener_sha "$ruta")")" index "$indice" files "$archivos_json"
}
comprobar_limpieza() {
    local ruta=$1 estado hijo nombre; local -a ajustes=(-c diff.ignoreSubmodules=none)
    if [[ -n ${HIJOS[$ruta]-} ]]; then
        while IFS= read -r hijo; do capturar_texto nombre obtener_texto_json "$hijo" name; ajustes+=(-c "submodule.$nombre.ignore=none"); done < <(elementos_json "${HIJOS[$ruta]}")
    fi
    if [[ -n ${MODULOS_LECTURA[$ruta]-} ]]; then
        while IFS= read -r hijo; do capturar_texto nombre obtener_texto_json "$hijo" value.name; ajustes+=(-c "submodule.$nombre.ignore=dirty"); done < <(entradas_json "${MODULOS_LECTURA[$ruta]}")
    fi
    capturar_git "$ruta" estado 0 "${ajustes[@]}" status --porcelain=v1 --untracked-files=all
    [[ -z $estado ]] || fallar "$ruta" "Quedan cambios después de sincronizar."$'\n'"$estado"
}
comprobar_modulos_lectura() {
    local ruta=$1 confirmados=$2 entrada relativa datos identificador directorio
    while IFS= read -r entrada; do
        capturar_texto relativa obtener_texto_json "$entrada" key; datos=$(obtener_json "$entrada" value)
        identificador=$(obtener_texto_json "$datos" oid); capturar_texto directorio obtener_texto_json "$datos" repo
        [[ $(obtener_texto_clave_json "$confirmados" "$relativa") == "$identificador" ]] || fallar "$ruta" "Cambió el SHA elegido del submódulo de solo lectura: $relativa."
        if [[ -e $directorio/.git ]]; then
            [[ $(obtener_sha "$directorio") == "$identificador" ]] || fallar "$ruta" "Cambió el checkout de solo lectura: $relativa."
        fi
    done < <(entradas_json "${MODULOS_LECTURA[$ruta]}")
}
ruta_externa() {
    local repositorio=$1 nombre_archivo=$2 proposito=$3 ruta comun
    [[ $nombre_archivo != '~' ]] || nombre_archivo=$HOME
    [[ $nombre_archivo != '~/'* ]] || nombre_archivo="$HOME/${nombre_archivo:2}"
    capturar_texto ruta ruta_real "$nombre_archivo"; comun=$(ruta_estado "$repositorio"); comun=${comun%/*/*}
    if esta_dentro "$ruta" "$repositorio" || esta_dentro "$ruta" "$comun"; then fallar "$repositorio" "$proposito debe estar fuera del checkout y de su directorio Git."; fi
    printf '%s' "$ruta"
}
comprobar_antes_de_publicar() {
    local repositorio=$1 comandos anterior directorio orden archivo_registro codigo inicio fin duracion resultado
    local -a argumentos_comando=()
    comandos=$(comandos_comprobacion "$repositorio"); RESULTADOS_COMPROBACIONES[$repositorio]='[]'
    [[ $comandos != '[]' ]] || return 0
    anterior=$(inventariar_repositorio "$repositorio"); directorio=$(mktemp -d /tmp/tunning-push-checks.XXXXXX)
    printf '=> [%s] Comprobaciones locales antes del push; logs: %s\n' "$(rotulo "$repositorio")" "$directorio"
    local numero=0
    while IFS= read -r orden; do
        numero=$((numero + 1)); archivo_registro="$directorio/$numero.log"; inicio=$(date +%s%N)
        argumentos_comando=(); local argumento
        while IFS= read -r argumento; do capturar_texto argumento obtener_texto_json "$argumento" ''; argumentos_comando+=("$argumento"); done < <(elementos_json "$orden")
        if (cd -- "$repositorio" && GIT_OPTIONAL_LOCKS=0 "${argumentos_comando[@]}") >"$archivo_registro" 2>&1; then codigo=0; else codigo=$?; fi
        cat -- "$archivo_registro"; fin=$(date +%s%N); duracion=$(awk -v inicio="$inicio" -v terminar="$fin" 'BEGIN {printf "%.3f",(terminar-inicio)/1000000000}')
        resultado=$(objeto_json argv "$orden" returncode "$codigo" log_sha256 "$(citar_json "$(huella_archivo "$archivo_registro")")" log "$(citar_json "$archivo_registro")" seconds "$duracion")
        RESULTADOS_COMPROBACIONES[$repositorio]=$(agregar_json "${RESULTADOS_COMPROBACIONES[$repositorio]}" "$resultado")
        [[ $codigo == 0 ]] || fallar "$repositorio" "Comprobaciones locales fallidas (código $codigo); no se publica. Log: $archivo_registro"
    done < <(elementos_json "$comandos")
    json_iguales "$(inventariar_repositorio "$repositorio")" "$anterior" || fallar "$repositorio" 'Las comprobaciones modificaron HEAD, índice o archivos; no se publica y se conservan los cambios.'
    comprobar_limpieza "$repositorio"
}
comprobar_disponibilidad_rama() {
    local ruta=$1 arbol_trabajo
    capturar_git "$ruta" arbol_trabajo 0 for-each-ref '--format=%(worktreepath)' "refs/heads/${RAMA[$ruta]}"
    [[ -z $arbol_trabajo ]] || fallar "$ruta" "La rama configurada ${RAMA[$ruta]} está activa en otro árbol de trabajo: $arbol_trabajo."
}
comprobar_historia_comun() {
    local resultado; capturar_git "$1" resultado '0 1' merge-base HEAD "$2"
    [[ $ESTADO_GIT == 0 ]] || fallar "$1" "La confirmación $2 y HEAD no tienen historia común; se conserva el checkout."
}
asegurar_confirmacion() {
    local ruta=$1 identificador=$2 direccion=$3 resultado
    capturar_git "$ruta" resultado '0 1 128' cat-file -e "$identificador^{commit}"
    if [[ $ESTADO_GIT != 0 ]]; then ejecutar_git "$ruta" fetch --no-recurse-submodules --no-tags -- "$direccion" "$identificador"; fi
    comprobar_historia_comun "$ruta" "$identificador"
}
validar_repositorio() {
    local ruta=$1 padre=${2-} nombre=${3-} actual estado pendiente rama remoto clave_integracion integraciones resultado punta
    comandos_comprobacion "$ruta" >/dev/null
    capturar_git "$ruta" actual 0 rev-parse --show-toplevel
    capturar_texto actual ruta_real "$actual"; [[ $actual == "$ruta" ]] || fallar "$ruta" 'No es un checkout independiente del submódulo.'
    for estado in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
        capturar_git "$ruta" pendiente 0 rev-parse --git-path "$estado"
        capturar_texto pendiente resolver_ruta "$ruta" "$pendiente"
        [[ ! -e $pendiente ]] || fallar "$ruta" "Hay una operación Git pendiente ($estado); resuélvela primero."
    done
    capturar_git "$ruta" actual '0 1' symbolic-ref --quiet --short HEAD
    if [[ $ESTADO_GIT == 1 ]]; then CABEZA_SEPARADA[$ruta]=true; else CABEZA_SEPARADA[$ruta]=false; fi
    rama=$actual
    if [[ ${CABEZA_SEPARADA[$ruta]} == true && -n $padre ]]; then rama=$(rama_configurada "$padre" "$nombre" "$ruta"); fi
    [[ -n $rama ]] || fallar "$ruta" 'HEAD está separado y no hay una rama configurada inequívoca en el padre.'
    ejecutar_git "$ruta" check-ref-format "refs/heads/$rama"
    [[ $rama != HEAD ]] || fallar "$ruta" 'HEAD no es un nombre de rama válido.'
    RAMA[$ruta]=$rama; FIRMA[$ruta]=
    [[ $(valor_booleano "$ruta" tunning.syncSign) != true ]] || FIRMA[$ruta]=-S
    INTEGRAR_PRODUCCION[$ruta]=$(valor_booleano "$ruta" tunning.syncProduction)
    remoto=$(valor_configuracion "$ruta" "branch.$rama.remote"); REMOTO[$ruta]=${remoto:-origin}
    remoto=$(valor_configuracion "$ruta" "branch.$rama.pushRemote")
    [[ -n $remoto ]] || remoto=$(valor_configuracion "$ruta" remote.pushDefault)
    REMOTO_PUBLICACION[$ruta]=${remoto:-${REMOTO[$ruta]}}
    clave_integracion="branch.$rama.merge"; integraciones=$(mktemp "$TEMPORALES/integraciones.XXXXXX")
    if git -C "$ruta" config --null --get-all "$clave_integracion" >"$integraciones"; then
        local entrada primero= encontrado=false
        while IFS= read -r -d '' entrada; do
            [[ $encontrado == false || $entrada == "$primero" ]] || fallar "$ruta" "Hay varios upstreams en $clave_integracion; selecciona uno antes de sincronizar."
            primero=$entrada; encontrado=true
        done <"$integraciones"
    else local codigo=$?; [[ $codigo == 1 ]] || fallar "$ruta" "No se pudo leer $clave_integracion."; fi
    resultado=$(valor_configuracion "$ruta" "$clave_integracion"); REFERENCIA_REMOTA[$ruta]=${resultado:-refs/heads/$rama}
    [[ ${REFERENCIA_REMOTA[$ruta]} == refs/heads/* ]] || fallar "$ruta" "Upstream no publicable: ${REFERENCIA_REMOTA[$ruta]}."
    ejecutar_git "$ruta" check-ref-format "${REFERENCIA_REMOTA[$ruta]}"
    for remoto in "${REMOTO[$ruta]}" "${REMOTO_PUBLICACION[$ruta]}"; do
        [[ $remoto != . ]] || fallar "$ruta" 'El remoto local "." no permite verificar una publicación.'
        capturar_git "$ruta" resultado 0 remote get-url -- "$remoto"
    done
    capturar_git "$ruta" resultado 0 remote get-url --push --all -- "${REMOTO_PUBLICACION[$ruta]}"
    [[ -n $resultado && $resultado != *$'\n'* ]] || fallar "$ruta" "El remoto ${REMOTO_PUBLICACION[$ruta]} necesita una única URL de publicación."
    URL_PUBLICACION[$ruta]=$resultado; CABEZAS_REMOTAS[$ruta]=$(referencias_remotas "$ruta" "${REMOTO[$ruta]}")
    referencias_remotas "$ruta" "${URL_PUBLICACION[$ruta]}" >/dev/null; PUNTA_RAMA[$ruta]=
    if [[ ${CABEZA_SEPARADA[$ruta]} == true ]]; then
        comprobar_disponibilidad_rama "$ruta"; capturar_git "$ruta" punta '0 128' rev-parse --verify "refs/heads/$rama"
        if [[ $ESTADO_GIT == 0 ]]; then PUNTA_RAMA[$ruta]=$punta; comprobar_historia_comun "$ruta" "$punta"; fi
    fi
    referencias_modulos "$ruta" >/dev/null
    if [[ $MODO == syncPR || $MODO == syncPRmerge ]]; then preparar_pr "$ruta"; fi
}
preparar_repositorio() {
    local ruta=$1 padre=${2-} nombre=${3-}
    if repositorio_solo_lectura "$ruta"; then fallar "$ruta" 'Repositorio de solo lectura (.brand o __*); no se sincroniza.'; fi
    if [[ -z ${CONFIRMACIONES_CREADAS[$ruta]+presente} ]]; then REPOSITORIOS+=("$ruta"); CONFIRMACIONES_CREADAS[$ruta]='[]'; fi
    validar_repositorio "$ruta" "$padre" "$nombre"; descubrir_modulos "$ruta"
}
descubrir_modulos() {
    local ruta=$1 registrados entradas entrada clave nombre ruta_hijo declarada rama resultado efectiva direcciones direccion hijo identificador relativa nombres='{}' hijos='[]'
    CONFIGURACION_MODULOS[$ruta]=$(contenido_modulos "$ruta"); registrados=$(referencias_modulos "$ruta"); MODULOS_LECTURA[$ruta]='{}'
    if [[ $registrados == '{}' ]]; then HIJOS[$ruta]='[]'; return; fi
    [[ -f $ruta/.gitmodules && ! -L $ruta/.gitmodules ]] || fallar "$ruta" 'Hay gitlinks sin un archivo .gitmodules válido.'
    entradas=$(mktemp "$TEMPORALES/modulos.XXXXXX")
    if git -C "$ruta" config --file .gitmodules --null --get-regexp '^submodule\..*\.path$' >"$entradas"; then :
    else local codigo=$?; [[ $codigo == 1 ]] || fallar "$ruta" 'No se pudo leer .gitmodules.'; fi
    while IFS= read -r -d '' entrada; do
        clave=${entrada%%$'\n'*}; relativa=${entrada#*$'\n'}
        if tiene_clave_json "$nombres" "$relativa"; then fallar "$ruta" "Ruta de submódulo duplicada: $relativa."; fi
        nombre=${clave#submodule.}; nombre=${nombre%.path}; nombres=$(asignar_clave_json "$nombres" "$relativa" "$(citar_json "$nombre")")
    done <"$entradas"
    while IFS= read -r entrada; do
        capturar_texto relativa obtener_texto_json "$entrada" key; identificador=$(obtener_texto_json "$entrada" value)
        capturar_texto ruta_hijo ruta_real "$ruta/$relativa"
        esta_dentro "$ruta_hijo" "$ruta" && [[ $ruta_hijo != "$ruta" ]] || fallar "$ruta" "Ruta de submódulo fuera del repositorio: $relativa."
        tiene_clave_json "$nombres" "$relativa" || fallar "$ruta_hijo" 'Falta el registro del submódulo en .gitmodules.'
        capturar_texto nombre obtener_texto_clave_json "$nombres" "$relativa"; capturar_texto declarada valor_configuracion "$ruta" "submodule.$nombre.url" .gitmodules
        [[ -n $declarada ]] || fallar "$ruta_hijo" 'Falta la URL del submódulo en .gitmodules.'
        capturar_texto efectiva valor_configuracion "$ruta" "submodule.$nombre.url"
        if nombre_solo_lectura "$relativa" || nombre_solo_lectura "$nombre" || nombre_solo_lectura "$declarada" || nombre_solo_lectura "$efectiva" || { [[ -e $ruta_hijo/.git ]] && repositorio_solo_lectura "$ruta_hijo"; }; then
            if [[ -e $ruta_hijo/.git ]]; then identificador=$(obtener_sha "$ruta_hijo"); fi
            hijo=$(objeto_json name "$(citar_json "$nombre")" repo "$(citar_json "$ruta_hijo")" oid "$(citar_json "$identificador")")
            MODULOS_LECTURA[$ruta]=$(asignar_clave_json "${MODULOS_LECTURA[$ruta]}" "$relativa" "$hijo")
            printf '=> [%s] Solo lectura; se conserva el SHA %.12s.\n' "$(rotulo "$ruta_hijo")" "$identificador"
            continue
        fi
        if [[ ! -e $ruta_hijo/.git ]]; then
            rama=$(rama_configurada "$ruta" "$nombre" "$ruta_hijo")
            [[ -n $rama ]] || fallar "$ruta_hijo" 'Submódulo sin inicializar y sin rama configurada para resolver HEAD separado.'
            capturar_git "$ruta" resultado '0 1' check-ref-format "refs/heads/$rama"
            [[ $ESTADO_GIT == 0 && $rama != HEAD ]] || fallar "$ruta_hijo" "Rama configurada inválida: $rama."
            printf '=> [%s] Inicializando en la confirmación registrada %.12s...\n' "$(rotulo "$ruta_hijo")" "$identificador"
            ejecutar_git "$ruta" submodule update --init --checkout -- "$relativa"
        fi
        capturar_texto efectiva valor_configuracion "$ruta" "submodule.$nombre.url"
        if [[ -z $efectiva ]]; then ejecutar_git "$ruta" submodule init -- "$relativa"; capturar_texto efectiva valor_configuracion "$ruta" "submodule.$nombre.url"; fi
        capturar_texto declarada url_absoluta "$ruta" "$declarada"
        direcciones=$(agregar_json '[]' "$(citar_json "$declarada")")
        [[ $efectiva == "$declarada" ]] || direcciones=$(agregar_json "$direcciones" "$(citar_json "$efectiva")")
        preparar_repositorio "$ruta_hijo" "$ruta" "$nombre"; asegurar_confirmacion "$ruta_hijo" "$identificador" "$efectiva"
        while IFS= read -r hijo; do capturar_texto direccion obtener_texto_json "$hijo" ''; referencias_remotas "$ruta_hijo" "$direccion" >/dev/null; done < <(elementos_json "$direcciones")
        hijo=$(objeto_json path "$(citar_json "$relativa")" name "$(citar_json "$nombre")" oid "$(citar_json "$identificador")" urls "$direcciones" repo "$(citar_json "$ruta_hijo")")
        hijos=$(agregar_json "$hijos" "$hijo")
    done < <(entradas_json "$registrados")
    HIJOS[$ruta]=$hijos
}
confirmar_cambios() {
    local ruta=$1 hijo nombre cambiado usuario equipo mensaje identificador
    local -a ajustes=() firma=()
    printf '=> [%s] Agregando cambios...\n' "$(rotulo "$ruta")"
    while IFS= read -r hijo; do capturar_texto nombre obtener_texto_json "$hijo" name; ajustes+=(-c "submodule.$nombre.ignore=none"); done < <(elementos_json "${HIJOS[$ruta]}")
    while IFS= read -r hijo; do capturar_texto nombre obtener_texto_json "$hijo" value.name; ajustes+=(-c "submodule.$nombre.ignore=none"); done < <(entradas_json "${MODULOS_LECTURA[$ruta]}")
    ejecutar_git "$ruta" "${ajustes[@]}" add -A --
    capturar_git "$ruta" cambiado '0 1' diff --cached --quiet --ignore-submodules=none
    if [[ $ESTADO_GIT == 0 ]]; then printf '=> [%s] No hay cambios para crear una confirmación.\n' "$(rotulo "$ruta")"; return; fi
    local -a meses=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    local dia mes hora; read -r dia mes hora < <(date '+%d %m %H:%M'); dia=$((10#$dia)); mes=$((10#$mes - 1))
    usuario=$(id -un); equipo=$(hostname)
    if [[ ${TUNNING_PROFILE-} == cloudshell || -n ${CLOUD_SHELL-} || -e /google/devshell/bashrc.google ]]; then equipo=CSE; fi
    mensaje="$usuario@$equipo $dia${meses[$mes]}$hora - $MENSAJE"
    printf '=> [%s] Creando confirmación: %s\n' "$(rotulo "$ruta")" "$mensaje"
    [[ -z ${FIRMA[$ruta]} ]] || firma+=("${FIRMA[$ruta]}")
    ejecutar_git "$ruta" commit "${firma[@]}" -m "$mensaje"; identificador=$(obtener_sha "$ruta"); CONFIRMACIONES_CREADAS[$ruta]=$(agregar_json "${CONFIRMACIONES_CREADAS[$ruta]}" "$(citar_json "$identificador")")
}
integrar() {
    local ruta=$1 descripcion=$2; shift 2
    local anterior previo actual destino padres hijo retirado referencias_actuales identificador ruta_hijo
    local -a argumentos=("$@") lista_padres=()
    anterior=$(huella_repositorio "$ruta"); previo=$(obtener_sha "$ruta")
    printf '=> [%s] Integrando %s...\n' "$(rotulo "$ruta")" "$descripcion"; ejecutar_git "$ruta" "${argumentos[@]}"
    actual=$(obtener_sha "$ruta")
    if [[ $actual != "$previo" ]]; then
        if [[ ${argumentos[0]} == pull ]]; then capturar_git "$ruta" destino 0 rev-parse FETCH_HEAD; else destino=${argumentos[-1]}; fi
        capturar_git "$ruta" padres 0 log -1 --format=%P; read -r -a lista_padres <<< "$padres"
        if [[ $actual != "$destino" && ${#lista_padres[@]} -gt 1 && ${lista_padres[0]} == "$previo" ]]; then CONFIRMACIONES_CREADAS[$ruta]=$(agregar_json "${CONFIRMACIONES_CREADAS[$ruta]}" "$(citar_json "$actual")"); fi
    fi
    if ! json_iguales "$(huella_repositorio "$ruta")" "$anterior"; then
        referencias_actuales=$(referencias_modulos "$ruta")
        while IFS= read -r retirado; do
            capturar_texto retirado obtener_texto_json "$retirado" key
            if ! tiene_clave_json "$referencias_actuales" "$retirado" && [[ -e $ruta/$retirado ]]; then fallar "$ruta" "El merge retiró $retirado; su directorio se conserva. Resuelve esa eliminación antes del push."; fi
        done < <(entradas_json "$(obtener_json "$anterior" 0)")
        descubrir_modulos "$ruta"
        while IFS= read -r hijo; do capturar_texto ruta_hijo obtener_texto_json "$hijo" repo; identificador=$(obtener_texto_json "$hijo" oid); sincronizar "$ruta_hijo" "$identificador"; done < <(elementos_json "${HIJOS[$ruta]}")
        confirmar_cambios "$ruta"
    fi
}
asociar_rama() {
    local ruta=$1 actual identificador
    if [[ ${CABEZA_SEPARADA[$ruta]} != true ]]; then capturar_git "$ruta" actual 0 symbolic-ref --quiet --short HEAD; [[ $actual == "${RAMA[$ruta]}" ]] || fallar "$ruta" 'La rama activa cambió durante la sincronización.'; return; fi
    comprobar_disponibilidad_rama "$ruta"; identificador=$(obtener_sha "$ruta")
    if [[ -n ${PUNTA_RAMA[$ruta]} ]]; then
        es_ancestro "$ruta" "${PUNTA_RAMA[$ruta]}" "$identificador" || fallar "$ruta" 'La rama configurada no está integrada; no se mueve su referencia.'
        ejecutar_git "$ruta" update-ref "refs/heads/${RAMA[$ruta]}" "$identificador" "${PUNTA_RAMA[$ruta]}"
        ejecutar_git "$ruta" switch --no-recurse-submodules "${RAMA[$ruta]}"
    else ejecutar_git "$ruta" switch --no-recurse-submodules -c "${RAMA[$ruta]}"; fi
    CABEZA_SEPARADA[$ruta]=false
}
verificar_referencia() {
    local hijo=$1 identificador=$2 direcciones=$3 elemento direccion anunciadas entrada punta confirmacion alcanzable encontrada resultado
    while IFS= read -r elemento; do
        capturar_texto direccion obtener_texto_json "$elemento" ''; anunciadas=$(referencias_y_etiquetas_remotas "$hijo" "$direccion"); encontrada=false
        while IFS= read -r entrada; do [[ $(obtener_texto_json "$entrada" value) != "$identificador" ]] || encontrada=true; done < <(entradas_json "$anunciadas")
        [[ $encontrada == false ]] || continue
        alcanzable=false
        while IFS= read -r entrada; do
            punta=$(obtener_texto_json "$entrada" value); capturar_git "$hijo" resultado '0 1 128' cat-file -e "$punta"
            if [[ $ESTADO_GIT != 0 ]]; then ejecutar_git "$hijo" fetch --no-recurse-submodules --no-tags -- "$direccion" "$punta"; fi
            capturar_git "$hijo" confirmacion '0 128' rev-parse --verify "$punta^{commit}"
            if [[ $ESTADO_GIT == 0 ]] && es_ancestro "$hijo" "$identificador" "$confirmacion"; then alcanzable=true; break; fi
        done < <(entradas_json "$anunciadas")
        [[ $alcanzable == true ]] || fallar "$hijo" "La referencia $identificador no es alcanzable en el remoto registrado $direccion; no se publica su padre."
    done < <(elementos_json "$direcciones")
}
sincronizar() {
    local ruta=$1 registrado=${2-} hijo ruta_hijo identificador actual confirmados esperado remoto_seguimiento integracion_seguimiento sha_base
    local -a firma=() seguimiento=()
    while IFS= read -r hijo; do capturar_texto ruta_hijo obtener_texto_json "$hijo" repo; identificador=$(obtener_texto_json "$hijo" oid); sincronizar "$ruta_hijo" "$identificador"; done < <(elementos_json "${HIJOS[$ruta]}")
    confirmar_cambios "$ruta"; obtener_sha "$ruta" >/dev/null
    [[ -z ${FIRMA[$ruta]} ]] || firma+=("${FIRMA[$ruta]}")
    if [[ -n $registrado ]] && ! es_ancestro "$ruta" "$registrado" "$(obtener_sha "$ruta")"; then integrar "$ruta" "confirmación registrada ${registrado:0:12}" merge --no-edit --no-autostash "${firma[@]}" "$registrado"; fi
    if [[ -n ${PUNTA_RAMA[$ruta]} ]] && ! es_ancestro "$ruta" "${PUNTA_RAMA[$ruta]}" "$(obtener_sha "$ruta")"; then integrar "$ruta" "rama configurada ${RAMA[$ruta]}" merge --no-edit --no-autostash "${firma[@]}" "${PUNTA_RAMA[$ruta]}"; fi
    if tiene_clave_json "${CABEZAS_REMOTAS[$ruta]}" "${REFERENCIA_REMOTA[$ruta]}"; then integrar "$ruta" "${REMOTO[$ruta]}/${REFERENCIA_REMOTA[$ruta]#refs/heads/}" pull --no-rebase --no-edit --no-autostash --no-recurse-submodules "${firma[@]}" -- "${REMOTO[$ruta]}" "${REFERENCIA_REMOTA[$ruta]}"; fi
    if [[ ${INTEGRAR_PRODUCCION[$ruta]} == true && ${RAMA[$ruta]} != production ]] && tiene_clave_json "${CABEZAS_REMOTAS[$ruta]}" refs/heads/production; then integrar "$ruta" "${REMOTO[$ruta]}/production" pull --no-rebase --no-edit --no-autostash --no-recurse-submodules "${firma[@]}" -- "${REMOTO[$ruta]}" production; fi
    if [[ $MODO == syncPR || $MODO == syncPRmerge ]]; then
        sha_base=$(consultar_sha_rama_github "$ruta" "${BASE[$ruta]}"); asegurar_confirmacion "$ruta" "$sha_base" "${URL_PUBLICACION[$ruta]}"
        if ! es_ancestro "$ruta" "$sha_base" "$(obtener_sha "$ruta")"; then integrar "$ruta" "base PR ${BASE[$ruta]}" merge --no-edit --no-autostash "${firma[@]}" "$sha_base"; fi
    fi
    if [[ $(contenido_modulos "$ruta") != "${CONFIGURACION_MODULOS[$ruta]}" ]]; then
        descubrir_modulos "$ruta"
        while IFS= read -r hijo; do capturar_texto ruta_hijo obtener_texto_json "$hijo" repo; identificador=$(obtener_texto_json "$hijo" oid); sincronizar "$ruta_hijo" "$identificador"; done < <(elementos_json "${HIJOS[$ruta]}")
        confirmar_cambios "$ruta"
        [[ $(contenido_modulos "$ruta") == "${CONFIGURACION_MODULOS[$ruta]}" ]] || fallar "$ruta" '.gitmodules volvió a cambiar durante la confirmación; revisa los hooks.'
    fi
    asociar_rama "$ruta"; comprobar_limpieza "$ruta"; confirmados=$(referencias_modulos "$ruta" true)
    comprobar_modulos_lectura "$ruta" "$confirmados"
    local cantidad; cantidad=$(longitud_json "${MODULOS_LECTURA[$ruta]}")
    while IFS= read -r hijo; do
        cantidad=$((cantidad + 1)); capturar_texto ruta_hijo obtener_texto_json "$hijo" repo; capturar_texto actual obtener_texto_json "$hijo" path
        tiene_clave_json "$confirmados" "$actual" || fallar "$ruta" 'Los submódulos cambiaron después de validar el árbol; se detiene el push.'
        identificador=$(obtener_texto_clave_json "$confirmados" "$actual")
        [[ $identificador == "$(obtener_sha "$ruta_hijo")" && -n ${PUBLICADOS[$ruta_hijo]+presente} ]] || fallar "$ruta_hijo" 'La referencia cambió después de publicar el hijo; se detiene su padre.'
        [[ $(obtener_texto_json "${PUBLICADOS[$ruta_hijo]}" 0) == "$identificador" ]] || fallar "$ruta_hijo" 'La referencia cambió después de publicar el hijo; se detiene su padre.'
        comprobar_limpieza "$ruta_hijo"; verificar_referencia "$ruta_hijo" "$identificador" "$(obtener_json "$hijo" urls)"
    done < <(elementos_json "${HIJOS[$ruta]}")
    [[ $(longitud_json "$confirmados") == "$cantidad" ]] || fallar "$ruta" 'Los submódulos cambiaron después de validar el árbol; se detiene el push.'
    comprobar_antes_de_publicar "$ruta"
    printf '=> [%s] Publicando %s/%s...\n' "$(rotulo "$ruta")" "${REMOTO_PUBLICACION[$ruta]}" "${RAMA[$ruta]}"
    remoto_seguimiento=$(valor_configuracion "$ruta" "branch.${RAMA[$ruta]}.remote"); integracion_seguimiento=$(valor_configuracion "$ruta" "branch.${RAMA[$ruta]}.merge")
    [[ -n $remoto_seguimiento && -n $integracion_seguimiento ]] || seguimiento+=(--set-upstream)
    esperado=$(obtener_sha "$ruta"); ejecutar_git "$ruta" push --recurse-submodules=check "${seguimiento[@]}" -- "${REMOTO_PUBLICACION[$ruta]}" "HEAD:refs/heads/${RAMA[$ruta]}"
    actual=$(referencias_remotas "$ruta" "${URL_PUBLICACION[$ruta]}" "refs/heads/${RAMA[$ruta]}")
    [[ $(obtener_texto_clave_json "$actual" "refs/heads/${RAMA[$ruta]}") == "$esperado" && $(obtener_sha "$ruta") == "$esperado" ]] || fallar "$ruta" 'El HEAD local y la rama publicada no coinciden después del push.'
    comprobar_limpieza "$ruta"
    PUBLICADOS[$ruta]=$(agregar_json "$(agregar_json "$(agregar_json '[]' "$(citar_json "$esperado")")" "$(citar_json "${REMOTO_PUBLICACION[$ruta]}")")" "$(citar_json "${RAMA[$ruta]}")")
    if [[ $MODO == syncPR || $MODO == syncPRmerge ]]; then publicar_pr "$ruta"; fi
}
mostrar_resumen() {
    local ruta identificador remoto rama creados elemento constancia
    printf '%s\n' "$1"
    for ruta in "${REPOSITORIOS[@]}"; do
        [[ -n ${PUBLICADOS[$ruta]+presente} ]] || continue
        identificador=$(obtener_texto_json "${PUBLICADOS[$ruta]}" 0); remoto=$(obtener_texto_json "${PUBLICADOS[$ruta]}" 1); rama=$(obtener_texto_json "${PUBLICADOS[$ruta]}" 2); creados=
        while IFS= read -r elemento; do elemento=$(obtener_texto_json "$elemento" ''); creados+="${creados:+, }${elemento:0:12}"; done < <(elementos_json "${CONFIRMACIONES_CREADAS[$ruta]}")
        printf '  [%s] %s/%s -> %.12s; commits creados: %s\n' "$(rotulo "$ruta")" "$remoto" "$rama" "$identificador" "${creados:-ninguno}"
        if [[ -n ${SOLICITUDES_CAMBIO[$ruta]+presente} ]]; then printf '    base: %s; issue #%s; PR %s\n' "${BASE[$ruta]}" "${INCIDENCIA[$ruta]}" "$(obtener_texto_json "${SOLICITUDES_CAMBIO[$ruta]}" html_url)"; fi
    done
    for ruta in "${REPOSITORIOS[@]}"; do
        [[ -n ${FUSIONADOS[$ruta]+presente} ]] || continue; constancia=${FUSIONADOS[$ruta]}
        printf '  [%s] PR #%s fusionado: %s; progreso guardado.\n' "$(rotulo "$ruta")" "$(obtener_texto_json "$constancia" pr)" "$(obtener_texto_json "$constancia" sha)"
    done
}
interpretar_opciones() {
    local opcion clave valor tipo terminar=false; local -a mensajes=()
    OPCIONES='{"local_audit":false,"approve":false}'
    while (($#)); do
        opcion=$1; shift
        if [[ $MODO != sync && $terminar == false && $opcion == --*=* ]]; then set -- "${opcion#*=}" "$@"; opcion=${opcion%%=*}; fi
        if [[ $MODO != sync && $terminar == false && ( $opcion == --help || $opcion == -h ) ]]; then printf '%s\n' "$AYUDA"; exit 0; fi
        if [[ $MODO == sync || $terminar == true || $opcion != --* ]]; then mensajes+=("$opcion"); continue; fi
        case "$opcion" in
            --) terminar=true ;;
            --local-audit) OPCIONES=$(asignar_clave_json "$OPCIONES" local_audit true) ;;
            --approve) OPCIONES=$(asignar_clave_json "$OPCIONES" approve true) ;;
            --issue|--repository|--pr|--record|--run|--output|--provider|--session|--environment|--signing-key|--findings)
                (($#)) || fallar "$PWD" "$opcion necesita un valor."
                clave=${opcion#--}; clave=${clave//-/_}; valor=$1; shift
                if [[ $clave == issue || $clave == pr || $clave == run ]]; then
                    [[ $valor =~ ^[0-9]+$ ]] || fallar "$PWD" "$opcion necesita un número entero."
                    while [[ ${#valor} -gt 1 && $valor == 0* ]]; do valor=${valor:1}; done
                    tipo=$valor
                else tipo=$(citar_json "$valor"); fi
                OPCIONES=$(asignar_clave_json "$OPCIONES" "$clave" "$tipo") ;;
            *) fallar "$PWD" "Opción desconocida: $opcion." ;;
        esac
    done
    MENSAJE="${mensajes[*]}"; MENSAJE=${MENSAJE:-Cambios en la matrix}
}
principal() {
    local dependencia directorio_guion resultado ruta esperado
    for dependencia in git realpath sha256sum stat mktemp; do command -v "$dependencia" >/dev/null || fallar "$PWD" "Falta la herramienta $dependencia."; done
    TEMPORALES=$(mktemp -d /tmp/tunning-sync.XXXXXX)
    directorio_guion=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
    # Los módulos solo contienen funciones Bash de esta implementación.
    source "$directorio_guion/git-json.sh"
    source "$directorio_guion/git-pr.sh"
    interpretar_opciones "$@"
    if [[ $MODO == criteria ]]; then gestionar_criterios; return; fi
    case "$MODO" in sync|syncPR|syncPRmerge|audit) ;; *) fallar "$PWD" "Modo desconocido: $MODO." ;; esac
    capturar_git "$PWD" resultado 0 rev-parse --show-toplevel; capturar_texto RAIZ ruta_real "$resultado"
    if [[ $MODO == audit ]]; then ejecutar_auditoria "$RAIZ"; return; fi
    printf '%s\n' '=> Validando repositorios y submódulos antes de confirmar cambios...'
    preparar_repositorio "$RAIZ"; sincronizar "$RAIZ"
    if [[ $MODO == syncPRmerge ]]; then fusionar_arbol "$RAIZ"; fi
    local cantidad=0
    for ruta in "${REPOSITORIOS[@]}"; do
        [[ -n ${PUBLICADOS[$ruta]+presente} ]] || continue; cantidad=$((cantidad + 1)); esperado=$(obtener_texto_json "${PUBLICADOS[$ruta]}" 0)
        [[ $(obtener_sha "$ruta") == "$esperado" ]] || fallar "$ruta" 'HEAD cambió después de la publicación.'; comprobar_limpieza "$ruta"
    done
    mostrar_resumen "Sincronizados $cantidad repositorios:"
}
finalizar() {
    local estado=$?
    trap - EXIT
    [[ $BASHPID == "$PID_SINCRONIZACION" ]] || exit "$estado"
    if [[ $estado != 0 && ${#PUBLICADOS[@]} -gt 0 ]]; then mostrar_resumen 'Publicaciones completadas antes del error (sincronización incompleta):' || :; fi
    # Solo se retiran temporales internos de lecturas; los logs/evidencia se conservan.
    if [[ -n $TEMPORALES && $TEMPORALES == /tmp/tunning-sync.* ]]; then rm -rf -- "$TEMPORALES"; fi
    exit "$estado"
}
trap finalizar EXIT
trap 'printf "git %s: Interrumpido; los padres pendientes no se publicaron.\n" "$MODO" >&2; exit 130' INT
trap 'estado=$?; printf "git %s: La operación local falló (código %s); se conserva el trabajo.\n" "$MODO" "$estado" >&2; exit "$estado"' ERR
principal "$@"
