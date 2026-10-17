#!/usr/bin/env bash
# Gestión de PR y evidencia; se carga desde el motor común de sincronización.

codificar_url() {
    local LC_ALL=C texto=$1 caracter numero posicion
    for ((posicion=0; posicion<${#texto}; posicion++)); do
        caracter=${texto:posicion:1}
        case $caracter in [a-zA-Z0-9.~_-]) printf '%s' "$caracter" ;; *) printf -v numero '%d' "'$caracter"; printf '%%%02X' "$numero" ;; esac
    done
}

api_github() {
    local ruta=$1 extremo=${2-} metodo=${3-GET} datos=${4-} respuesta archivo_error codigo
    local repositorio=${REPOSITORIO_GITHUB[$1]-} destino
    command -v gh >/dev/null || fallar "$ruta" 'Los modos PR necesitan GitHub CLI (gh).'
    [[ $repositorio =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fallar "$ruta" 'Nombre de repositorio GitHub inválido.'
    destino="repos/$repositorio${extremo:+/$extremo}"
    archivo_error=$(mktemp "$TEMPORALES/github.XXXXXX")
    local -a argumentos=(api --hostname github.com --method "$metodo" "$destino")
    if [[ -n $datos ]]; then
        json_valido "$datos" || fallar "$ruta" 'Datos JSON inválidos para GitHub.'
        argumentos+=(--input -)
        if respuesta=$(cd -- "$ruta" && GH_PROMPT_DISABLED=1 gh "${argumentos[@]}" <<< "$datos" 2>"$archivo_error"); then :
        else codigo=$?; fallar "$ruta" "GitHub $metodo ${extremo:-$repositorio} falló; revisa gh auth status y permisos (código $codigo)."; fi
    elif respuesta=$(cd -- "$ruta" && GH_PROMPT_DISABLED=1 gh "${argumentos[@]}" 2>"$archivo_error"); then :
    else codigo=$?; fallar "$ruta" "GitHub $metodo ${extremo:-$repositorio} falló; revisa gh auth status y permisos (código $codigo)."; fi
    [[ -n $respuesta ]] || respuesta=null
    json_valido "$respuesta" || fallar "$ruta" 'Respuesta JSON inválida de GitHub.'
    printf '%s' "$respuesta"
}

paginas_github() {
    local ruta=$1 extremo=$2 clave=${3-} pagina respuesta lote elemento acumulado='[]' separador='?'
    [[ $extremo != *'?'* ]] || separador='&'
    for ((pagina=1; pagina<=1000; pagina++)); do
        respuesta=$(api_github "$ruta" "$extremo${separador}per_page=100&page=$pagina")
        if [[ -n $clave ]]; then lote=$(obtener_json "$respuesta" "$clave"); else lote=$respuesta; fi
        [[ $(tipo_json "$lote") == array ]] || fallar "$ruta" "Lista inválida de GitHub: $extremo."
        while IFS= read -r elemento; do acumulado=$(agregar_json "$acumulado" "$elemento"); done < <(elementos_json "$lote")
        if (($(longitud_json "$lote") < 100)); then printf '%s' "$acumulado"; return; fi
    done
    fallar "$ruta" 'La consulta GitHub excede el límite de paginación.'
}

consultar_sha_rama_github() {
    local respuesta; respuesta=$(api_github "$1" "git/ref/heads/$(codificar_url "$2")")
    local identificador; identificador=$(obtener_texto_json "$respuesta" object.sha)
    [[ $identificador =~ ^[a-f0-9]{40,64}$ ]] || fallar "$1" 'GitHub no devolvió un SHA de rama válido.'
    printf '%s' "$identificador"
}

nombre_repositorio_github() {
    local ruta=$1 remoto=$2 direccion repositorio
    direccion=$(valor_configuracion "$ruta" "remote.$remoto.pushurl")
    [[ -n $direccion ]] || direccion=$(valor_configuracion "$ruta" "remote.$remoto.url")
    case $direccion in
        git@github.com:*) repositorio=${direccion#git@github.com:} ;;
        https://github.com/*) repositorio=${direccion#https://github.com/} ;;
        ssh://git@github.com/*) repositorio=${direccion#ssh://git@github.com/} ;;
        *) fallar "$ruta" "El remoto $remoto no identifica inequívocamente un repositorio en github.com." ;;
    esac
    repositorio=${repositorio%/}; repositorio=${repositorio%.git}
    [[ $repositorio =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fallar "$ruta" 'Nombre de repositorio GitHub inválido.'
    printf '%s' "$repositorio"
}

extraer_criterios() {
    local cuerpo=$1 ruta=$2 linea seccion=false filas='[]' numero=0 marca texto fila
    local expresion='^- \[([ xX])\] (.+)$' encabezado='^## Criterios de aceptación[[:space:]]*$'
    while IFS= read -r linea || [[ -n $linea ]]; do
        if [[ $linea =~ $encabezado ]]; then seccion=true; continue; fi
        [[ $seccion == true ]] || continue
        [[ $linea != '## '* ]] || break
        if [[ $linea =~ $expresion ]]; then
            marca=${BASH_REMATCH[1]}; texto=${BASH_REMATCH[2]}; texto=${texto%%' — '*}
            texto=${texto#"${texto%%[![:space:]]*}"}; texto=${texto%"${texto##*[![:space:]]}"}
            numero=$((numero+1)); [[ $marca == ' ' ]] && marca=false || marca=true
            fila=$(agregar_json "$(agregar_json "$(agregar_json '[]' "$(citar_json "A$numero")")" "$marca")" "$(citar_json "$texto")")
            filas=$(agregar_json "$filas" "$fila")
        fi
    done <<< "$cuerpo"
    ((numero > 0)) || fallar "$ruta" 'El issue no tiene una sección de Criterios de aceptación con casillas.'
    printf '%s' "$filas"
}

huella_criterios() {
    local fila pares='[]' par
    while IFS= read -r fila; do
        par=$(agregar_json "$(agregar_json '[]' "$(obtener_json "$fila" 0)")" "$(obtener_json "$fila" 2)")
        pares=$(agregar_json "$pares" "$par")
    done < <(elementos_json "$1")
    huella_texto "$(canonizar_json "$pares")"
}

extraer_evidencia() {
    local cuerpo=$1 ruta=$2 linea dentro=false bloque='' bloques=0
    local apertura='^```tunning-evidence[[:space:]]*$' cierre='^```[[:space:]]*$'
    while IFS= read -r linea || [[ -n $linea ]]; do
        if [[ $dentro == false && $linea =~ $apertura ]]; then
            bloques=$((bloques+1)); dentro=true; continue
        fi
        if [[ $dentro == true ]]; then
            if [[ $linea =~ $cierre ]]; then dentro=false; else bloque+="$linea"$'\n'; fi
        fi
    done <<< "$cuerpo"
    [[ $bloques == 1 && $dentro == false ]] || fallar "$ruta" 'Falta un único bloque tunning-evidence en el issue.'
    json_valido "$bloque" || fallar "$ruta" 'El bloque tunning-evidence no contiene JSON válido.'
    printf '%s' "$bloque"
}

incidencia_del_pr() {
    local ruta=$1 solicitud=$2 numeros numero cantidad=0 resultado
    numeros=$(obtener_texto_json "$solicitud" body | awk '
        { linea=$0; limpia=""
          while (length(linea)) {
            if (comentario) { fin=index(linea,"-->"); if (!fin) {linea=""; break}; linea=substr(linea,fin+3); comentario=0 }
            inicio=index(linea,"<!--")
            if (inicio) { limpia=limpia substr(linea,1,inicio-1); linea=substr(linea,inicio+4); comentario=1 }
            else {limpia=limpia linea; linea=""}
          }
          if (limpia ~ /^```/) { bloque=!bloque; next }
          if (!bloque && tolower(limpia) ~ /^closes #[0-9]+[ \t\r]*$/) { sub(/^[^#]*#/,"",limpia); sub(/[ \t\r]*$/,"",limpia); print limpia }
        }' | LC_ALL=C sort -u)
    while IFS= read -r numero; do
        [[ -n $numero ]] || continue; cantidad=$((cantidad+1)); resultado=$((10#$numero))
    done <<< "$numeros"
    [[ $cantidad == 1 ]] || fallar "$ruta" 'El PR necesita una única línea Closes #N con su issue de criterios.'
    printf '%s' "$resultado"
}

validar_detalles_criterios() {
    local entradas=$1 filas=$2 entrada identificador detalle fila
    local -A vistos=() esperados=()
    [[ $(tipo_json "$entradas") == array && $(longitud_json "$entradas") == "$(longitud_json "$filas")" ]] || return 1
    while IFS= read -r fila; do identificador=$(obtener_texto_json "$fila" 0); esperados[$identificador]=true; done < <(elementos_json "$filas")
    while IFS= read -r entrada; do
        [[ $(tipo_json "$entrada") == object && $(tipo_json "$entrada" id) == string && $(tipo_json "$entrada" detail) == string ]] || return 1
        identificador=$(obtener_texto_json "$entrada" id); detalle=$(obtener_texto_json "$entrada" detail)
        [[ $identificador =~ ^A[1-9][0-9]*$ && ${esperados[$identificador]+presente} && ! ${vistos[$identificador]+presente} && $detalle == *[![:space:]]* ]] || return 1
        vistos[$identificador]=true
    done < <(elementos_json "$entradas")
}

ejecucion_exitosa() {
    local ruta=$1 numero=$2 identificador=$3 flujo=$4 ejecucion
    ejecucion=$(api_github "$ruta" "actions/runs/$numero")
    [[ $(obtener_texto_json "$ejecucion" head_sha) == "$identificador" && $(obtener_texto_json "$ejecucion" status) == completed && $(obtener_texto_json "$ejecucion" conclusion) == success ]] || fallar "$ruta" "La ejecución $numero no acredita el SHA $identificador."
    local observado; observado=$(obtener_texto_json "$ejecucion" path)
    [[ ${observado%%@*} == "$flujo" ]] || fallar "$ruta" 'La ejecución pertenece a otro flujo de comprobación.'
}

comprobar_criterios() {
    local ruta=$1 solicitud=$2 numero=$3 flujo=${4:-.github/workflows/tests.yml} incidencia filas fila evidencia clave entradas entrada fuente
    incidencia=$(api_github "$ruta" "issues/$numero"); filas=$(extraer_criterios "$(obtener_texto_json "$incidencia" body)" "$ruta")
    while IFS= read -r fila; do [[ $(obtener_texto_json "$fila" 1) == true ]] || fallar "$ruta" "Issue #$numero: criterios pendientes: $(obtener_texto_json "$fila" 0)."; done < <(elementos_json "$filas")
    evidencia=$(extraer_evidencia "$(obtener_texto_json "$incidencia" body)" "$ruta")
    local esperado; esperado=$(objeto_json schema 1 repository "$(citar_json "${REPOSITORIO_GITHUB[$ruta]}")" sha "$(obtener_json "$solicitud" head.sha)" base_sha "$(obtener_json "$solicitud" base.sha)" criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")")
    for clave in schema repository sha base_sha criteria_sha256; do json_iguales "$(obtener_json "$evidencia" "$clave")" "$(obtener_json "$esperado" "$clave")" || fallar "$ruta" 'Evidencia obsoleta o de otro PR, base o criterio.'; done
    entradas=$(obtener_json "$evidencia" criteria)
    validar_detalles_criterios "$entradas" "$filas" || fallar "$ruta" 'La evidencia no cubre exactamente todos los criterios con explicaciones.'
    fuente=$(obtener_texto_json "$evidencia" source)
    [[ -z $fuente || $fuente == terminal ]] || fallar "$ruta" 'Fuente de evidencia desconocida.'
    if [[ $fuente == terminal ]]; then
        [[ $(tipo_json "$evidencia" local_tests) == array ]] || fallar "$ruta" 'La evidencia de terminal no registra las comprobaciones locales.'
    else
        while IFS= read -r entrada; do
            [[ $(tipo_json "$entrada" run) == number && $(obtener_texto_json "$entrada" run) =~ ^[0-9]+$ ]] || fallar "$ruta" 'Falta una ejecución válida en la evidencia.'
            ejecucion_exitosa "$ruta" "$(obtener_texto_json "$entrada" run)" "$(obtener_texto_json "$solicitud" head.sha)" "$flujo"
        done < <(elementos_json "$entradas")
    fi
    printf '%s' "$evidencia"
}

actualizar_cuerpo_criterios() {
    local cuerpo=$1 evidencia=$2 linea dentro=false seccion=false actualizado=''
    local apertura='^```tunning-evidence[[:space:]]*$' cierre='^```[[:space:]]*$' casilla='^- \[[ xX]\]' encabezado='^## Criterios de aceptación[[:space:]]*$'
    while IFS= read -r linea || [[ -n $linea ]]; do
        if [[ $dentro == false && $linea =~ $apertura ]]; then dentro=true; continue; fi
        if [[ $dentro == true ]]; then [[ $linea =~ $cierre ]] && dentro=false; continue; fi
        if [[ $linea =~ $encabezado ]]; then seccion=true
        elif [[ $linea == '## '* ]]; then seccion=false; fi
        if [[ $seccion == true && $linea =~ $casilla ]]; then linea="- [x]${linea:5}"; fi
        actualizado+="$linea"$'\n'
    done <<< "$cuerpo"
    while [[ $actualizado == *$'\n' ]]; do actualizado=${actualizado%$'\n'}; done
    printf '%s\n\n```tunning-evidence\n%s\n```\n' "$actualizado" "$evidencia"
}

gestionar_criterios() {
    local ruta=$PWD repositorio numero solicitud incidencia registro ejecucion filas entradas evidencia entrada nuevas='[]' cuerpo resultado
    repositorio=$(obtener_texto_json "$OPCIONES" repository); numero=$(obtener_texto_json "$OPCIONES" pr)
    [[ -n $repositorio && $numero =~ ^[1-9][0-9]*$ ]] || fallar "$ruta" 'Usa --repository owner/repo --pr N.'
    REPOSITORIO_GITHUB[$ruta]=$repositorio
    solicitud=$(api_github "$ruta" "pulls/$numero"); incidencia=$(incidencia_del_pr "$ruta" "$solicitud"); INCIDENCIA[$ruta]=$incidencia
    capturar_texto registro obtener_texto_json "$OPCIONES" record; ejecucion=$(obtener_texto_json "$OPCIONES" run)
    if [[ -n $registro ]]; then
        if [[ -n $ejecucion ]]; then ejecucion_exitosa "$ruta" "$ejecucion" "$(obtener_texto_json "$solicitud" head.sha)" .github/workflows/tests.yml; fi
        resultado=$(api_github "$ruta" "issues/$incidencia"); cuerpo=$(obtener_texto_json "$resultado" body); filas=$(extraer_criterios "$cuerpo" "$ruta")
        [[ -f $registro ]] || fallar "$ruta" 'No existe el archivo de detalles de criterios.'
        entradas=$(leer_documento_json "$registro"); validar_detalles_criterios "$entradas" "$filas" || fallar "$ruta" '--record exige una explicación verificable para cada criterio.'
        evidencia=$(objeto_json schema 1 repository "$(citar_json "$repositorio")" sha "$(obtener_json "$solicitud" head.sha)" base_sha "$(obtener_json "$solicitud" base.sha)" criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")")
        if [[ -z $ejecucion ]]; then
            evidencia=$(asignar_clave_json "$evidencia" source '"terminal"')
            evidencia=$(asignar_clave_json "$evidencia" local_tests '[]')
        fi
        while IFS= read -r entrada; do
            [[ -z $ejecucion ]] || entrada=$(asignar_clave_json "$entrada" run "$ejecucion")
            nuevas=$(agregar_json "$nuevas" "$entrada")
        done < <(elementos_json "$entradas")
        evidencia=$(asignar_clave_json "$evidencia" criteria "$nuevas")
        cuerpo=$(actualizar_cuerpo_criterios "$cuerpo" "$evidencia")
        api_github "$ruta" "issues/$incidencia" PATCH "$(objeto_json body "$(citar_json "$cuerpo")")" >/dev/null
    fi
    comprobar_criterios "$ruta" "$solicitud" "$incidencia" >/dev/null
    printf 'Criterios y evidencia OK: %s PR #%s, issue #%s, %s.\n' "$repositorio" "$numero" "$incidencia" "$(obtener_texto_json "$solicitud" head.sha)"
}

preparar_pr() {
    local ruta=$1 metadatos base predeterminada responsable incidencia existente estado recibo fusionada
    REPOSITORIO_GITHUB[$ruta]=$(nombre_repositorio_github "$ruta" "${REMOTO_PUBLICACION[$ruta]}")
    metadatos=$(api_github "$ruta")
    [[ $(obtener_texto_json "$metadatos" archived) != true && $(obtener_texto_json "$metadatos" permissions.push) == true ]] || fallar "$ruta" 'GitHub no permite publicar en este repositorio.'
    predeterminada=$(obtener_texto_json "$metadatos" default_branch); base=$(valor_configuracion "$ruta" tunning.prBase); base=${base:-$predeterminada}
    ejecutar_git "$ruta" check-ref-format "refs/heads/$base"
    [[ ${RAMA[$ruta]} != "$base" && ${RAMA[$ruta]} != "$predeterminada" ]] || fallar "$ruta" 'La rama activa es principal/base; prepara explícitamente una rama con git switch -c antes de syncPR.'
    BASE[$ruta]=$base; BASE_PREDETERMINADA[$ruta]=$predeterminada; SHA_BASE[$ruta]=$(consultar_sha_rama_github "$ruta" "$base"); METADATOS[$ruta]=$metadatos
    responsable=$(valor_configuracion "$ruta" tunning.responsible); responsable=${responsable:-${REPOSITORIO_GITHUB[$ruta]%%/*}}
    [[ $responsable =~ ^[A-Za-z0-9-]+$ ]] || fallar "$ruta" 'tunning.responsible debe ser un login de GitHub válido.'
    RESPONSABLE[$ruta]=$responsable; api_github "$ruta" "assignees/$responsable" >/dev/null
    incidencia=''
    if [[ $ruta == "$RAIZ" ]]; then incidencia=$(obtener_texto_json "$OPCIONES" issue); fi
    [[ -n $incidencia ]] || incidencia=$(valor_configuracion "$ruta" tunning.issue)
    if [[ -n $incidencia ]]; then
        [[ $incidencia =~ ^[1-9][0-9]*$ ]] || fallar "$ruta" 'El issue debe ser un entero positivo.'
        existente=$(api_github "$ruta" "issues/$incidencia"); estado=$(leer_estado "$ruta"); recibo=$(obtener_json "$estado" merged)
        fusionada=false
        if [[ $recibo != null && $(obtener_texto_json "$estado" issue) == "$incidencia" ]]; then
            recibo=$(api_github "$ruta" "pulls/$(obtener_texto_json "$recibo" pr)"); fusionada=$(obtener_texto_json "$recibo" merged)
        fi
        [[ $(obtener_json "$existente" pull_request) == null && ( $(obtener_texto_json "$existente" state) == open || $fusionada == true ) ]] || fallar "$ruta" "Issue #$incidencia no es un issue abierto."
        extraer_criterios "$(obtener_texto_json "$existente" body)" "$ruta" >/dev/null
    fi
    INCIDENCIA[$ruta]=$incidencia
}

publicar_pr() {
    local ruta=$1 identificador comparacion consulta existentes existente='' numero marca coincidencias='[]' incidencia detalle elemento hijo ruta_hija solicitud_hija hijos='[]' bloque cuerpo inicio fin estado clave borrador=true
    [[ $MODO != syncPRmerge ]] || borrador=false
    identificador=$(obtener_sha "$ruta"); SHA_BASE[$ruta]=$(consultar_sha_rama_github "$ruta" "${BASE[$ruta]}")
    comparacion=$(api_github "$ruta" "compare/$(codificar_url "${SHA_BASE[$ruta]}")...$(codificar_url "$identificador")")
    if [[ $(obtener_texto_json "$comparacion" ahead_by) == 0 || $(obtener_json "$comparacion" files '[]') == '[]' ]]; then printf '=> [%s] Sin diferencias con %s; no se crea PR.\n' "$(rotulo "$ruta")" "${BASE[$ruta]}"; return; fi
    consulta="state=open&head=$(codificar_url "${REPOSITORIO_GITHUB[$ruta]%%/*}:${RAMA[$ruta]}")&base=$(codificar_url "${BASE[$ruta]}")"
    existentes=$(paginas_github "$ruta" "pulls?$consulta")
    (($(longitud_json "$existentes") <= 1)) || fallar "$ruta" 'Hay varios PR abiertos para la misma rama/base.'
    if [[ $(longitud_json "$existentes") == 1 ]]; then
        existente=$(obtener_json "$existentes" 0); numero=$(incidencia_del_pr "$ruta" "$existente")
        if [[ -z ${INCIDENCIA[$ruta]} ]]; then INCIDENCIA[$ruta]=$numero
        else [[ ${INCIDENCIA[$ruta]} == "$numero" ]] || fallar "$ruta" 'El PR existente está asociado a otro issue.'; fi
    fi
    if [[ -z ${INCIDENCIA[$ruta]} ]]; then
        marca="<!-- tunning-branch:$(huella_texto "$(canonizar_json "$(agregar_json "$(agregar_json '[]' "$(citar_json "${RAMA[$ruta]}")")" "$(citar_json "${BASE[$ruta]}")")")") -->"
        while IFS= read -r elemento; do
            cuerpo=$(obtener_texto_json "$elemento" body)
            if [[ $(obtener_json "$elemento" pull_request) == null && $cuerpo == *"$marca"* ]]; then coincidencias=$(agregar_json "$coincidencias" "$elemento"); fi
        done < <(elementos_json "$(paginas_github "$ruta" 'issues?state=open')")
        (($(longitud_json "$coincidencias") <= 1)) || fallar "$ruta" 'Hay varios issues para la rama/base; configura tunning.issue.'
        if [[ $(longitud_json "$coincidencias") == 1 ]]; then incidencia=$(obtener_json "$coincidencias" 0)
        else
            cuerpo="$marca"$'\n\n## Criterios de aceptación\n\n- [ ] Comprobaciones acordadas aprobadas para el SHA vigente.\n- [ ] Cambios y referencias hijas revisados sin hallazgos pendientes.\n'
            detalle=$(objeto_json title "$(citar_json "Sincronizar ${RAMA[$ruta]} hacia ${BASE[$ruta]}")" assignees "$(agregar_json '[]' "$(citar_json "${RESPONSABLE[$ruta]}")")" body "$(citar_json "$cuerpo")")
            incidencia=$(api_github "$ruta" issues POST "$detalle")
        fi
        INCIDENCIA[$ruta]=$(obtener_texto_json "$incidencia" number)
    fi
    numero=${INCIDENCIA[$ruta]}
    detalle=$(objeto_json assignees "$(agregar_json '[]' "$(citar_json "${RESPONSABLE[$ruta]}")")")
    api_github "$ruta" "issues/$numero/assignees" POST "$detalle" >/dev/null
    while IFS= read -r hijo; do
        capturar_texto ruta_hija obtener_texto_json "$hijo" repo; solicitud_hija=${SOLICITUDES_CAMBIO[$ruta_hija]-}; solicitud_hija=${solicitud_hija:-'{}'}
        elemento=$(objeto_json path "$(obtener_json "$hijo" path)" repository "$(citar_json "${REPOSITORIO_GITHUB[$ruta_hija]}")" sha "$(citar_json "$(obtener_sha "$ruta_hija")")" pr "$(obtener_json "$solicitud_hija" number)")
        hijos=$(agregar_json "$hijos" "$elemento")
    done < <(elementos_json "${HIJOS[$ruta]}")
    bloque=$'<!-- tunning-sync:start -->\n'"Rama \`${RAMA[$ruta]}\` → \`${BASE[$ruta]}\`; SHA \`$identificador\`."$'\n\n'
    [[ -n $existente ]] || bloque+="Closes #$numero"$'\n\n'
    bloque+='Dependencias hijas: '; if [[ $hijos == '[]' ]]; then bloque+='ninguna'; else bloque+=$hijos; fi
    bloque+=$'\n\nLas comprobaciones locales y los criterios deben corresponder a este SHA y base.\n<!-- tunning-sync:end -->'
    if [[ -n $existente ]]; then
        cuerpo=$(obtener_texto_json "$existente" body); inicio='<!-- tunning-sync:start -->'; fin='<!-- tunning-sync:end -->'
        while [[ $cuerpo == *"$inicio"* ]]; do
            detalle=${cuerpo#*"$inicio"}; [[ $detalle == *"$fin"* ]] || fallar "$ruta" 'Bloque gestionado del PR incompleto.'
            cuerpo="${cuerpo%%"$inicio"*}${detalle#*"$fin"}"
        done
        cuerpo=${cuerpo%"${cuerpo##*[![:space:]]}"}
        if ! (incidencia_del_pr "$ruta" "$(objeto_json body "$(citar_json "$cuerpo")")" >/dev/null 2>&1); then cuerpo+=$'\n\n'"Closes #$numero"; fi
        cuerpo+=$'\n\n'"$bloque"
        elemento=$(api_github "$ruta" "pulls/$(obtener_texto_json "$existente" number)" PATCH "$(objeto_json body "$(citar_json "$cuerpo")")")
    else
        detalle=$(objeto_json head "$(citar_json "${RAMA[$ruta]}")" base "$(citar_json "${BASE[$ruta]}")" title "$(citar_json "Sincronizar ${RAMA[$ruta]}")" body "$(citar_json "$bloque")" draft "$borrador")
        elemento=$(api_github "$ruta" pulls POST "$detalle")
    fi
    api_github "$ruta" "issues/$(obtener_texto_json "$elemento" number)/assignees" POST "$(objeto_json assignees "$(agregar_json '[]' "$(citar_json "${RESPONSABLE[$ruta]}")")")" >/dev/null
    SOLICITUDES_CAMBIO[$ruta]=$elemento
    estado=$(leer_estado "$ruta")
    for clave in schema path repository branch base sha base_sha issue pr children responsible; do
        case $clave in
            schema) detalle=1 ;; path) detalle=$(citar_json "$ruta") ;; repository) detalle=$(citar_json "${REPOSITORIO_GITHUB[$ruta]}") ;;
            branch) detalle=$(citar_json "${RAMA[$ruta]}") ;; base) detalle=$(citar_json "${BASE[$ruta]}") ;;
            sha) detalle=$(citar_json "$identificador") ;; base_sha) detalle=$(citar_json "${SHA_BASE[$ruta]}") ;;
            issue) detalle=$numero ;; pr) detalle=$(obtener_json "$elemento" number) ;; children) detalle=$hijos ;;
            responsible) detalle=$(citar_json "${RESPONSABLE[$ruta]}") ;;
        esac
        estado=$(asignar_clave_json "$estado" "$clave" "$detalle")
    done
    if [[ ${RESULTADOS_COMPROBACIONES[$ruta]-[]} != '[]' ]]; then estado=$(asignar_clave_json "$estado" local_tests "$(objeto_json sha "$(citar_json "$identificador")" results "${RESULTADOS_COMPROBACIONES[$ruta]}")"); fi
    guardar_estado "$ruta" "$estado"
}

politica_pr() {
    local ruta=$1 nombre archivo permisos propietario politica elemento copia
    capturar_texto nombre valor_configuracion "$ruta" tunning.prPolicy
    if [[ -z $nombre ]]; then printf '{"checks":[],"reviewers":[]}'; return; fi
    capturar_texto archivo ruta_externa "$ruta" "$nombre" 'La política de PR'
    [[ -f $archivo ]] || fallar "$ruta" 'No existe la política de PR.'
    propietario=$(stat -c %u -- "$archivo"); permisos=$(stat -c %a -- "$archivo")
    [[ $propietario == "$(id -u)" ]] && (( (8#$permisos & 0022) == 0 )) || fallar "$ruta" 'La política debe pertenecer al usuario y no admitir escritura de grupo/otros.'
    copia=$(mktemp "$TEMPORALES/politica.XXXXXX"); cp -- "$archivo" "$copia"
    politica=$(leer_documento_json "$copia") || fallar "$ruta" 'La política no contiene JSON válido.'
    [[ $(tipo_json "$politica" checks) == array ]] || fallar "$ruta" 'La política necesita una lista checks (puede estar vacía).'
    while IFS= read -r elemento; do [[ $(tipo_json "$elemento") == string && -n $(obtener_texto_json "$elemento") ]] || fallar "$ruta" 'Nombre de check inválido en la política.'; done < <(elementos_json "$(obtener_json "$politica" checks)")
    if tiene_clave_json "$politica" reviewers; then
        [[ $(tipo_json "$politica" reviewers) == array ]] || fallar "$ruta" 'La lista de revisores debe ser un array.'
        while IFS= read -r elemento; do [[ $(tipo_json "$elemento") == string && -n $(obtener_texto_json "$elemento") ]] || fallar "$ruta" 'Revisor inválido en la política.'; done < <(elementos_json "$(obtener_json "$politica" reviewers)")
    fi
    printf '%s' "$politica"
}

comprobar_fusion() {
    local ruta=$1 solicitud=$2 politica=$3 comprobaciones estados elemento nombre valor observados='{}' revisiones revision usuario ultima aprobados='{}' revisor identificador
    [[ $(obtener_json "$solicitud" draft) != true && $(obtener_json "$solicitud" mergeable) == true ]] || fallar "$ruta" 'PR borrador, con conflicto o estado de integración sin resolver.'
    valor=$(obtener_texto_json "$solicitud" mergeable_state)
    [[ $valor == clean || $valor == unstable || $valor == has_hooks ]] || fallar "$ruta" 'PR borrador, con conflicto o estado de integración sin resolver.'
    identificador=$(obtener_texto_json "$solicitud" head.sha)
    comprobaciones=$(paginas_github "$ruta" "commits/$identificador/check-runs?filter=latest" check_runs)
    estados=$(paginas_github "$ruta" "commits/$identificador/statuses")
    while IFS= read -r elemento; do
        nombre=$(obtener_texto_json "$elemento" name)
        [[ $(obtener_texto_json "$elemento" status) == completed && $(obtener_texto_json "$elemento" conclusion) == success ]] || fallar "$ruta" 'Checks pendientes, fallidos, omitidos o ausentes; no se fusiona.'
        observados=$(asignar_clave_json "$observados" "$nombre" '"success"')
    done < <(elementos_json "$comprobaciones")
    local estados_recientes='{}'
    while IFS= read -r elemento; do
        nombre=$(obtener_texto_json "$elemento" context)
        if ! tiene_clave_json "$estados_recientes" "$nombre"; then estados_recientes=$(asignar_clave_json "$estados_recientes" "$nombre" "$(obtener_json "$elemento" state)"); fi
    done < <(elementos_json "$estados")
    while IFS= read -r elemento; do
        nombre=$(obtener_texto_json "$elemento" key); valor=$(obtener_texto_json "$elemento" value)
        [[ $valor == success ]] || fallar "$ruta" 'Checks pendientes, fallidos, omitidos o ausentes; no se fusiona.'
        observados=$(asignar_clave_json "$observados" "$nombre" '"success"')
    done < <(entradas_json "$estados_recientes")
    while IFS= read -r elemento; do nombre=$(obtener_texto_json "$elemento"); tiene_clave_json "$observados" "$nombre" || fallar "$ruta" "Faltan checks acordados: $nombre."; done < <(elementos_json "$(obtener_json "$politica" checks)")
    revisiones=$(paginas_github "$ruta" "pulls/$(obtener_texto_json "$solicitud" number)/reviews"); ultima='{}'
    while IFS= read -r revision; do
        valor=$(obtener_texto_json "$revision" state)
        if [[ $valor == APPROVED || $valor == CHANGES_REQUESTED || $valor == DISMISSED ]]; then
            usuario=$(obtener_texto_json "$revision" user.login); ultima=$(asignar_clave_json "$ultima" "$usuario" "$revision")
        fi
    done < <(elementos_json "$revisiones")
    while IFS= read -r elemento; do
        usuario=$(obtener_texto_json "$elemento" key); revision=$(obtener_json "$elemento" value); valor=$(obtener_texto_json "$revision" state)
        [[ $valor != CHANGES_REQUESTED ]] || fallar "$ruta" 'Hay una revisión de GitHub que solicita cambios.'
        if [[ $valor == APPROVED && $(obtener_texto_json "$revision" commit_id) == "$identificador" && $usuario != "$(obtener_texto_json "$solicitud" user.login)" ]]; then aprobados=$(asignar_clave_json "$aprobados" "$usuario" true); fi
    done < <(entradas_json "$ultima")
    while IFS= read -r revisor; do usuario=$(obtener_texto_json "$revisor"); tiene_clave_json "$aprobados" "$usuario" || fallar "$ruta" 'Faltan revisiones acordadas sobre el SHA actual.'; done < <(elementos_json "$(obtener_json "$politica" reviewers '[]')")
}

registrar_evidencia_terminal() {
    local ruta=$1 solicitud=$2 numero=$3 incidencia cuerpo filas fila resultado pruebas='[]' resumen evidencia entradas='[]' quien sha usuario_gh
    if (comprobar_criterios "$ruta" "$solicitud" "$numero" >/dev/null 2>&1); then return 0; fi
    sha=$(obtener_texto_json "$solicitud" head.sha)
    incidencia=$(api_github "$ruta" "issues/$numero"); cuerpo=$(obtener_texto_json "$incidencia" body); filas=$(extraer_criterios "$cuerpo" "$ruta")
    while IFS= read -r resultado; do
        [[ $(obtener_json "$resultado" returncode) == 0 ]] || fallar "$ruta" 'Hay comprobaciones locales fallidas; no se fusiona.'
        pruebas=$(agregar_json "$pruebas" "$(objeto_json argv "$(obtener_json "$resultado" argv)" returncode 0 log_sha256 "$(obtener_json "$resultado" log_sha256)")")
    done < <(elementos_json "${RESULTADOS_COMPROBACIONES[$ruta]-[]}")
    if [[ $pruebas == '[]' ]]; then resumen='sin comprobaciones locales configuradas (tunning.testCommands)'
    else resumen="$(longitud_json "$pruebas") comprobaciones locales aprobadas en este SHA antes del push"; fi
    quien="$(git -C "$ruta" config user.name || :) <$(git -C "$ruta" config user.email || :)>"
    usuario_gh=$(GH_PROMPT_DISABLED=1 gh api --hostname github.com user --jq .login 2>/dev/null || :)
    while IFS= read -r fila; do
        entradas=$(agregar_json "$entradas" "$(objeto_json id "$(obtener_json "$fila" 0)" detail "$(citar_json "Verificado en terminal por $quien${usuario_gh:+ (@$usuario_gh)} para $sha; $resumen.")")")
    done < <(elementos_json "$filas")
    evidencia=$(objeto_json schema 1 repository "$(citar_json "${REPOSITORIO_GITHUB[$ruta]}")" sha "$(citar_json "$sha")" base_sha "$(obtener_json "$solicitud" base.sha)" \
        criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")" source '"terminal"' \
        confirmed_by "$(objeto_json git "$(citar_json "$quien")" github "$(citar_json "$usuario_gh")" host "$(citar_json "$(id -un)@$(hostname)")" timestamp "$(citar_json "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")")" \
        local_tests "$pruebas" criteria "$entradas")
    api_github "$ruta" "issues/$numero" PATCH "$(objeto_json body "$(citar_json "$(actualizar_cuerpo_criterios "$cuerpo" "$evidencia")")")" >/dev/null
    printf '=> [%s] Issue #%s: criterios y evidencia de terminal registrados.\n' "$(rotulo "$ruta")" "$numero"
}

marcar_pr_listo() {
    local ruta=$1 solicitud=$2 numero
    [[ $(obtener_json "$solicitud" draft) == true ]] || return 0
    numero=$(obtener_texto_json "$solicitud" number)
    printf '=> [%s] Marcando PR #%s listo para revisión...\n' "$(rotulo "$ruta")" "$numero"
    (cd -- "$ruta" && GH_PROMPT_DISABLED=1 gh pr ready "$numero" --repo "github.com/${REPOSITORIO_GITHUB[$ruta]}") >/dev/null || fallar "$ruta" "No se pudo marcar el PR #$numero listo para revisión."
}

# Espera a que GitHub calcule mergeable y terminen los checks; no decide el resultado.
esperar_pr_fusionable() {
    local ruta=$1 numero=$2 limite inicio=$SECONDS solicitud identificador elemento nombre pendiente estados vistos
    limite=$(valor_configuracion "$ruta" tunning.mergeTimeout); limite=${limite:-600}
    [[ $limite =~ ^[1-9][0-9]*$ ]] || fallar "$ruta" 'tunning.mergeTimeout debe ser un entero positivo (segundos).'
    while :; do
        solicitud=$(api_github "$ruta" "pulls/$numero"); identificador=$(obtener_texto_json "$solicitud" head.sha); pendiente=
        if [[ $(obtener_json "$solicitud" mergeable) == null || $(obtener_texto_json "$solicitud" mergeable_state) == unknown ]]; then pendiente='GitHub calcula si el PR es fusionable'
        else
            while IFS= read -r elemento; do
                [[ $(obtener_texto_json "$elemento" status) == completed ]] || pendiente="check $(obtener_texto_json "$elemento" name)"
            done < <(elementos_json "$(paginas_github "$ruta" "commits/$identificador/check-runs?filter=latest" check_runs)")
            estados=$(paginas_github "$ruta" "commits/$identificador/statuses"); vistos='{}'
            while IFS= read -r elemento; do
                nombre=$(obtener_texto_json "$elemento" context); ! tiene_clave_json "$vistos" "$nombre" || continue
                vistos=$(asignar_clave_json "$vistos" "$nombre" true)
                [[ $(obtener_texto_json "$elemento" state) != pending ]] || pendiente="estado $nombre"
            done < <(elementos_json "$estados")
        fi
        if [[ -z $pendiente ]]; then printf '%s' "$solicitud"; return; fi
        (( SECONDS - inicio < limite )) || fallar "$ruta" "Tiempo de espera agotado (${limite}s): $pendiente. Repite git syncPRmerge."
        printf '=> [%s] Esperando %s...\n' "$(rotulo "$ruta")" "$pendiente" >&2
        sleep 5
    done
}

fusionar_arbol() {
    local ruta=$1 hijo ruta_hija referencias ruta_relativa estado recibo solicitud numero politica evidencia hijos_esperados metodo permiso resultado padres cantidad arbol_auditado fresca remotos esperado identificado
    local -a firma=()
    while IFS= read -r hijo; do capturar_texto ruta_hija obtener_texto_json "$hijo" repo; fusionar_arbol "$ruta_hija"; done < <(elementos_json "${HIJOS[$ruta]}")
    referencias=$(referencias_modulos "$ruta" true)
    while IFS= read -r hijo; do
        capturar_texto ruta_hija obtener_texto_json "$hijo" repo; capturar_texto ruta_relativa obtener_texto_json "$hijo" path
        if [[ $(obtener_texto_clave_json "$referencias" "$ruta_relativa") != "$(obtener_sha "$ruta_hija")" ]]; then sincronizar "$ruta"; fallar "$ruta" 'Las fusiones hijas cambiaron referencias: nuevo commit padre publicado; repite git syncPRmerge.'; fi
    done < <(elementos_json "${HIJOS[$ruta]}")
    estado=$(leer_estado "$ruta"); recibo=$(obtener_json "$estado" merged)
    if [[ ! ${SOLICITUDES_CAMBIO[$ruta]+presente} ]]; then
        if [[ $recibo != null ]]; then
            solicitud=$(api_github "$ruta" "pulls/$(obtener_texto_json "$recibo" pr)")
            [[ $(obtener_json "$solicitud" merged) == true && $(obtener_texto_json "$solicitud" merge_commit_sha) == "$(obtener_texto_json "$recibo" sha)" ]] || fallar "$ruta" 'El progreso guardado no coincide con una fusión real en GitHub.'
            asegurar_confirmacion "$ruta" "$(obtener_texto_json "$recibo" sha)" "${URL_PUBLICACION[$ruta]}"
            es_ancestro "$ruta" "$(obtener_texto_json "$recibo" sha)" "$(obtener_sha "$ruta")" || fallar "$ruta" 'El resultado de la fusión guardada no está integrado en la rama activa.'
            FUSIONADOS[$ruta]=$recibo
        fi
        return
    fi
    numero=$(obtener_texto_json "${SOLICITUDES_CAMBIO[$ruta]}" number); solicitud=$(api_github "$ruta" "pulls/$numero")
    [[ $(obtener_json "$solicitud" merged) != true ]] || fallar "$ruta" 'El PR ya fue fusionado fuera de esta ejecución; vuelve a sincronizar y validar su resultado.'
    [[ $(obtener_texto_json "$solicitud" head.sha) == "$(obtener_sha "$ruta")" && $(obtener_texto_json "$solicitud" base.ref) == "${BASE[$ruta]}" ]] || fallar "$ruta" 'El PR cambió de SHA/base después de publicarlo.'
    politica=$(politica_pr "$ruta")
    registrar_evidencia_terminal "$ruta" "$solicitud" "${INCIDENCIA[$ruta]}"
    evidencia=$(comprobar_criterios "$ruta" "$solicitud" "${INCIDENCIA[$ruta]}" "$(obtener_texto_json "$politica" workflow)")
    marcar_pr_listo "$ruta" "$solicitud"
    solicitud=$(esperar_pr_fusionable "$ruta" "$numero")
    [[ $(obtener_texto_json "$solicitud" head.sha) == "$(obtener_sha "$ruta")" && $(obtener_texto_json "$solicitud" base.sha) == "$(obtener_texto_json "$evidencia" base_sha)" ]] || fallar "$ruta" 'El PR cambió de SHA o base mientras se esperaba a GitHub; repite git syncPRmerge.'
    hijos_esperados=$(referencias_modulos "$ruta" true)
    comprobar_fusion "$ruta" "$solicitud" "$politica"
    metodo=$(obtener_texto_json "$politica" merge_method); [[ -n $metodo ]] || metodo=$(valor_configuracion "$ruta" tunning.mergeMethod)
    if [[ -z $metodo ]]; then
        metodo=merge
        if [[ $(obtener_json "${METADATOS[$ruta]}" allow_merge_commit) == false ]]; then
            if [[ $(obtener_json "${METADATOS[$ruta]}" allow_squash_merge) == true ]]; then metodo=squash
            elif [[ $(obtener_json "${METADATOS[$ruta]}" allow_rebase_merge) == true ]]; then metodo=rebase; fi
        fi
    fi
    case $metodo in merge) permiso=allow_merge_commit ;; squash) permiso=allow_squash_merge ;; rebase) permiso=allow_rebase_merge ;; *) fallar "$ruta" 'Método de merge no permitido por la política.' ;; esac
    [[ $(obtener_json "${METADATOS[$ruta]}" "$permiso") == true ]] || fallar "$ruta" 'Método de merge no permitido por GitHub.'
    identificado=$(obtener_texto_json "$solicitud" head.sha); esperado=$(obtener_texto_json "$solicitud" base.sha)
    if [[ $metodo == rebase ]]; then capturar_git "$ruta" resultado 0 rev-list --min-parents=2 "$esperado..$identificado"; [[ -z $resultado ]] || fallar "$ruta" 'Rebase necesita historia lineal del PR.'; fi
    capturar_git "$ruta" cantidad 0 rev-list --count "$esperado..$identificado"; capturar_git "$ruta" arbol_auditado 0 rev-parse 'HEAD^{tree}'
    comprobar_limpieza "$ruta"; fresca=$(api_github "$ruta" "pulls/$numero")
    remotos=$(referencias_remotas "$ruta" "${URL_PUBLICACION[$ruta]}" "refs/heads/${RAMA[$ruta]}" "refs/heads/${BASE[$ruta]}")
    [[ $(obtener_texto_json "$fresca" head.sha) == "$identificado" && $(obtener_texto_json "$fresca" base.sha) == "$esperado" && $(obtener_texto_clave_json "$remotos" "refs/heads/${RAMA[$ruta]}") == "$identificado" && $(obtener_texto_clave_json "$remotos" "refs/heads/${BASE[$ruta]}") == "$esperado" && $(obtener_sha "$ruta") == "$identificado" ]] || fallar "$ruta" 'HEAD/base/referencias cambiaron justo antes de fusionar; evidencia invalidada.'
    json_iguales "$(referencias_modulos "$ruta" true)" "$hijos_esperados" || fallar "$ruta" 'Las referencias cambiaron antes de fusionar.'
    resultado=$(api_github "$ruta" "pulls/$numero/merge" PUT "$(objeto_json sha "$(citar_json "$identificado")" merge_method "$(citar_json "$metodo")")")
    [[ $(obtener_json "$resultado" merged) == true && -n $(obtener_texto_json "$resultado" sha) ]] || fallar "$ruta" 'GitHub rechazó la fusión; los ancestros se detienen.'
    recibo=$(objeto_json pr "$numero" sha "$(obtener_json "$resultado" sha)" head_sha "$(citar_json "$identificado")" base_sha "$(citar_json "$esperado")")
    estado=$(asignar_clave_json "$(asignar_clave_json "$estado" merged "$recibo")" evidence "$evidencia"); guardar_estado "$ruta" "$estado"; FUSIONADOS[$ruta]=$recibo
    resultado=$(obtener_texto_json "$recibo" sha); asegurar_confirmacion "$ruta" "$resultado" "${URL_PUBLICACION[$ruta]}"
    capturar_git "$ruta" padres 0 log -1 --format=%P "$resultado"
    case $metodo in
        merge) [[ $padres == "$esperado $identificado" ]] || fallar "$ruta" 'La base o el contenido cambió durante la fusión remota; se guardó el resultado.' ;;
        squash) [[ $padres == "$esperado" ]] || fallar "$ruta" 'La base o el contenido cambió durante la fusión remota; se guardó el resultado.' ;;
        rebase) capturar_git "$ruta" padres 0 rev-parse "$resultado~$cantidad"; [[ $padres == "$esperado" ]] || fallar "$ruta" 'La base o el contenido cambió durante la fusión remota; se guardó el resultado.' ;;
    esac
    capturar_git "$ruta" padres 0 rev-parse "$resultado^{tree}"
    [[ $padres == "$arbol_auditado" ]] || fallar "$ruta" 'La base o el contenido cambió durante la fusión remota; se guardó el resultado.'
    if es_ancestro "$ruta" "$(obtener_sha "$ruta")" "$resultado"; then ejecutar_git "$ruta" merge --ff-only "$resultado"
    else [[ -z ${FIRMA[$ruta]} ]] || firma+=("${FIRMA[$ruta]}"); integrar "$ruta" "resultado $metodo de PR #$numero" merge --no-edit --no-autostash "${firma[@]}" "$resultado"; fi
    capturar_git "$ruta" padres 0 rev-parse 'HEAD^{tree}'; [[ $padres == "$arbol_auditado" ]] || fallar "$ruta" 'Integrar la fusión cambió el contenido auditado.'
    comprobar_limpieza "$ruta"; referencias=$(referencias_modulos "$ruta" true)
    while IFS= read -r hijo; do
        capturar_texto ruta_hija obtener_texto_json "$hijo" repo; capturar_texto ruta_relativa obtener_texto_json "$hijo" path
        verificar_referencia "$ruta_hija" "$(obtener_texto_clave_json "$referencias" "$ruta_relativa")" "$(obtener_json "$hijo" urls)"
    done < <(elementos_json "${HIJOS[$ruta]}")
    comprobar_antes_de_publicar "$ruta"; ejecutar_git "$ruta" push --recurse-submodules=check -- "${REMOTO_PUBLICACION[$ruta]}" "HEAD:refs/heads/${RAMA[$ruta]}"
    remotos=$(referencias_remotas "$ruta" "${URL_PUBLICACION[$ruta]}" "refs/heads/${RAMA[$ruta]}"); identificado=$(obtener_sha "$ruta")
    [[ $(obtener_texto_clave_json "$remotos" "refs/heads/${RAMA[$ruta]}") == "$identificado" ]] || fallar "$ruta" 'La rama de trabajo no coincide con su publicación tras integrar la fusión.'
    PUBLICADOS[$ruta]=$(agregar_json "$(agregar_json "$(agregar_json '[]' "$(citar_json "$identificado")")" "$(citar_json "${REMOTO_PUBLICACION[$ruta]}")")" "$(citar_json "${RAMA[$ruta]}")")
}
