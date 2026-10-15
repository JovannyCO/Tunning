[![La terminal bajo revisión: evidencias, faltantes y reconciliación de Ubuntu y WSL2](assets/brand/diagnostico-ubuntu-26-wsl2-jovanny-co-header.png)](#diagnóstico-inicial)

[Leer el diagnóstico →](#diagnóstico-inicial)

# Validación y reconciliación de la terminal actual

Fecha: 2026-10-04.

## Código reconciliado — 2026-10-04

Se incorporaron el prompt Bash activo, sus ajustes de teclado, `devup`, una implementación compartida de `git sync` y el perfil visual de Windows Terminal. El instalador común copia los comandos sin enlaces al checkout, respalda los archivos existentes, comprueba los marcadores y conserva la zona horaria de Ubuntu/WSL. Las variantes Starship y Cloud Shell siguen disponibles.

Las comprobaciones de la reconciliación cubrieron Git con remotos locales, fallos de firma y conflictos, instalación y reinstalación, conservación de preferencias, `devup` con actualizadores simulados y el prompt. El diagnóstico siguiente documenta el estado **anterior** a esas correcciones. Sigue pendiente certificar una instalación completa en una distribución WSL recién creada; identidad, credenciales y claves se restauran por separado.

## Diagnóstico inicial

**Resultado inicial: este checkout no contenía todo lo necesario para reconstruir la terminal actual.** Tenía parte de la apariencia y un instalador compatible con los paquetes de Ubuntu 26, pero faltaban la configuración Bash activa, `devup` y ajustes de Windows Terminal. Además, `git sync` no detenía el flujo ante errores.

Repositorio auditado: `~/projects/open/Tunning`, rama `Ubuntu26`, commit `3c9ae4d`. Al iniciar, el árbol de trabajo estaba limpio. La rama estaba seis commits por delante de su referencia local `origin/Ubuntu26`; no se hizo `fetch`, por lo que esto no certifica el estado actual del servidor.

## Entorno comprobado

| Componente | Evidencia local |
|---|---|
| Windows | Microsoft Windows 11 Pro, edición Professional, 26H2, compilación 26300; consulta de Windows mediante PowerShell |
| Distribución | Ubuntu 26.04.1 LTS, `resolute`; `/etc/os-release` |
| WSL | `wsl.exe --list --verbose`: `Ubuntu-26.04`, versión 2 |
| Kernel | `6.18.33.2-microsoft-standard-WSL2`, x86_64 |
| Shell | Bash, `/bin/bash` |
| Prompt configurado | Funciones de apariencia en `~/.bashrc`, ejecutadas mediante `PROMPT_COMMAND` |
| Starship / fastfetch / eza | No instalados en el entorno inspeccionado |
| Zona horaria | `America/New_York`, mediante `/etc/localtime`; `TZ` no definido en la sesión de inspección |
| Windows Terminal | Esquema Material MD3; fuente JetBrainsMono Nerd Font Mono, tamaño 13, peso normal; opacidad 92, acrílico activo, padding `14, 10, 14, 10`, antialiasing `cleartype` |

El perfil `Ubuntu-26.04` hereda esos ajustes de `profiles.defaults`. Se encontraron archivos JetBrainsMono Nerd Font en la carpeta de fuentes del usuario de Windows. No se hizo una comprobación visual de los glifos.

## Cobertura y faltantes

### 1. El prompt actual no está versionado en este checkout

El prompt activo está definido en `~/.bashrc:16–99`. En cambio, [setup.sh](setup.sh) instala Starship y [configs/bashrc_append.sh](configs/bashrc_append.sh) lo inicializa en la línea 142. Reconstruir con estos archivos produciría una configuración diferente de la actual.

También faltan los bindings actuales de Readline: búsqueda del historial con las flechas y completado con Tab/Shift+Tab (`~/.bashrc:126–134`). La inicialización de `GPG_TTY` de la sesión actual tampoco está incluida.

**Pendiente:** versionar una configuración reutilizable del prompt Bash y de esos ajustes, con una integración que no dependa del contenido exclusivo de este equipo.

### 2. `devup` depende de otra copia y de un archivo sin seguimiento

El comando actual es este enlace:

```text
~/.local/bin/devup
  -> ~/projects/work/Tunning/scripts/devup.sh
```

En `~/projects/open/Tunning` no hay script, instalación, integración de arranque ni documentación de `devup`. En la otra copia, `git status` muestra `scripts/` sin seguimiento y cambios locales en `README.md`, `setup.sh` y `configs/bashrc_append.sh`. El arranque actual lo invoca desde `~/.bashrc:139–140`.

**Pendiente:** incorporar el script y su instalación al repo que se vaya a conservar, incluir la llamada `devup --boot` y documentar sus dependencias. Un clon no recuperaría el archivo actualmente sin seguimiento. No se ejecutaron las actualizaciones de `devup`.

### 3. `git sync` continúa después de errores

En [setup.sh](setup.sh), líneas 113–124, los `;` separan partes de la secuencia que deberían detenerse si falla un paso. El `git push origin HEAD` final se ejecuta independientemente del resultado del commit o de los pulls.

Resultados comprobados:

| Caso | Resultado |
|---|---|
| Fallo simulado de `git add` | Continúa hasta `push`; termina con código 0 si el push simulado tiene éxito |
| Fallo simulado de `git commit` | Continúa con pull y push; termina con código 0 |
| Fallo simulado del pull de la rama actual | Ejecuta push; termina con código 0 |
| Fallo simulado del pull de `production` | Ejecuta push; termina con código 0 |
| Git real, hook que rechaza el commit, remoto local temporal | Ejecuta push, devuelve 0 y deja los cambios sin commit |

El alias activo en `~/.gitconfig` también difiere del instalador: usa `git commit -S` y hace pull de `production` sin comprobar primero si existe. La configuración actual tiene identidad y firma de commits habilitadas; el repo no proporciona un procedimiento completo para reconstruirlas. El ejemplo manual del README, además, fija el hostname a `CSE`.

**Pendiente:** corregir el control de errores, definir el comportamiento de pull/`production` y documentar la configuración de identidad, autenticación y firma con credenciales externas al repo. El alias debe devolver error si falla una operación necesaria.

### 4. Windows Terminal solo está cubierto parcialmente

El contenido interior de [configs/windows_terminal_scheme.json](configs/windows_terminal_scheme.json) **coincide exactamente** con el esquema Material MD3 instalado. Faltan los ajustes de fuente, tamaño, opacidad, acrílico, márgenes y antialiasing indicados arriba.

El archivo del repo envuelve el esquema bajo la clave `Material MD3`. Para importarlo, el objeto interior debe añadirse al array `schemes` y referenciarse desde el perfil o sus valores predeterminados. Ese formato está documentado por [Microsoft](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes); los ajustes de fuente y apariencia pertenecen al [perfil de Windows Terminal](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance).

El README sí menciona la instalación manual de la fuente en Windows, pero `setup.sh` instala fuentes dentro de Linux y termina con instrucciones de GNOME Terminal. No restaura la configuración del emulador de Windows.

**Pendiente:** añadir una plantilla de apariencia del perfil Ubuntu y pasos de importación o un instalador que conserve los demás perfiles. Unificar también la versión de Nerd Fonts: el script descarga 3.2.1 y el README menciona 3.4.0.

### 5. El instalador necesita ajustes para una reconstrucción fiable

| Hallazgo | Evidencia / efecto |
|---|---|
| Depende del directorio desde el que se ejecuta | Usa `configs/...` relativo al directorio de trabajo. La prueba desde otro directorio falló buscando `configs/starship.toml`, después de las llamadas simuladas a APT |
| No valida la plataforma | Lee y muestra `/etc/os-release`, pero no comprueba Ubuntu 26 ni WSL2 antes de instalar. Los dos instaladores se seleccionan manualmente |
| Dependencias implícitas | Usa `git`, `fc-list` y `fc-cache`, pero no instala explícitamente `git` ni `fontconfig`. Están presentes en esta máquina; los paquetes consultados no los declaran como dependencias directas |
| Sin respaldo de configuraciones existentes | Sobrescribe los archivos de Starship y fastfetch y actualiza `.bashrc` sin guardar una copia |
| Marcador de cierre ausente | Si existe el marcador inicial de Tunning pero falta el final, el `sed` elimina el contenido restante de `.bashrc`. Se reprodujo la pérdida de una línea ajena al bloque en una copia temporal |
| Cambio de zona horaria | `configs/bashrc_append.sh:128` fuerza `America/Bogota`; no reproduce la zona actual `America/New_York` |

La reinstalación normal, con ambos marcadores válidos, sí conservó el contenido exterior y dejó un único bloque Tunning después de dos ejecuciones simuladas.

### 6. WSL y herramientas de desarrollo tienen documentación parcial

[SETUP-Firebase-Ubuntu-26.md](SETUP-Firebase-Ubuntu-26.md) incluye una configuración `.wslconfig` cuyos valores coinciden con la actual: 20 GB de RAM, 8 procesadores, 6 GB de swap, red mirrored, DNS tunneling, firewall y recuperación gradual de memoria. El ejemplo de `/etc/wsl.conf` cubre systemd e interoperabilidad; no incluye el usuario predeterminado configurado en este equipo.

Estos archivos requieren pasos fuera del instalador de apariencia. Microsoft distingue la [configuración global de WSL y la configuración por distribución](https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

La guía contiene instalación manual de NVM/Node y Firebase, pero las referencias `master`, `--lts` y versiones no fijadas no garantizan recuperar las mismas versiones. No se validó la reinstalación completa de ese stack, de sus sesiones autenticadas ni de los servicios de los proyectos.

## Comprobaciones realizadas

- Sintaxis Bash correcta en `setup.sh`, `setup-cloudshell.sh` y `configs/bashrc_append.sh`.
- Lectura TOML correcta de las dos configuraciones Starship y JSON correcto de las tres configuraciones JSON/JSONC. Esto verifica sintaxis; no certifica el comportamiento de los programas.
- APT local ofrece `fastfetch 2.57.1+dfsg-1ubuntu1`, `eza 0.23.4-1ubuntu1` y `starship 1.22.1-9ubuntu1` desde `resolute/universe`.
- `apt-get --simulate install fastfetch eza starship curl unzip tar` resolvió las dependencias sin errores; no instaló paquetes.
- Tres escenarios del instalador en destinos temporales: reinstalación, invocación desde otro directorio y marcador incompleto. Se redirigieron únicamente las referencias de destino `$HOME` en una copia temporal; `sudo` se sustituyó por un registrador y se simuló la fuente ya instalada. No se ejecutaron descargas ni cambios de sistema.
- Cuatro simulaciones de fallos de Git y una reproducción con Git real usando exclusivamente repositorios temporales y un remoto local.
- Comparación de hashes antes/después: `~/.bashrc`, `~/.gitconfig` y `settings.json` de Windows Terminal permanecieron idénticos.

No se ejecutó el instalador sobre el entorno real ni una instalación completa en una distribución limpia. Esta auditoría demuestra faltantes y errores concretos; no certifica todavía una reconstrucción completa.

## Trabajo necesario para dar la reconstrucción por validada

1. Consolidar en este repo el prompt Bash, Readline y `devup` que usa la terminal actual.
2. Corregir `git sync` y documentar cómo restablecer identidad, autenticación y firma.
3. Incorporar la apariencia del perfil Windows Terminal y su procedimiento de restauración.
4. Ajustar el instalador: detección de entorno, rutas independientes del directorio de trabajo, dependencias explícitas, respaldos y conservación de la zona horaria.
5. Probar instalación y reinstalación en una Ubuntu 26 limpia sobre WSL2 y comparar el resultado con la configuración aquí inventariada.

La primera entrega añadió únicamente este diagnóstico. La sección «Código reconciliado» y el README describen las correcciones posteriores y el procedimiento vigente.

[![La evidencia fija el siguiente paso: queda probar la reconstrucción en una WSL limpia](assets/brand/diagnostico-ubuntu-26-wsl2-jovanny-co-footer.png)](#trabajo-necesario-para-dar-la-reconstrucción-por-validada)

[Revisar el trabajo necesario →](#trabajo-necesario-para-dar-la-reconstrucción-por-validada)
