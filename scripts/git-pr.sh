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

auditoria_criterios() {
    local ruta=$1 solicitud=$2 numero=$3 filas=$4 auditoria informe
    comprobar_limpieza "$ruta"
    [[ $(obtener_sha "$ruta") == "$(obtener_texto_json "$solicitud" head.sha)" ]] || fallar "$ruta" 'El checkout no corresponde al SHA vigente del PR.'
    INCIDENCIA[$ruta]=$numero
    auditoria=$(validar_auditoria "$ruta" "$solicitud" "$(politica_auditoria "$ruta")")
    informe=$(obtener_json "$auditoria" report)
    [[ $(obtener_texto_json "$informe" criteria_sha256) == "$(huella_criterios "$filas")" ]] || fallar "$ruta" 'La auditoría no cubre los criterios vigentes del issue.'
    printf '%s' "$auditoria"
}

comprobar_criterios() {
    local ruta=$1 solicitud=$2 numero=$3 flujo=${4:-.github/workflows/tests.yml} incidencia filas fila evidencia clave entradas entrada fuente auditoria
    incidencia=$(api_github "$ruta" "issues/$numero"); filas=$(extraer_criterios "$(obtener_texto_json "$incidencia" body)" "$ruta")
    while IFS= read -r fila; do [[ $(obtener_texto_json "$fila" 1) == true ]] || fallar "$ruta" "Issue #$numero: criterios pendientes: $(obtener_texto_json "$fila" 0)."; done < <(elementos_json "$filas")
    evidencia=$(extraer_evidencia "$(obtener_texto_json "$incidencia" body)" "$ruta")
    local esperado; esperado=$(objeto_json schema 1 repository "$(citar_json "${REPOSITORIO_GITHUB[$ruta]}")" sha "$(obtener_json "$solicitud" head.sha)" base_sha "$(obtener_json "$solicitud" base.sha)" criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")")
    for clave in schema repository sha base_sha criteria_sha256; do json_iguales "$(obtener_json "$evidencia" "$clave")" "$(obtener_json "$esperado" "$clave")" || fallar "$ruta" 'Evidencia obsoleta o de otro PR, base o criterio.'; done
    entradas=$(obtener_json "$evidencia" criteria)
    validar_detalles_criterios "$entradas" "$filas" || fallar "$ruta" 'La evidencia no cubre exactamente todos los criterios con explicaciones.'
    fuente=$(obtener_texto_json "$evidencia" source)
    [[ -z $fuente || $fuente == local-audit ]] || fallar "$ruta" 'Fuente de evidencia desconocida.'
    while IFS= read -r entrada; do
        if [[ $fuente == local-audit ]]; then
            [[ $(obtener_texto_json "$entrada" audit_report_sha256) == "$(obtener_texto_json "$evidencia" audit.report_sha256)" ]] || fallar "$ruta" 'La evidencia no corresponde al informe local registrado.'
        else
            [[ $(tipo_json "$entrada" run) == number && $(obtener_texto_json "$entrada" run) =~ ^[0-9]+$ ]] || fallar "$ruta" 'Falta una ejecución válida en la evidencia.'
            ejecucion_exitosa "$ruta" "$(obtener_texto_json "$entrada" run)" "$(obtener_texto_json "$solicitud" head.sha)" "$flujo"
        fi
    done < <(elementos_json "$entradas")
    if [[ $fuente == local-audit ]]; then
        auditoria=$(auditoria_criterios "$ruta" "$solicitud" "$numero" "$filas")
        esperado=$(objeto_json fingerprint "$(obtener_json "$auditoria" fingerprint)" report_sha256 "$(obtener_json "$auditoria" report_sha256)")
        json_iguales "$(obtener_json "$evidencia" audit)" "$esperado" || fallar "$ruta" 'La evidencia no corresponde a la auditoría local firmada vigente.'
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
    local ruta=$PWD repositorio numero solicitud incidencia registro ejecucion auditoria_local filas entradas evidencia auditoria entrada nuevas='[]' cuerpo fresca resultado
    repositorio=$(obtener_texto_json "$OPCIONES" repository); numero=$(obtener_texto_json "$OPCIONES" pr)
    [[ -n $repositorio && $numero =~ ^[1-9][0-9]*$ ]] || fallar "$ruta" 'Usa --repository owner/repo --pr N.'
    REPOSITORIO_GITHUB[$ruta]=$repositorio
    solicitud=$(api_github "$ruta" "pulls/$numero"); incidencia=$(incidencia_del_pr "$ruta" "$solicitud"); INCIDENCIA[$ruta]=$incidencia
    capturar_texto registro obtener_texto_json "$OPCIONES" record; ejecucion=$(obtener_texto_json "$OPCIONES" run); auditoria_local=$(obtener_texto_json "$OPCIONES" local_audit)
    if [[ -n $registro ]]; then
        if [[ $auditoria_local == true ]]; then [[ -z $ejecucion ]] || fallar "$ruta" '--record necesita --local-audit o --run, exclusivamente.'
        else [[ -n $ejecucion ]] || fallar "$ruta" '--record necesita --local-audit o --run, exclusivamente.'; ejecucion_exitosa "$ruta" "$ejecucion" "$(obtener_texto_json "$solicitud" head.sha)" .github/workflows/tests.yml; fi
        resultado=$(api_github "$ruta" "issues/$incidencia"); cuerpo=$(obtener_texto_json "$resultado" body); filas=$(extraer_criterios "$cuerpo" "$ruta")
        [[ -f $registro ]] || fallar "$ruta" 'No existe el archivo de detalles de criterios.'
        entradas=$(leer_documento_json "$registro"); validar_detalles_criterios "$entradas" "$filas" || fallar "$ruta" '--record exige una explicación verificable para cada criterio.'
        evidencia=$(objeto_json schema 1 repository "$(citar_json "$repositorio")" sha "$(obtener_json "$solicitud" head.sha)" base_sha "$(obtener_json "$solicitud" base.sha)" criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")")
        if [[ $auditoria_local == true ]]; then
            auditoria=$(auditoria_criterios "$ruta" "$solicitud" "$incidencia" "$filas")
            evidencia=$(asignar_clave_json "$evidencia" source '"local-audit"')
            evidencia=$(asignar_clave_json "$evidencia" audit "$(objeto_json fingerprint "$(obtener_json "$auditoria" fingerprint)" report_sha256 "$(obtener_json "$auditoria" report_sha256)")")
        fi
        while IFS= read -r entrada; do
            if [[ $auditoria_local == true ]]; then entrada=$(asignar_clave_json "$entrada" audit_report_sha256 "$(obtener_json "$auditoria" report_sha256)")
            else entrada=$(asignar_clave_json "$entrada" run "$ejecucion"); fi
            nuevas=$(agregar_json "$nuevas" "$entrada")
        done < <(elementos_json "$entradas")
        evidencia=$(asignar_clave_json "$evidencia" criteria "$nuevas")
        cuerpo=$(actualizar_cuerpo_criterios "$cuerpo" "$evidencia")
        api_github "$ruta" "issues/$incidencia" PATCH "$(objeto_json body "$(citar_json "$cuerpo")")" >/dev/null
    fi
    evidencia=$(comprobar_criterios "$ruta" "$solicitud" "$incidencia")
    if [[ $auditoria_local == true ]]; then
        [[ $(obtener_texto_json "$evidencia" source) == local-audit ]] || fallar "$ruta" '--local-audit exige evidencia de una auditoría local firmada.'
        fresca=$(api_github "$ruta" "pulls/$numero")
        [[ $(obtener_texto_json "$fresca" head.sha) == "$(obtener_texto_json "$solicitud" head.sha)" && $(obtener_texto_json "$fresca" base.sha) == "$(obtener_texto_json "$solicitud" base.sha)" ]] || fallar "$ruta" 'El PR cambió durante la validación; repite la evidencia local.'
    fi
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
    local ruta=$1 identificador comparacion consulta existentes existente='' numero marca coincidencias='[]' incidencia detalle elemento hijo ruta_hija solicitud_hija hijos='[]' bloque cuerpo inicio fin estado implementador clave
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
    bloque+=$'\n\nLas comprobaciones locales, los criterios y la auditoría deben corresponder a este SHA y base.\n<!-- tunning-sync:end -->'
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
        detalle=$(objeto_json head "$(citar_json "${RAMA[$ruta]}")" base "$(citar_json "${BASE[$ruta]}")" title "$(citar_json "Sincronizar ${RAMA[$ruta]}")" body "$(citar_json "$bloque")" draft true)
        elemento=$(api_github "$ruta" pulls POST "$detalle")
    fi
    api_github "$ruta" "issues/$(obtener_texto_json "$elemento" number)/assignees" POST "$(objeto_json assignees "$(agregar_json '[]' "$(citar_json "${RESPONSABLE[$ruta]}")")")" >/dev/null
    SOLICITUDES_CAMBIO[$ruta]=$elemento
    estado=$(leer_estado "$ruta")
    implementador=$(objeto_json provider "$(citar_json "$(valor_configuracion "$ruta" tunning.implementerProvider)")" session "$(citar_json "$(valor_configuracion "$ruta" tunning.implementerSession)")" identity "$(citar_json "$(git -C "$ruta" log -1 '--format=%an <%ae>')")")
    for clave in schema path repository branch base sha base_sha issue pr children responsible implementer; do
        case $clave in
            schema) detalle=1 ;; path) detalle=$(citar_json "$ruta") ;; repository) detalle=$(citar_json "${REPOSITORIO_GITHUB[$ruta]}") ;;
            branch) detalle=$(citar_json "${RAMA[$ruta]}") ;; base) detalle=$(citar_json "${BASE[$ruta]}") ;;
            sha) detalle=$(citar_json "$identificador") ;; base_sha) detalle=$(citar_json "${SHA_BASE[$ruta]}") ;;
            issue) detalle=$numero ;; pr) detalle=$(obtener_json "$elemento" number) ;; children) detalle=$hijos ;;
            responsible) detalle=$(citar_json "${RESPONSABLE[$ruta]}") ;; implementer) detalle=$implementador ;;
        esac
        estado=$(asignar_clave_json "$estado" "$clave" "$detalle")
    done
    if [[ ${RESULTADOS_COMPROBACIONES[$ruta]-[]} != '[]' ]]; then estado=$(asignar_clave_json "$estado" local_tests "$(objeto_json sha "$(citar_json "$identificador")" results "${RESULTADOS_COMPROBACIONES[$ruta]}")"); fi
    estado=$(quitar_clave_json "$estado" audit); guardar_estado "$ruta" "$estado"
}

politica_auditoria() {
    local ruta=$1 nombre archivo permisos propietario politica elemento copia
    capturar_texto nombre valor_configuracion "$ruta" tunning.prPolicy
    [[ -n $nombre ]] || fallar "$ruta" 'Falta tunning.prPolicy: política externa de comprobaciones e identidades auditoras.'
    capturar_texto archivo ruta_externa "$ruta" "$nombre" 'La política de auditoría'
    [[ -f $archivo ]] || fallar "$ruta" 'No existe la política de auditoría.'
    propietario=$(stat -c %u -- "$archivo"); permisos=$(stat -c %a -- "$archivo")
    [[ $propietario == "$(id -u)" ]] && (( (8#$permisos & 0022) == 0 )) || fallar "$ruta" 'La política debe pertenecer al usuario y no admitir escritura de grupo/otros.'
    copia=$(mktemp "$TEMPORALES/politica.XXXXXX"); cp -- "$archivo" "$copia"
    politica=$(leer_documento_json "$copia") || fallar "$ruta" 'La política no contiene JSON válido.'
    comandos_validos "$(obtener_json "$politica" commands)" || fallar "$ruta" 'La política debe acordar comandos como arrays de argumentos.'
    [[ $(tipo_json "$politica" checks) == array && $(tipo_json "$politica" auditors) == object && $(longitud_json "$(obtener_json "$politica" auditors)") -gt 0 ]] || fallar "$ruta" 'La política necesita checks y auditores autorizados.'
    while IFS= read -r elemento; do [[ $(tipo_json "$elemento") == string && -n $(obtener_texto_json "$elemento") ]] || fallar "$ruta" 'Nombre de check inválido en la política.'; done < <(elementos_json "$(obtener_json "$politica" checks)")
    if tiene_clave_json "$politica" reviewers; then
        [[ $(tipo_json "$politica" reviewers) == array ]] || fallar "$ruta" 'La lista de revisores debe ser un array.'
        while IFS= read -r elemento; do [[ $(tipo_json "$elemento") == string && -n $(obtener_texto_json "$elemento") ]] || fallar "$ruta" 'Revisor inválido en la política.'; done < <(elementos_json "$(obtener_json "$politica" reviewers)")
    fi
    asignar_clave_json "$politica" _sha256 "$(citar_json "$(huella_archivo "$copia")")"
}

validar_auditoria() {
    local ruta=$1 solicitud=$2 politica=$3 nombre archivo firma copia estado_firma errores huella cantidad=0 linea
    local informe identidad implementador auditor resultados resultado ordenes='[]' clave esperado
    local -a campos=()
    capturar_texto nombre valor_configuracion "$ruta" tunning.auditReport
    [[ -n $nombre ]] || fallar "$ruta" 'Falta tunning.auditReport: se requiere auditoría independiente firmada para este SHA.'
    capturar_texto archivo ruta_externa "$ruta" "$nombre" 'El informe'; firma="$archivo.asc"
    copia=$(mktemp "$TEMPORALES/informe.XXXXXX")
    if ! cp -- "$archivo" "$copia" || ! cp -- "$firma" "$copia.asc"; then fallar "$ruta" 'Firma de auditoría inválida: no se pudieron leer el informe y su firma.'; fi
    estado_firma=$(mktemp "$TEMPORALES/firma.XXXXXX"); errores=$(mktemp "$TEMPORALES/firma-error.XXXXXX")
    if ! gpg --batch --no-auto-key-retrieve --status-fd=1 --verify "$copia.asc" "$copia" >"$estado_firma" 2>"$errores"; then fallar "$ruta" 'Firma de auditoría inválida, expirada o revocada.'; fi
    while IFS= read -r linea; do
        case $linea in
            '[GNUPG:] VALIDSIG '*)
                read -r -a campos <<< "$linea"; cantidad=$((cantidad+1)); huella=${campos[2]}
                ((${#campos[@]} < 12)) || huella=${campos[-1]} ;;
            '[GNUPG:] EXPKEYSIG '*|'[GNUPG:] EXPSIG '*|'[GNUPG:] REVKEYSIG '*|'[GNUPG:] BADSIG '*|'[GNUPG:] ERRSIG '*) fallar "$ruta" 'Firma de auditoría inválida, expirada o revocada.' ;;
        esac
    done < "$estado_firma"
    [[ $cantidad == 1 && $huella =~ ^[A-Fa-f0-9]{40,64}$ ]] || fallar "$ruta" 'Firma de auditoría inválida, expirada o revocada.'
    huella=${huella^^}; identidad=$(obtener_clave_json "$(obtener_json "$politica" auditors)" "$huella")
    [[ $(tipo_json "$identidad") == object ]] || fallar "$ruta" 'El firmante no está autorizado por la política local de auditoría.'
    informe=$(leer_documento_json "$copia") || fallar "$ruta" 'El informe firmado no contiene JSON válido.'
    esperado=$(objeto_json schema 1 repository "$(citar_json "${REPOSITORIO_GITHUB[$ruta]}")" sha "$(citar_json "$(obtener_sha "$ruta")")" base_sha "$(obtener_json "$solicitud" base.sha)" children "$(referencias_modulos "$ruta" true)" pr "$(obtener_json "$solicitud" number)" issue "${INCIDENCIA[$ruta]}" policy_sha256 "$(obtener_json "$politica" _sha256)")
    for clave in schema repository sha base_sha children pr issue policy_sha256; do json_iguales "$(obtener_json "$informe" "$clave")" "$(obtener_json "$esperado" "$clave")" || fallar "$ruta" 'Auditoría obsoleta: cambió SHA, base, hijos, PR, issue o política.'; done
    implementador=$(obtener_json "$(leer_estado "$ruta")" implementer); auditor=$(obtener_json "$informe" auditor)
    [[ -n $(obtener_texto_json "$implementador" provider) && -n $(obtener_texto_json "$implementador" session) && -n $(obtener_texto_json "$identidad" provider) && -n $(obtener_texto_json "$identidad" identity) ]] || fallar "$ruta" 'Faltan identidades verificadas del implementador o auditor.'
    [[ $(obtener_json "$auditor" provider) == "$(obtener_json "$identidad" provider)" && $(obtener_json "$auditor" identity) == "$(obtener_json "$identidad" identity)" && -n $(obtener_texto_json "$auditor" session) && -n $(obtener_texto_json "$auditor" environment) && $(obtener_json "$auditor" provider) != "$(obtener_json "$implementador" provider)" && $(obtener_json "$auditor" session) != "$(obtener_json "$implementador" session)" ]] || fallar "$ruta" 'Se necesita un auditor autorizado de otro proveedor y sesión independiente.'
    json_iguales "$(obtener_json "$informe" implementer)" "$implementador" || fallar "$ruta" 'La identidad del implementador no coincide con el manifiesto vigente.'
    resultados=$(obtener_json "$informe" tests)
    [[ $(tipo_json "$resultados") == array ]] || fallar "$ruta" 'Faltan resultados de comprobaciones en el informe.'
    while IFS= read -r resultado; do
        ordenes=$(agregar_json "$ordenes" "$(obtener_json "$resultado" argv)")
        [[ $(obtener_json "$resultado" returncode) == 0 && $(obtener_texto_json "$resultado" log_sha256) =~ ^[a-f0-9]{64}$ ]] || fallar "$ruta" 'Auditoría con comprobaciones incompletas o fallidas.'
    done < <(elementos_json "$resultados")
    json_iguales "$ordenes" "$(obtener_json "$politica" commands)" || fallar "$ruta" 'Auditoría con comandos diferentes de los acordados.'
    [[ $(obtener_json "$informe" findings) == '[]' && $(obtener_json "$informe" unchanged) == true && $(obtener_json "$informe" review_approved) == true ]] || fallar "$ruta" 'Auditoría con hallazgos, cambios de código o revisión pendiente.'
    objeto_json fingerprint "$(citar_json "$huella")" report_sha256 "$(citar_json "$(huella_archivo "$copia")")" report "$informe"
}

ejecutar_auditoria() {
    local ruta=$1 estado politica salida proveedor sesion entorno clave hallazgos archivo_hallazgos identidad solicitud incidencia filas anterior posterior sin_cambios=false
    local resultados='[]' orden argumento directorio numero=0 codigo limite archivo_salida archivo_error archivo_registro huella resultado informe aprobado
    local -a argumentos=()
    export GIT_OPTIONAL_LOCKS=0
    estado=$(leer_estado "$ruta")
    [[ -n $(obtener_texto_json "$estado" pr) && -n $(obtener_texto_json "$estado" implementer.provider) ]] || fallar "$ruta" 'Primero el implementador debe publicar syncPR y registrar proveedor/sesión.'
    capturar_texto salida obtener_texto_json "$OPCIONES" output; capturar_texto proveedor obtener_texto_json "$OPCIONES" provider; capturar_texto sesion obtener_texto_json "$OPCIONES" session
    capturar_texto entorno obtener_texto_json "$OPCIONES" environment; clave=$(obtener_texto_json "$OPCIONES" signing_key); aprobado=$(obtener_texto_json "$OPCIONES" approve)
    capturar_texto archivo_hallazgos obtener_texto_json "$OPCIONES" findings
    [[ -n $salida && -n $proveedor && -n $sesion && -n $entorno && -n $clave ]] || fallar "$ruta" 'Auditoría: usa --output, --provider, --session, --environment y --signing-key.'
    [[ $aprobado == true || -n $archivo_hallazgos ]] || fallar "$ruta" 'Declara --approve tras revisar, o --findings con hallazgos.'
    capturar_texto salida ruta_externa "$ruta" "$salida" 'El informe'
    [[ ! -e $salida && ! -L $salida && ! -e $salida.asc && ! -L $salida.asc ]] || fallar "$ruta" 'El informe o su firma ya existen; usa otra ruta para conservar la evidencia.'
    politica=$(politica_auditoria "$ruta"); identidad=$(obtener_clave_json "$(obtener_json "$politica" auditors)" "${clave^^}")
    [[ $(obtener_texto_json "$identidad" provider) == "$proveedor" && -n $(obtener_texto_json "$identidad" identity) && $proveedor != "$(obtener_texto_json "$estado" implementer.provider)" && $sesion != "$(obtener_texto_json "$estado" implementer.session)" ]] || fallar "$ruta" 'La política no autoriza a este auditor independiente/proveedor/sesión.'
    REPOSITORIO_GITHUB[$ruta]=$(obtener_texto_json "$estado" repository); INCIDENCIA[$ruta]=$(obtener_texto_json "$estado" issue)
    solicitud=$(api_github "$ruta" "pulls/$(obtener_texto_json "$estado" pr)")
    [[ $(obtener_texto_json "$solicitud" merged) != true && $(obtener_texto_json "$solicitud" state) == open && $(obtener_sha "$ruta") == "$(obtener_texto_json "$estado" sha)" && $(obtener_texto_json "$solicitud" head.sha) == "$(obtener_texto_json "$estado" sha)" && $(obtener_texto_json "$solicitud" base.sha) == "$(obtener_texto_json "$estado" base_sha)" ]] || fallar "$ruta" 'El manifiesto/PR cambió antes de la auditoría.'
    comprobar_limpieza "$ruta"; incidencia=$(api_github "$ruta" "issues/${INCIDENCIA[$ruta]}"); filas=$(extraer_criterios "$(obtener_texto_json "$incidencia" body)" "$ruta")
    hallazgos='[]'
    if [[ -n $archivo_hallazgos ]]; then capturar_texto archivo_hallazgos ruta_externa "$ruta" "$archivo_hallazgos" 'Los hallazgos'; hallazgos=$(canonizar_json "$(leer_documento_json "$archivo_hallazgos")"); fi
    [[ $(tipo_json "$hallazgos") == array && ( $aprobado != true || $(longitud_json "$hallazgos") == 0 ) ]] || fallar "$ruta" 'Hallazgos debe ser un array; --approve requiere cero hallazgos.'
    limite=$(obtener_texto_json "$politica" timeout_seconds); limite=${limite:-600}
    [[ $limite =~ ^[1-9][0-9]*$ ]] || fallar "$ruta" 'El tiempo límite debe ser un entero positivo.'
    anterior=$(inventariar_repositorio "$ruta"); directorio=$(mktemp -d /tmp/tunning-audit-checks.XXXXXX)
    while IFS= read -r orden; do
        numero=$((numero+1)); argumentos=()
        while IFS= read -r argumento; do capturar_texto argumento obtener_texto_json "$argumento" ''; argumentos+=("$argumento"); done < <(elementos_json "$orden")
        archivo_salida="$directorio/$numero.stdout"; archivo_error="$directorio/$numero.stderr"; archivo_registro="$directorio/$numero.log"
        if (cd -- "$ruta" && timeout -- "$limite" "${argumentos[@]}") >"$archivo_salida" 2>"$archivo_error"; then codigo=0; else codigo=$?; fi
        if [[ $codigo == 124 ]]; then printf timeout >"$archivo_registro"
        else { cat -- "$archivo_salida"; printf '\n'; cat -- "$archivo_error"; } >"$archivo_registro"; fi
        huella=$(huella_archivo "$archivo_registro")
        resultado=$(objeto_json argv "$orden" returncode "$codigo" log_sha256 "$(citar_json "$huella")")
        resultados=$(agregar_json "$resultados" "$resultado")
    done < <(elementos_json "$(obtener_json "$politica" commands)")
    if posterior=$(inventariar_repositorio "$ruta") && json_iguales "$anterior" "$posterior"; then sin_cambios=true; fi
    informe=$(objeto_json schema 1 repository "$(obtener_json "$estado" repository)" sha "$(obtener_json "$estado" sha)" base_sha "$(obtener_json "$estado" base_sha)" children "$(referencias_modulos "$ruta" true)" pr "$(obtener_json "$estado" pr)" issue "$(obtener_json "$estado" issue)" criteria_sha256 "$(citar_json "$(huella_criterios "$filas")")" policy_sha256 "$(obtener_json "$politica" _sha256)" implementer "$(obtener_json "$estado" implementer)" auditor "$(objeto_json provider "$(citar_json "$proveedor")" session "$(citar_json "$sesion")" environment "$(citar_json "$entorno")" identity "$(obtener_json "$identidad" identity)")" tests "$resultados" findings "$hallazgos" unchanged "$sin_cambios" review_approved "${aprobado:-false}" timestamp "$(citar_json "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")")
    mkdir -p -- "${salida%/*}"
    (umask 077; set -o noclobber; printf '%s\n' "$informe" >"$salida") || fallar "$ruta" 'No se pudo crear el informe sin sobrescribir otro archivo.'
    if ! gpg --batch --local-user "$clave" --armor --detach-sign --output "$salida.asc" "$salida" >"$directorio/firma.stdout" 2>"$directorio/firma.stderr"; then fallar "$ruta" "No se pudo firmar el informe $salida; se conserva sin aprobar."; fi
    printf 'Informe de auditoría: %s; firma: %s.asc; sin cambios: %s; registros: %s.\n' "$salida" "$salida" "$sin_cambios" "$directorio"
    [[ $sin_cambios == true && $hallazgos == '[]' && $aprobado == true ]] || fallar "$ruta" 'Auditoría fallida; informe conservado.'
    while IFS= read -r resultado; do [[ $(obtener_json "$resultado" returncode) == 0 ]] || fallar "$ruta" 'Auditoría fallida; informe conservado.'; done < <(elementos_json "$resultados")
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

fusionar_arbol() {
    local ruta=$1 hijo ruta_hija referencias ruta_relativa estado recibo solicitud numero politica evidencia auditoria informe metodo permiso resultado padres cantidad arbol_auditado fresca remotos esperado identificado
    local -a firma=()
    while IFS= read -r hijo; do capturar_texto ruta_hija obtener_texto_json "$hijo" repo; fusionar_arbol "$ruta_hija"; done < <(elementos_json "${HIJOS[$ruta]}")
    referencias=$(referencias_modulos "$ruta" true)
    while IFS= read -r hijo; do
        capturar_texto ruta_hija obtener_texto_json "$hijo" repo; capturar_texto ruta_relativa obtener_texto_json "$hijo" path
        if [[ $(obtener_texto_clave_json "$referencias" "$ruta_relativa") != "$(obtener_sha "$ruta_hija")" ]]; then sincronizar "$ruta"; fallar "$ruta" 'Las fusiones hijas cambiaron referencias: nuevo commit padre publicado; necesita nuevas pruebas y auditoría antes de fusionar.'; fi
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
    politica=$(politica_auditoria "$ruta")
    evidencia=$(comprobar_criterios "$ruta" "$solicitud" "${INCIDENCIA[$ruta]}" "$(obtener_texto_json "$politica" workflow)")
    auditoria=$(validar_auditoria "$ruta" "$solicitud" "$politica"); informe=$(obtener_json "$auditoria" report)
    [[ $(obtener_texto_json "$informe" criteria_sha256) == "$(obtener_texto_json "$evidencia" criteria_sha256)" ]] || fallar "$ruta" 'La auditoría no cubre los criterios vigentes del issue.'
    comprobar_fusion "$ruta" "$solicitud" "$politica"
    metodo=$(obtener_texto_json "$politica" merge_method); metodo=${metodo:-merge}
    case $metodo in merge) permiso=allow_merge_commit ;; squash) permiso=allow_squash_merge ;; rebase) permiso=allow_rebase_merge ;; *) fallar "$ruta" 'Método de merge no permitido por la política.' ;; esac
    [[ $(obtener_json "${METADATOS[$ruta]}" "$permiso") == true ]] || fallar "$ruta" 'Método de merge no permitido por GitHub.'
    identificado=$(obtener_texto_json "$solicitud" head.sha); esperado=$(obtener_texto_json "$solicitud" base.sha)
    if [[ $metodo == rebase ]]; then capturar_git "$ruta" resultado 0 rev-list --min-parents=2 "$esperado..$identificado"; [[ -z $resultado ]] || fallar "$ruta" 'Rebase necesita historia lineal del PR.'; fi
    capturar_git "$ruta" cantidad 0 rev-list --count "$esperado..$identificado"; capturar_git "$ruta" arbol_auditado 0 rev-parse 'HEAD^{tree}'
    comprobar_limpieza "$ruta"; fresca=$(api_github "$ruta" "pulls/$numero")
    remotos=$(referencias_remotas "$ruta" "${URL_PUBLICACION[$ruta]}" "refs/heads/${RAMA[$ruta]}" "refs/heads/${BASE[$ruta]}")
    [[ $(obtener_texto_json "$fresca" head.sha) == "$identificado" && $(obtener_texto_json "$fresca" base.sha) == "$esperado" && $(obtener_texto_clave_json "$remotos" "refs/heads/${RAMA[$ruta]}") == "$identificado" && $(obtener_texto_clave_json "$remotos" "refs/heads/${BASE[$ruta]}") == "$esperado" && $(obtener_sha "$ruta") == "$identificado" ]] || fallar "$ruta" 'HEAD/base/referencias cambiaron justo antes de fusionar; evidencia invalidada.'
    json_iguales "$(referencias_modulos "$ruta" true)" "$(obtener_json "$informe" children)" || fallar "$ruta" 'Las referencias cambiaron antes de fusionar.'
    resultado=$(api_github "$ruta" "pulls/$numero/merge" PUT "$(objeto_json sha "$(citar_json "$identificado")" merge_method "$(citar_json "$metodo")")")
    [[ $(obtener_json "$resultado" merged) == true && -n $(obtener_texto_json "$resultado" sha) ]] || fallar "$ruta" 'GitHub rechazó la fusión; los ancestros se detienen.'
    recibo=$(objeto_json pr "$numero" sha "$(obtener_json "$resultado" sha)" head_sha "$(citar_json "$identificado")" base_sha "$(citar_json "$esperado")")
    estado=$(asignar_clave_json "$(asignar_clave_json "$estado" merged "$recibo")" audit "$auditoria"); guardar_estado "$ruta" "$estado"; FUSIONADOS[$ruta]=$recibo
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
