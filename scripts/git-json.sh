#!/usr/bin/env bash
# JSON para los comandos Bash. Los datos nunca se interpretan como código.

error_json() { printf 'JSON inválido: %s (posición %s).\n' "$1" "${J_POSICION:-0}" >&2; return 1; }

citar_json() {
    local LC_ALL=C.UTF-8
    local texto=${1-} resultado='"' caracter escapado codigo indice
    for ((indice=0; indice<${#texto}; indice++)); do
        caracter=${texto:indice:1}
        case $caracter in
            '"') resultado+='\"' ;;
            '\') resultado+='\\' ;;
            $'\b') resultado+='\b' ;; $'\f') resultado+='\f' ;;
            $'\n') resultado+='\n' ;; $'\r') resultado+='\r' ;; $'\t') resultado+='\t' ;;
            *)
                printf -v codigo '%d' "'$caracter"
                if ((codigo < 32 || codigo > 126)); then
                    if ((codigo <= 65535)); then
                        printf -v escapado '\\u%04x' "$codigo"
                    else
                        codigo=$((codigo-65536))
                        printf -v escapado '\\u%04x\\u%04x' "$((55296+(codigo>>10)))" "$((56320+(codigo&1023)))"
                    fi
                    resultado+=$escapado
                else resultado+=$caracter; fi ;;
        esac
    done
    printf '%s"' "$resultado"
}

_espacios_json() {
    while [[ ${J_TEXTO:J_POSICION:1} == [$' \t\r\n'] ]]; do ((J_POSICION+=1)); done
    return 0
}

_cadena_json() {
    local caracter fragmento hexadecimal bajo numero decodificado patron_prefijo='^[^"\\]*'
    J_CADENA=''
    [[ ${J_TEXTO:J_POSICION:1} == '"' ]] || { error_json 'se esperaba una cadena'; return 1; }
    ((J_POSICION+=1))
    while ((J_POSICION < ${#J_TEXTO})); do
        fragmento=${J_TEXTO:J_POSICION}
        [[ $fragmento =~ $patron_prefijo ]]
        fragmento=${BASH_REMATCH[0]}
        [[ $fragmento != *[$'\001'-$'\037']* ]] || { error_json 'carácter de control literal'; return 1; }
        J_CADENA+=$fragmento
        ((J_POSICION+=${#fragmento}))
        caracter=${J_TEXTO:J_POSICION:1}
        if [[ $caracter == '"' ]]; then ((J_POSICION+=1)); return 0; fi
        [[ $caracter == '\' ]] || { error_json 'cadena sin cierre'; return 1; }
        ((J_POSICION+=1))
        caracter=${J_TEXTO:J_POSICION:1}
        ((J_POSICION+=1))
        case $caracter in
            '"'|'\'|'/') J_CADENA+=$caracter ;;
            b) J_CADENA+=$'\b' ;; f) J_CADENA+=$'\f' ;; n) J_CADENA+=$'\n' ;;
            r) J_CADENA+=$'\r' ;; t) J_CADENA+=$'\t' ;;
            u)
                hexadecimal=${J_TEXTO:J_POSICION:4}
                [[ $hexadecimal =~ ^[[:xdigit:]]{4}$ ]] || { error_json 'escape Unicode'; return 1; }
                ((J_POSICION+=4)); numero=$((16#$hexadecimal))
                if ((numero >= 55296 && numero <= 56319)); then
                    [[ ${J_TEXTO:J_POSICION:2} == '\u' ]] || { error_json 'par Unicode incompleto'; return 1; }
                    ((J_POSICION+=2)); bajo=${J_TEXTO:J_POSICION:4}
                    [[ $bajo =~ ^[[:xdigit:]]{4}$ ]] || { error_json 'escape Unicode'; return 1; }
                    ((J_POSICION+=4)); bajo=$((16#$bajo))
                    ((bajo >= 56320 && bajo <= 57343)) || { error_json 'par Unicode inválido'; return 1; }
                    numero=$((65536+((numero-55296)<<10)+bajo-56320))
                elif ((numero >= 56320 && numero <= 57343)); then
                    error_json 'par Unicode inválido'; return 1
                fi
                ((numero != 0)) || { error_json 'NUL no es válido en argumentos de terminal'; return 1; }
                printf -v decodificado '\\U%08x' "$numero"
                printf -v decodificado '%b' "$decodificado"
                J_CADENA+=$decodificado ;;
            *) error_json 'escape desconocido'; return 1 ;;
        esac
    done
    error_json 'cadena sin cierre'
}

_nodo_json() {
    local profundidad=$1 nodo hijo anterior=-1 clave caracter literal patron_numero='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?'
    ((profundidad <= 128)) || { error_json 'anidamiento excesivo'; return 1; }
    _espacios_json
    nodo=$J_CANTIDAD; ((J_CANTIDAD+=1)); J_PRIMERO[nodo]=-1; J_SIGUIENTE[nodo]=-1; J_NOMBRE[nodo]=''
    caracter=${J_TEXTO:J_POSICION:1}
    case $caracter in
        '"') _cadena_json || return; J_TIPO[nodo]=string; J_VALOR[nodo]=$J_CADENA ;;
        '{'|'[')
            if [[ $caracter == '{' ]]; then J_TIPO[nodo]=object; literal='}'; else J_TIPO[nodo]=array; literal=']'; fi
            ((J_POSICION+=1)); _espacios_json
            if [[ ${J_TEXTO:J_POSICION:1} != "$literal" ]]; then
                while :; do
                    clave=''
                    if [[ ${J_TIPO[nodo]} == object ]]; then
                        _cadena_json || return; clave=$J_CADENA; _espacios_json
                        [[ ${J_TEXTO:J_POSICION:1} == ':' ]] || { error_json 'se esperaba dos puntos'; return 1; }
                        ((J_POSICION+=1))
                        hijo=${J_PRIMERO[nodo]}
                        while ((hijo >= 0)); do
                            [[ ${J_NOMBRE[hijo]} != "$clave" ]] || { error_json 'clave duplicada'; return 1; }
                            hijo=${J_SIGUIENTE[hijo]}
                        done
                    fi
                    _nodo_json "$((profundidad+1))" || return
                    hijo=$J_NODO; J_NOMBRE[hijo]=$clave
                    if ((anterior < 0)); then J_PRIMERO[nodo]=$hijo; else J_SIGUIENTE[anterior]=$hijo; fi
                    anterior=$hijo; _espacios_json
                    [[ ${J_TEXTO:J_POSICION:1} == ',' ]] || break
                    ((J_POSICION+=1)); _espacios_json
                done
            fi
            [[ ${J_TEXTO:J_POSICION:1} == "$literal" ]] || { error_json 'cierre de objeto o arreglo'; return 1; }
            ((J_POSICION+=1)) ;;
        t|f|n)
            case $caracter in t) literal=true; J_TIPO[nodo]=boolean ;; f) literal=false; J_TIPO[nodo]=boolean ;; n) literal=null; J_TIPO[nodo]=null ;; esac
            [[ ${J_TEXTO:J_POSICION:${#literal}} == "$literal" ]] || { error_json 'literal desconocido'; return 1; }
            J_VALOR[nodo]=$literal; ((J_POSICION+=${#literal})) ;;
        *)
            if [[ ${J_TEXTO:J_POSICION} =~ $patron_numero ]]; then
                J_VALOR[nodo]=${BASH_REMATCH[0]}; J_TIPO[nodo]=number; ((J_POSICION+=${#BASH_REMATCH[0]}))
            else error_json 'valor desconocido'; return 1; fi ;;
    esac
    J_NODO=$nodo
}

interpretar_json() {
    local LC_ALL=C.UTF-8
    J_TEXTO=${1-}; J_POSICION=0; J_CANTIDAD=0; J_RAIZ=0; J_NODO=0
    J_TIPO=(); J_VALOR=(); J_PRIMERO=(); J_SIGUIENTE=(); J_NOMBRE=()
    _nodo_json 0 || return
    J_RAIZ=$J_NODO; _espacios_json
    ((J_POSICION == ${#J_TEXTO})) || { error_json 'datos después del valor'; return 1; }
}

json_valido() { (interpretar_json "${1-}") >/dev/null 2>&1; }

_emitir_json() {
    local nodo=$1 hijo separador='' clave indice
    case ${J_TIPO[nodo]} in
        string) citar_json "${J_VALOR[nodo]}" ;;
        number|boolean|null) printf '%s' "${J_VALOR[nodo]}" ;;
        array)
            printf '['; hijo=${J_PRIMERO[nodo]}
            while ((hijo >= 0)); do printf '%s' "$separador"; _emitir_json "$hijo"; separador=','; hijo=${J_SIGUIENTE[hijo]}; done
            printf ']' ;;
        object)
            printf '{'
            while IFS= read -r -d '' clave; do
                hijo=${J_PRIMERO[nodo]}
                while ((hijo >= 0)); do
                    if [[ ${J_NOMBRE[hijo]} == "$clave" ]]; then
                        printf '%s' "$separador"; citar_json "$clave"; printf ':'; _emitir_json "$hijo"; separador=','; break
                    fi
                    hijo=${J_SIGUIENTE[hijo]}
                done
            done < <(
                hijo=${J_PRIMERO[nodo]}
                while ((hijo >= 0)); do printf '%s\0' "${J_NOMBRE[hijo]}"; hijo=${J_SIGUIENTE[hijo]}; done | LC_ALL=C sort -z
            )
            printf '}' ;;
    esac
}

canonizar_json() { interpretar_json "${1-}" || return; _emitir_json "$J_RAIZ"; }
json_iguales() { local primero segundo; primero=$(canonizar_json "$1") && segundo=$(canonizar_json "$2") && [[ $primero == "$segundo" ]]; }

_buscar_clave_json() {
    local padre=$1 clave=$2 hijo=${J_PRIMERO[$1]}
    J_ENCONTRADO=-1
    if [[ ${J_TIPO[padre]} == object ]]; then
        while ((hijo >= 0)); do
            if [[ ${J_NOMBRE[hijo]} == "$clave" ]]; then J_ENCONTRADO=$hijo; return 0; fi
            hijo=${J_SIGUIENTE[hijo]}
        done
    elif [[ ${J_TIPO[padre]} == array && $clave =~ ^[0-9]+$ ]]; then
        local desplazamiento=0
        while ((hijo >= 0)); do
            if ((desplazamiento == 10#$clave)); then J_ENCONTRADO=$hijo; return 0; fi
            ((desplazamiento+=1)); hijo=${J_SIGUIENTE[hijo]}
        done
    fi
    return 1
}

_buscar_ruta_json() {
    local ruta=${1-} nodo=$J_RAIZ clave
    J_ENCONTRADO=$nodo
    while [[ -n $ruta ]]; do
        clave=${ruta%%.*}
        _buscar_clave_json "$nodo" "$clave" || return 1
        nodo=$J_ENCONTRADO
        if [[ $ruta == *.* ]]; then ruta=${ruta#*.}; else ruta=''; fi
    done
    J_ENCONTRADO=$nodo
}

obtener_json() {
    interpretar_json "$1" || return
    if _buscar_ruta_json "${2-}"; then _emitir_json "$J_ENCONTRADO"; else printf '%s' "${3-null}"; fi
}

_texto_nodo_json() {
    case ${J_TIPO[$1]} in
        string|number|boolean) printf '%s' "${J_VALOR[$1]}" ;;
        object|array) _emitir_json "$1" ;;
    esac
}

obtener_texto_json() { interpretar_json "$1" || return; if _buscar_ruta_json "${2-}"; then _texto_nodo_json "$J_ENCONTRADO"; fi; }
obtener_clave_json() { interpretar_json "$1" || return; if _buscar_clave_json "$J_RAIZ" "$2"; then _emitir_json "$J_ENCONTRADO"; else printf null; fi; }
obtener_texto_clave_json() { interpretar_json "$1" || return; if _buscar_clave_json "$J_RAIZ" "$2"; then _texto_nodo_json "$J_ENCONTRADO"; fi; }
tiene_clave_json() { interpretar_json "$1" || return; _buscar_clave_json "$J_RAIZ" "$2"; }
tipo_json() { interpretar_json "$1" || return; if _buscar_ruta_json "${2-}"; then printf '%s' "${J_TIPO[J_ENCONTRADO]}"; else printf null; fi; }

longitud_json() {
    local LC_ALL=C.UTF-8
    interpretar_json "$1" || return
    local cantidad=0 hijo=${J_PRIMERO[J_RAIZ]}
    case ${J_TIPO[J_RAIZ]} in
        string) printf '%s' "${#J_VALOR[J_RAIZ]}" ;;
        object|array) while ((hijo >= 0)); do ((cantidad+=1)); hijo=${J_SIGUIENTE[hijo]}; done; printf '%s' "$cantidad" ;;
        *) return 1 ;;
    esac
}

elementos_json() {
    interpretar_json "$1" || return
    [[ ${J_TIPO[J_RAIZ]} == array ]] || { error_json 'se esperaba un arreglo'; return 1; }
    local hijo=${J_PRIMERO[J_RAIZ]}
    while ((hijo >= 0)); do _emitir_json "$hijo"; printf '\n'; hijo=${J_SIGUIENTE[hijo]}; done
}

claves_json() {
    interpretar_json "$1" || return
    [[ ${J_TIPO[J_RAIZ]} == object ]] || return 1
    local hijo=${J_PRIMERO[J_RAIZ]}
    while ((hijo >= 0)); do citar_json "${J_NOMBRE[hijo]}"; printf '\n'; hijo=${J_SIGUIENTE[hijo]}; done
}

entradas_json() {
    interpretar_json "$1" || return
    [[ ${J_TIPO[J_RAIZ]} == object ]] || return 1
    local hijo clave
    while IFS= read -r -d '' clave; do
        hijo=${J_PRIMERO[J_RAIZ]}
        while ((hijo >= 0)); do
            if [[ ${J_NOMBRE[hijo]} == "$clave" ]]; then
                printf '{"key":'; citar_json "$clave"; printf ',"value":'
                _emitir_json "$hijo"; printf '}\n'; break
            fi
            hijo=${J_SIGUIENTE[hijo]}
        done
    done < <(
        hijo=${J_PRIMERO[J_RAIZ]}
        while ((hijo >= 0)); do printf '%s\0' "${J_NOMBRE[hijo]}"; hijo=${J_SIGUIENTE[hijo]}; done | LC_ALL=C sort -z
    )
}

objeto_json() {
    local separador='' clave codificado
    (($#%2 == 0)) || return 1
    printf '{'
    while (($#)); do
        clave=$1; codificado=$(canonizar_json "$2") || return; shift 2
        printf '%s' "$separador"; citar_json "$clave"; printf ':%s' "$codificado"; separador=','
    done
    printf '}'
}

asignar_clave_json() {
    local objeto=$1 clave=$2 reemplazo=$3 hijo separador='' encontrado=false
    reemplazo=$(canonizar_json "$reemplazo") || return
    interpretar_json "$objeto" || return
    [[ ${J_TIPO[J_RAIZ]} == object ]] || return 1
    printf '{'; hijo=${J_PRIMERO[J_RAIZ]}
    while ((hijo >= 0)); do
        printf '%s' "$separador"; citar_json "${J_NOMBRE[hijo]}"; printf ':'
        if [[ ${J_NOMBRE[hijo]} == "$clave" ]]; then printf '%s' "$reemplazo"; encontrado=true; else _emitir_json "$hijo"; fi
        separador=','; hijo=${J_SIGUIENTE[hijo]}
    done
    if [[ $encontrado == false ]]; then printf '%s' "$separador"; citar_json "$clave"; printf ':%s' "$reemplazo"; fi
    printf '}'
}

quitar_clave_json() {
    interpretar_json "$1" || return
    [[ ${J_TIPO[J_RAIZ]} == object ]] || return 1
    local clave=$2 hijo=${J_PRIMERO[J_RAIZ]} separador=''
    printf '{'
    while ((hijo >= 0)); do
        if [[ ${J_NOMBRE[hijo]} != "$clave" ]]; then
            printf '%s' "$separador"; citar_json "${J_NOMBRE[hijo]}"; printf ':'; _emitir_json "$hijo"; separador=','
        fi
        hijo=${J_SIGUIENTE[hijo]}
    done
    printf '}'
}

agregar_json() {
    local arreglo valor separador=''
    arreglo=$(canonizar_json "$1") || return; valor=$(canonizar_json "$2") || return
    [[ $arreglo == '['* ]] || return 1
    [[ $arreglo == '[]' ]] || separador=','
    printf '%s%s%s]' "${arreglo%]}" "$separador" "$valor"
}

asignar_json() {
    local objeto=$1 ruta=$2 reemplazo=$3 clave anidado
    [[ -n $ruta ]] || { canonizar_json "$reemplazo"; return; }
    clave=${ruta%%.*}
    if [[ $ruta == *.* ]]; then
        anidado=$(obtener_clave_json "$objeto" "$clave") || return
        [[ $anidado != null ]] || anidado='{}'
        reemplazo=$(asignar_json "$anidado" "${ruta#*.}" "$reemplazo") || return
    fi
    asignar_clave_json "$objeto" "$clave" "$reemplazo"
}

leer_documento_json() {
    local archivo=$1 contenido
    [[ -f $archivo && -r $archivo ]] || { error_json 'archivo ilegible'; return 1; }
    # Bash no puede almacenar NUL. Rechazarlo antes de leer evita perder bytes.
    if ! LC_ALL=C tr -d '\000' < "$archivo" | cmp -s -- "$archivo" -; then
        error_json 'octeto NUL literal en el archivo'; return 1
    fi
    contenido=$(cat -- "$archivo") || return
    interpretar_json "$contenido" || return
    printf '%s' "$contenido"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
    if [[ ${1-} != --validate || $# != 2 ]]; then printf 'Uso: bash git-json.sh --validate ARCHIVO\n' >&2; exit 2; fi
    leer_documento_json "$2" >/dev/null
fi
