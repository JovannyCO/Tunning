[![Flujo Git y PR: publica con pruebas y revisa criterios antes de la fusión](../assets/brand/flujo-git-pr-terminal-tuning-jovanny-co-header.png)](#criterios-con-evidencia)

[Revisar los criterios →](#criterios-con-evidencia)

# Git sync, PR y fusión revisada

[Guía de terminal](USO.md#git-sync)

Los tres alias comparten [scripts/git-sync.sh](../scripts/git-sync.sh), escrito
en Bash y apoyado en Git y las herramientas básicas de Ubuntu. Sus módulos
[scripts/git-pr.sh](../scripts/git-pr.sh) y [scripts/git-json.sh](../scripts/git-json.sh)
se instalan junto al motor; el segundo procesa JSON en Bash.
`git sync` conserva el flujo de equipo: confirma, integra, comprueba en local y
publica; no usa la API de GitHub ni modifica issues. `git syncPR` añade issues y PR en borrador,
de hijos a padres, sin fusionarlos. `git syncPRmerge` prepara esos mismos PR,
registra la evidencia de pruebas locales en el issue y fusiona en la terminal.

Las comprobaciones se ejecutan en la terminal antes del push. Si fallan, el comando
conserva el trabajo y se detiene para corregirlo. Terminal Tuning mantiene sus
comprobaciones en local, sin configuración `.github` ni estados de pruebas o
criterios enviados a GitHub. La evidencia de aceptación se valida también en la
terminal antes de una fusión solicitada, sin depender de agentes de IA.
Los modos PR siguen usando GitHub para gestionar issues, PR, revisiones y las
demás reglas del repositorio.

## Decisiones de implementación

La lógica usa Bash 4.4, Git y las herramientas básicas de Ubuntu para que la
instalación y los tres alias se puedan revisar y ejecutar con las herramientas
de la terminal. El motor común conserva el mismo comportamiento de firmas,
ramas, remotos y submódulos en cada modo.

El módulo JSON trata las respuestas de GitHub, la configuración y la evidencia
como datos, conserva los argumentos literales y calcula huellas sobre una
representación uniforme de Unicode.

El [instalador Bash](../scripts/install.sh) actualiza juntos el motor y sus
módulos, con respaldos, escritura atómica y restauración ante errores. Así,
la terminal ejecuta la misma versión que se revisa en el checkout. Los nombres
propios de variables y funciones usan español de Colombia; los identificadores
de Git, GitHub y sus formatos conservan su contrato de compatibilidad.

En Terminal Tuning, [scripts/verify.sh](../scripts/verify.sh) comprueba
sintaxis Bash/JSON, enlaces locales y cabeceras y dimensiones PNG:

```bash
bash scripts/verify.sh
```

Los alias detectan ese verificador por repositorio. Puedes fijar
`tunning.testCommands` con un array JSON de comandos y argumentos para elegir
otras comprobaciones; esta preferencia tiene prioridad, como explica
la [guía de uso](USO.md#git-sync). Cada submódulo usa sus propias comprobaciones.
Un fallo bloquea el push. Reinstala el motor tras modificarlo con
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
por criterio vinculada a las comprobaciones locales de la terminal y sus resultados.
Editar el código, la base o los criterios invalida la evidencia anterior.

Durante `git syncPRmerge`, tras superar las comprobaciones locales antes del
push, el motor registra automáticamente la evidencia de terminal (`source: "terminal"`)
con los comandos ejecutados, códigos de retorno y hashes SHA256 de sus logs, y
marca las casillas del issue si aún no existía evidencia vigente para ese SHA.

Si deseas detallar manualmente la explicación de cada criterio, prepara fuera del
checkout un array JSON `[{"id":"A1","detail":"Comando, resultado y caso comprobado"}, ...]`
y regístralo:

```bash
bash scripts/check-issue-criteria.sh --repository JovannyCO/terminal-tuning --pr 12 \
  --record /tmp/criterios-verificados.json
bash scripts/check-issue-criteria.sh --repository JovannyCO/terminal-tuning --pr 12
```

Una nueva publicación o una base distinta exige actualizar la evidencia para el
nuevo SHA. El motor bloquea la fusión si la evidencia no corresponde al estado actual.

Para Terminal Tuning, las comprobaciones se ejecutan en la terminal (`bash scripts/verify.sh`),
sin requerir checks de GitHub Actions. El motor no modifica ni omite reglas
remotas: una regla de otro repositorio que exija un check sigue siendo
obligatoria hasta que su responsable la cambie.

`--record ... --run ID` conserva compatibilidad para repositorios que usen CI
en GitHub Actions.

## Política de auditoría

De forma predeterminada no se requiere archivo de política externa ni agentes de IA:
`git syncPRmerge` valida las comprobaciones locales configuradas en el repositorio,
la evidencia vigente del issue y el estado de integración del PR en GitHub.

Si un repositorio necesita exigir checks remotos específicos, revisores o un
método de integración fijo, configura `tunning.prPolicy` con la ruta de un JSON
fuera del checkout y del directorio Git que pertenezca al usuario y no admita
escritura de grupo/otros:

```json
{
  "checks": [],
  "merge_method": "merge",
  "reviewers": []
}
```

## Fusión y reanudación

`git syncPRmerge` se ejecuta íntegramente en la terminal (incluida Google Cloud
Shell) con Bash, Git y `gh` autenticado, sin depender de ningún agente de IA:

1. Sincroniza el árbol de hijos a padres, ejecuta las comprobaciones locales y
   publica cada rama de trabajo.
2. Crea o actualiza el issue de criterios y el PR listo para revisión (o marca
   listo un PR en borrador creado previamente con `git syncPR`).
3. Registra y verifica en el issue la evidencia `source: "terminal"` vinculada
   al SHA, al SHA base y a los resultados de las comprobaciones locales.
4. Espera a que GitHub calcule `mergeable` y terminen los checks pendientes
   (`tunning.mergeTimeout`, 600 s por defecto).
5. Verifica las condiciones de fusión (`mergeable`, estado limpio, ausencia de
   revisiones que soliciten cambios y `tunning.prPolicy` si se configuró) y
   fusiona usando la condición `sha` del endpoint normal de merge.
6. Integra el commit de fusión en la rama activa, ejecuta las comprobaciones
   locales y publica la rama actualizada.

```bash
gh auth login            # una vez; en Cloud Shell persiste en ~/.config/gh
git switch -c mi-rama    # syncPR* no trabajan sobre la rama base
git syncPRmerge "feat: cambio"
```

El método de integración puede fijarse con `tunning.mergeMethod` o en
`tunning.prPolicy`; si no se indica, se usa el primero permitido por el
repositorio (`merge`, `squash` o `rebase`). No emplea force ni admin override.

El progreso se guarda por repositorio en el directorio Git, en
`tunning-sync/state.json`. Las fusiones remotas son parciales: un fallo detiene
los ancestros, conserva las fusiones completadas y permite reanudar.
Si un merge hijo crea otro commit, el padre publica la referencia actualizada y
pide repetir `git syncPRmerge` para validar y fusionar el nuevo SHA.
Merge avanza la rama hija sin perder historia. Para squash/rebase, el motor
comprueba el árbol resultante e integra ese resultado en la rama activa con
un merge, conservando los commits originales y publicándolo. Rebase exige
historia lineal en el PR.

La API condiciona el HEAD, pero no ofrece una comparación atómica del SHA base:
si la base cambia durante la petición, se detecta al revisar los padres del
merge y se bloquean los ancestros; una fusión ya completada no se revierte.
Solo GitHub cierra los issues vinculados a PR efectivamente fusionados en su
rama predeterminada. El resumen diferencia publicaciones y fusiones completas
de una ejecución detenida.

[![Cierre del flujo de PR: relaciona el SHA y la base con evidencia y auditoría vigentes](../assets/brand/flujo-git-pr-terminal-tuning-jovanny-co-footer.png)](#política-de-auditoría)

[Consultar la auditoría →](#política-de-auditoría)
