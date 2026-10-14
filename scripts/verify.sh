#!/usr/bin/env bash
# Comprobaciones estáticas locales; no instala herramientas ni usa la red.
set -euo pipefail
RAIZ=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
temporal=$(mktemp -d /tmp/tunning-verify.XXXXXX)
trap 'rm -rf -- "$temporal"' EXIT
sintaxis=0 enlaces=0 imagenes=0

fallar() { printf '%s\n' "$*" >&2; exit 1; }
prosa() {
    awk '
    {
        linea=$0; sub(/^ ? ? ?/, "", linea)
        if (linea ~ /^```/ || linea ~ /^~~~/) {
            caracter=substr(linea,1,1); marca=linea
            sub(caracter == "`" ? "[^`].*$" : "[^~].*$", "", marca)
            if (!bloque) { bloque=caracter; ancho=length(marca) }
            else if (bloque == caracter && length(marca) >= ancho) bloque=""
            next
        }
        if (!bloque) print
    }' "$1"
}
decodificar_url() {
    local original=$1 prefijo sufijo octeto
    decodificado=''
    while [[ $original =~ ^([^%]*)%([[:xdigit:]]{2})(.*)$ ]]; do
        prefijo=${BASH_REMATCH[1]}; sufijo=${BASH_REMATCH[3]}
        [[ ${BASH_REMATCH[2]} != 00 ]] || fallar 'Un enlace contiene un octeto nulo.'
        printf -v octeto '%b' "\\x${BASH_REMATCH[2]}"
        decodificado+="$prefijo$octeto"; original=$sufijo
    done
    decodificado+=$original
}
encabezados() {
    local documento=$1 titulo ancla cantidad
    local -A usadas=()
    while IFS= read -r titulo; do
        [[ $titulo =~ ^(#{1,6})[[:space:]]+(.+)$ ]] || continue
        titulo=${BASH_REMATCH[2]}
        titulo=$(printf '%s' "$titulo" | sed -E 's/[[:space:]]+#+[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')
        ancla=$(printf '%s' "${titulo,,}" | sed -E 's/[^[:alnum:]_ -]//g; s/ /-/g')
        cantidad=${usadas["encabezado:$ancla"]:-0}; usadas["encabezado:$ancla"]=$((cantidad+1))
        if ((cantidad)); then printf '%s-%s\n' "$ancla" "$cantidad"; else printf '%s\n' "$ancla"; fi
    done < <(prosa "$documento")
}
comprobar_enlaces() {
    local documento=$1 original destino fragmento ruta almacen
    while IFS= read -r original; do
        [[ $original =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: || $original == //* ]] && continue
        [[ $original != \<*\> ]] || original=${original:1:${#original}-2}
        ruta=${original%%#*}; fragmento=''
        [[ $original != *'#'* ]] || fragmento=${original#*#}
        ruta=${ruta%%\?*}
        decodificar_url "$ruta"; ruta=$decodificado
        if [[ -n $ruta ]]; then destino=$(realpath -m -- "${documento%/*}/$ruta"); else destino=$documento; fi
        [[ -e $destino ]] || fallar "${documento#"$RAIZ/"}: enlace inexistente $original"
        if [[ -n $fragmento && $destino == *.md ]]; then
            decodificar_url "$fragmento"; fragmento=$decodificado
            almacen=$temporal/$(printf '%s' "$destino" | sha256sum | cut -d ' ' -f 1)
            if [[ ! -f $almacen ]]; then encabezados "$destino" > "$almacen"; fi
            grep -Fxq -- "$fragmento" "$almacen" || fallar "${documento#"$RAIZ/"}: ancla inexistente $original"
        fi
        enlaces=$((enlaces+1))
    done < <(prosa "$documento" | awk '
        {
            texto=$0
            while (match(texto, /\]\([^)]*\)/)) {
                print substr(texto,RSTART+2,RLENGTH-3)
                texto=substr(texto,RSTART+RLENGTH)
            }
        }')
}
while IFS= read -r -d '' archivo; do
    case $archivo in
        *.sh) bash -n "$archivo"; sintaxis=$((sintaxis+1));;
        *.json) bash "$RAIZ/scripts/git-json.sh" --validate "$archivo" >/dev/null; sintaxis=$((sintaxis+1));;
        *.jsonc)
            sed '/^[[:space:]]*\/\//d' "$archivo" > "$temporal/config.json"
            bash "$RAIZ/scripts/git-json.sh" --validate "$temporal/config.json" >/dev/null
            sintaxis=$((sintaxis+1));;
        *.md) comprobar_enlaces "$archivo";;
        "$RAIZ"/assets/*.png)
            read -r -a octetos <<< "$(od -An -v -tu1 -N24 "$archivo" | tr '\n' ' ')"
            [[ ${#octetos[@]} == 24 && ${octetos[*]:0:8} == '137 80 78 71 13 10 26 10' ]] || fallar "${archivo#"$RAIZ/"}: cabecera PNG inválida"
            ancho=$((octetos[16]*16777216+octetos[17]*65536+octetos[18]*256+octetos[19]))
            alto=$((octetos[20]*16777216+octetos[21]*65536+octetos[22]*256+octetos[23]))
            ((ancho>0 && alto>0)) || fallar "${archivo#"$RAIZ/"}: dimensiones PNG inválidas"
            imagenes=$((imagenes+1));;
    esac
done < <(find "$RAIZ" -type d \( -name .git -o -name .agents -o -name .codex -o -name .aws -o -name node_modules \) -prune -o -type f -print0)
printf 'Sintaxis Bash/JSON: %s archivos; enlaces locales: %s; imágenes PNG: %s. OK\n' "$sintaxis" "$enlaces" "$imagenes"
