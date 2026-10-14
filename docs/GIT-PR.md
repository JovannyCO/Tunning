# Git sync, PR y fusión revisada

[Guía de terminal](USO.md#git-sync)

Los tres alias usan una sola copia de [scripts/git-sync.sh](../scripts/git-sync.sh).
`git sync` conserva el flujo de equipo: confirma, integra, prueba en local y
publica; no usa la API de GitHub ni modifica issues. `git syncPR` añade issues y PR en borrador,
de hijos a padres, sin fusionarlos. `git syncPRmerge` prepara esos mismos PR y
solo fusiona cuando pasan los criterios, las pruebas y la auditoría independiente.

Las suites se ejecutan en la terminal antes del push. Si fallan, el comando
conserva el trabajo y se detiene para corregirlo. Tunning mantiene sus
comprobaciones en local, sin configuración `.github` ni estados de pruebas o
criterios enviados a GitHub. La evidencia de aceptación y la auditoría
independiente se validan también en la terminal antes de una fusión solicitada.
Los modos PR siguen usando GitHub para gestionar issues, PR, revisiones y las
demás reglas del repositorio.

En Tunning, [scripts/test-local.py](../scripts/test-local.py) comprueba
sintaxis/enlaces y reparte los tests entre procesos:

```bash
python3 scripts/test-local.py --jobs 8
```

Los alias detectan ese runner por repositorio. Para otras suites puedes fijar
`tunning.testCommands` con un array JSON de comandos y argumentos, como explica
la [guía de uso](USO.md#git-sync). La suite del padre no sustituye las pruebas
de sus submódulos. Reinstala el motor tras modificarlo con
`bash setup.sh --no-packages`.

Los modos PR necesitan GitHub CLI (`gh`) autenticado con permisos de contenido,
issues y PR. No instalan credenciales. La base predeterminada es la rama real
del repositorio en GitHub: en tus públicos suele ser `main`, y en los privados
`production`. Puedes elegir otra base con `git config tunning.prBase rama`.
Si estás en la principal o base, el comando se detiene antes de confirmar:
prepara una rama explícita, conservando tus commits y archivos.

```bash
git switch -c 123-describir-cambio
git syncPR "Describir el cambio" --issue 123
# En los hijos, tunning.issue permite elegir un issue ya existente.
git config tunning.issue 123
```

Sin `--issue`/`tunning.issue`, reutiliza el issue de la rama/base o crea uno
con criterios pendientes. Reutiliza el PR abierto, conserva su descripción,
publica las dependencias hijas y omite PR sin diferencias. Ni publicar ni
pasar tests permite inferir que se cumplió cada requisito escrito en un issue.
El responsable predeterminado es el propietario del repositorio. En los
proyectos de JovannyCO, los issues y PR se asignan a JovannyCO. Puedes fijarlo
con `git config --global tunning.responsible JovannyCO`; se añaden asignaciones
sin retirar otros responsables y se comprueba que GitHub permita asignarlo.

## Criterios con evidencia

Un issue necesita `## Criterios de aceptación` y casillas `- [ ]`/`- [x]`.
La comprobación local rechaza casillas pendientes y exige un bloque JSON
`tunning-evidence`: SHA del PR, SHA base, resumen de los criterios y explicación
por criterio vinculada a una auditoría local firmada y sus resultados.
Editar el código, la base o los criterios invalida la evidencia anterior.

Un responsable comprueba el contenido de cada criterio y prepara fuera del
checkout un array JSON: `[{"id":"A1","detail":"Comando, resultado y caso comprobado"}, ...]`.
Los IDs siguen el orden de las casillas de aceptación; deben cubrirlas todas.
Después de pasar las pruebas y obtener el informe independiente firmado del SHA
y base publicados, puede registrar esa evidencia y marcar las casillas:

```bash
python3 scripts/check-issue-criteria.py --repository JovannyCO/Tunning --pr 12 \
  --record /tmp/criterios-verificados.json --local-audit
python3 scripts/check-issue-criteria.py --repository JovannyCO/Tunning --pr 12
```

El registro no evalúa semánticamente las explicaciones: representa la revisión
explícita del responsable y comprueba la cobertura y el informe configurado en
`tunning.auditReport` con la política `tunning.prPolicy`. No crea pruebas ni
auditorías inexistentes. El informe incluye comandos, resultados y hashes de
logs; la evidencia vincula esos datos al SHA y base vigentes. No reutilices un
informe de otro commit ni inventes identidad, firma o resultados.

El registro actualiza el JSON de evidencia y las casillas del issue tras la
validación local del informe firmado. Una nueva publicación o una base distinta
exige repetir la validación. El motor bloquea la fusión si la evidencia no
corresponde al estado actual, aunque las pruebas hayan pasado.

Para Tunning, configura `checks: []` en la política porque todas sus suites se
ejecutan en local. Sus reglas de rama conservan las demás restricciones acordadas, como
la aplicación a administradores y la prohibición de force push. El motor no
modifica ni omite reglas remotas: una regla de otro repositorio que exija un
check sigue siendo obligatoria hasta que su responsable la cambie.

`--record ... --run ID` conserva compatibilidad histórica para repositorios que
usen CI. Esa opción no forma parte del flujo de Tunning ni reemplaza la
auditoría independiente para fusionar.

## Política de auditoría

Guarda la política y los informes fuera del checkout y del directorio Git.
Configura `tunning.prPolicy` con la ruta de un JSON que pertenezca al usuario
y no admita escritura de grupo/otros. Acuerda las suites y las identidades
antes de auditar; el código de un PR no debe poder modificar esta política.

```json
{
  "commands": [["python3", "scripts/test-local.py", "--jobs", "8"]],
  "checks": [],
  "merge_method": "merge",
  "reviewers": [],
  "auditors": {
    "FINGERPRINT_GPG_COMPLETO": {"provider": "anthropic", "identity": "Identidad verificada por el responsable"}
  }
}
```

El ejemplo acuerda suites locales sin checks de GitHub requeridos. Para otros
repositorios, una política aprobada puede acordar checks remotos, comandos y
revisores; no se cambia en silencio para hacer pasar un PR. El fingerprint y
las identidades del ejemplo son marcadores: reemplázalos por datos comprobados
antes de usar la política.

Registra el proveedor y sesión del implementador con
`tunning.implementerProvider` y `tunning.implementerSession`. El auditor usa
otro proveedor y sesión, firma su informe y no corrige código. Solo se aceptan
firmas GPG vigentes de fingerprints autorizados en la política local, usando
claves públicas previamente verificadas. La firma acredita el firmante; la
asociación de esa persona con un proveedor la establece el responsable al
autorizar la clave. No demuestra por sí sola qué modelo ejecutó una terminal.

El informe incluye SHA/base, referencias hijas, criterios, implementador,
auditor/entorno/sesión, comandos/resultados y hashes de logs, sin hallazgos.
`tunning.auditReport` apunta al informe; su firma separada usa el sufijo `.asc`.
Una aprobación escrita en texto libre o los tests del implementador no lo
sustituyen. No publiques logs con credenciales o datos privados.

En la terminal del auditor, después de revisar el código, genera el informe
con el mismo motor instalado. Este modo ejecuta solo las suites acordadas,
comprueba HEAD, bytes del índice y archivos propios/hijos antes y después,
y conserva incluso los informes fallidos; no confirma, publica ni corrige.

```bash
~/.local/bin/git-sync --tunning-mode=audit \
  --provider anthropic --session claude-terminal-2 --environment terminal-2 \
  --signing-key FINGERPRINT_GPG_COMPLETO --output /tmp/auditoria-sha.json --approve
git config tunning.auditReport /tmp/auditoria-sha.json
```

Si hay defectos, usa `--findings /tmp/hallazgos.json` (array JSON) en lugar de
`--approve` y entrega el resultado al implementador. Usa otra ruta para cada
informe; no sobrescribe informes ni firmas. El comando detecta cambios de
código pero no aísla procesos: las suites acordadas también deben ser de
lectura sobre el checkout. Conserva los cambios inesperados para su revisión.
El responsable autoriza la clave y el auditor declara el entorno/sesión;
la herramienta no certifica que se trate de otra máquina física.

## Fusión y reanudación

`git syncPRmerge` verifica pruebas y evidencia local, auditoría independiente,
revisiones acordadas, estado del PR, método permitido y SHA remoto/base
inmediatamente antes de la llamada a GitHub. En otros repositorios comprueba
también los checks remotos que exija su política.
Usa la condición `sha` del endpoint normal de merge; no emplea force ni
admin override. GitHub aplica las protecciones y reglas adicionales del repo.
No exige al autor autoaprobar su propio PR.
Los PR se crean en borrador: el responsable debe marcarlos listos para revisión
tras comprobar sus criterios. Un borrador siempre bloquea la fusión.

El progreso se guarda por repositorio en el directorio Git, en
`tunning-sync/state.json`. Las fusiones remotas son parciales: un fallo detiene
los ancestros, conserva las fusiones completadas y permite reanudar.
Un merge hijo suele crear otro commit; el implementador publica la referencia
actualizada del padre y se detiene para nuevas pruebas y auditoría del nuevo SHA.
Merge avanza la rama hija sin perder historia. Para squash/rebase, el motor
comprueba el árbol resultante e integra ese resultado en la rama activa con
un merge firmado, conservando los commits originales y publicándolo. El padre
referencia ese nuevo HEAD publicado, que contiene el resultado fusionado, y
necesita nueva evidencia/auditoría. Rebase exige historia lineal en el PR.

La API condiciona el HEAD, pero no ofrece una comparación atómica del SHA base:
si la base cambia durante la petición, se detecta al revisar los padres del
merge y se bloquean los ancestros; una fusión ya completada no se revierte.
Solo GitHub cierra los issues vinculados a PR efectivamente fusionados en su
rama predeterminada. El resumen diferencia publicaciones y fusiones completas
de una ejecución detenida.
