[![Guía de uso: instala tu terminal y conserva preferencias y respaldos](../assets/brand/guia-de-uso-terminal-tuning-jovanny-co-header.png)](#instalar-o-actualizar)

[Ir a la instalación →](#instalar-o-actualizar)

# Guía de Terminal Tuning: instalación, terminal y sincronización Git

[Volver a la portada](../README.md)

Configuración reproducible de los tres componentes de uso diario: **prompt Material MD3**, **`git sync`** y **`devup`**. Ubuntu 26 sobre WSL2 usa el prompt Bash de la terminal de referencia. Se conservan Starship, fastfetch y eza como opciones, y la variante de Google Cloud Shell sin iconos Nerd Font.

## Instalar o actualizar

En Ubuntu 26.04, con `bash` y `git` disponibles, clona este repo y ejecuta:

```bash
git clone https://github.com/JovannyCO/terminal-tuning.git
cd terminal-tuning
bash setup.sh
source ~/.bashrc
```

Puedes invocar `setup.sh` por ruta absoluta desde cualquier directorio. Detecta Ubuntu/WSL2 o Cloud Shell antes de instalar. Instala los paquetes base necesarios y copia los comandos y la configuración a tu usuario:

```text
~/.local/bin/devup
~/.local/bin/git-sync
~/.local/bin/git-pr.sh
~/.local/bin/git-json.sh
~/.config/tunning/bashrc_append.sh
~/.config/tunning/prompt-bash.sh
~/.config/tunning/settings.sh
```

Los comandos instalados son archivos independientes: mover o borrar el checkout no los rompe. El instalador integra un bloque en `.bashrc` y configura `git sync`, `git syncPR` y `git syncPRmerge` en `.gitconfig`, conservando la identidad, firma y demás ajustes existentes.

Para aplicar solo los archivos cuando ya tienes las dependencias, o inspeccionar primero los cambios:

```bash
bash setup.sh --no-packages
bash setup.sh --no-packages --dry-run
```

Cada actualización guarda los archivos reemplazados bajo `~/.local/state/tunning/backups/<fecha>/`, con sus rutas relativas y un `manifest.json`. Si hay un error al escribir los archivos, intenta restaurar los ya modificados. Una reinstalación sin cambios no duplica bloques ni crea nuevos respaldos. Los marcadores incompletos de `.bashrc` provocan un error antes de modificar la configuración.

Sin opciones nuevas conserva el prompt y los extras de `settings.sh`; la detección del entorno sigue siendo automática. El instalador lee únicamente preferencias literales conocidas, sin ejecutar ese archivo, y se detiene si contiene una configuración inválida. Las opciones explícitas cambian la selección.

`--target-dir /tmp/tunning-prueba --no-packages` prepara una instalación aislada sin cambiar `HOME`. Sirve para inspeccionar archivos; no activa esa configuración en tu sesión.

### Compatibilidad con instalaciones anteriores

**Terminal Tuning** es el nombre público del proyecto antes llamado **Tunning**.
La configuración conserva los identificadores históricos `tunning` para que las
instalaciones anteriores mantengan sus preferencias, respaldos y alias. Siguen
vigentes `~/.config/tunning`, `~/.local/state/tunning`, las opciones Git
`tunning.*`, las variables `TUNNING_*` y los marcadores de los bloques gestionados
en Bash y Git. El estado de sincronización sigue bajo `tunning-sync/` en el
directorio Git. La reinstalación utiliza esas mismas rutas y ajustes.

Para un checkout existente, comprueba `git remote -v` y actualiza `origin` según
el transporte que ya utilices. Si tienes SSH configurado:

```bash
git remote set-url origin git@github.com:JovannyCO/terminal-tuning.git
git remote -v
```

Para conservar HTTPS:

```bash
git remote set-url origin https://github.com/JovannyCO/terminal-tuning.git
git remote -v
```

GitHub normalmente redirige la URL anterior tras un renombre. Actualiza también
los enlaces que mantengas fuera del repositorio. Puedes conservar el nombre de
la carpeta de tu checkout y seguir usando tu rama actual. Después de actualizar
sus archivos, ejecuta `bash setup.sh --no-packages` para reinstalar las copias
de usuario. El renombre conserva identidad, autenticación, firma y preferencias.

## Apariencia y teclado

El prompt Bash muestra usuario/host en naranja, directorio en azul cian sobre gris, rama Git en teal, reloj a la derecha y `╰ ❯` en la segunda línea. La flecha cambia de verde a rojo cuando falla un comando.

| Rol | Color |
|---|---|
| Primario | `#FF6D00` |
| Secundario | `#00897B` |
| Terciario (azul cian) | `#02BCF9` |
| Superficie | `#1C1B1F` |
| Superficie variante | `#2B2930` |

Incluye los atajos de la terminal de referencia: flechas arriba/abajo para buscar en el historial por prefijo, Tab para recorrer completados y Shift+Tab para retroceder. Conserva la zona horaria del sistema en Ubuntu/WSL y el tipo de terminal declarado por el emulador.

Para activar también fastfetch y eza, o elegir el prompt Starship anterior:

```bash
bash setup.sh --extras
bash setup.sh --prompt starship
```

Starship activa también los extras. `--prompt bash` conserva los extras previamente activados. Para volver a Bash sin extras: `bash setup.sh --no-packages --prompt bash --no-extras`. Desactivar extras conserva sus binarios y archivos de configuración; deja de activarlos al abrir la terminal.

### Windows Terminal

1. Instala **JetBrainsMono Nerd Font Mono** en **Windows** desde [Nerd Fonts v3.4.0](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.4.0).
2. En el `settings.json` de Windows Terminal, añade el objeto interior `Material MD3` de [configs/windows_terminal_scheme.json](../configs/windows_terminal_scheme.json) al array `schemes`.
3. Añade las propiedades de [configs/windows_terminal_profile.json](../configs/windows_terminal_profile.json) al perfil `Ubuntu-26.04`, conservando sus campos de identificación. También puedes aplicarlas a `profiles.defaults` si quieres esa apariencia en todos los perfiles.

El perfil reproduce fuente tamaño 13, peso normal, opacidad 92, acrílico, márgenes `14, 10, 14, 10` y antialiasing `cleartype`. El instalador Linux no modifica Windows Terminal; Microsoft documenta los [esquemas](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes) y la [apariencia por perfil](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance).

En Ubuntu fuera de WSL, instala la misma fuente en el sistema que ejecuta tu emulador y selecciónala en sus preferencias.

## Git sync

```bash
git sync
git sync "Fix del botón de login"
```

El alias invoca la copia de [scripts/git-sync.sh](../scripts/git-sync.sh)
instalada en `~/.local/bin/git-sync`. Usa Bash, Git y las herramientas
básicas de Ubuntu. Los modos PR cargan [scripts/git-pr.sh](../scripts/git-pr.sh),
instalado junto al motor, y requieren `gh`; las auditorías firmadas requieren
GPG. [scripts/git-json.sh](../scripts/git-json.sh) procesa JSON en Bash y también
se instala junto al motor. Después de actualizar el checkout, ejecuta
`bash setup.sh --no-packages` para actualizar las copias instaladas.

`.brand` y los repositorios cuyo nombre comienza por `__` son dependencias
siempre de solo lectura para `git sync`, `git syncPR` y `git syncPRmerge`.
Los alias no los inicializan ni cambian su checkout, rama o configuración;
tampoco ejecutan commit, merge, fetch, push ni PR en ellos. Procesan el padre
conservando el SHA ya seleccionado por el usuario, que puede registrarse como
gitlink. Si se invocan dentro de uno de esos repositorios, se niegan a modificarlo.

1. Descubre los submódulos recursivamente, omite las dependencias de solo lectura y valida las ramas, los remotos, las preferencias y las operaciones pendientes del resto del árbol antes de crear commits. Inicializa los faltantes del resto en los commits registrados, sin usar `--remote` ni mover los checkouts existentes.
2. Procesa los hijos más profundos primero. Cada repositorio agrega sus archivos y referencias hijas con `git add -A`; si corresponde, crea un commit con formato `usuario@hostname 4octubre12:34 - mensaje`. El mensaje predeterminado es `Cambios en la matrix`; Cloud Shell usa `CSE` como hostname.
3. Integra mediante merge su rama remota y `production`, si existe y es otra rama, conservando los commits locales. Si un merge cambia los submódulos, vuelve a validar y sincronizar sus referencias antes de continuar.
4. Ejecuta las comprobaciones locales sobre el resultado que va a publicar. Si fallan, se detiene antes del push de ese repositorio; conserva los cambios para corregirlos y repetir la comprobación.
5. Comprueba que los commits hijos están disponibles en los remotos registrados y publica únicamente la rama de trabajo, también con [`--recurse-submodules=check`](https://git-scm.com/docs/git-push#Documentation/git-push.txt---recurse-submodulescheckon-demandonlyno). Establece un upstream cuando falta. Después, el padre confirma y publica las referencias de sus hijos ya publicados.

Cada repositorio procesado conserva su rama activa. Para un submódulo procesado con HEAD separado hace falta `submodule.<nombre>.branch` en `.gitmodules` o en la configuración del padre; la configuración local tiene prioridad y `branch=.` usa la rama del padre. Integra los commits separados y los de la rama configurada antes de asociar HEAD a esa rama. Si la configuración es ambigua o las historias no se pueden integrar con seguridad, indica la ruta y se detiene conservando el trabajo. Las dependencias de solo lectura quedan excluidas de estos requisitos y operaciones.

Los remotos se eligen con `branch.<rama>.remote`, `branch.<rama>.pushRemote` y `remote.pushDefault`, usando `origin` por defecto. El comando también publica commits pendientes con árbol limpio y ramas nuevas. No publica automáticamente `production` ni integra PR.

**Un error de staging, commit, firma, autenticación, merge, comprobaciones locales o push detiene el flujo con un código distinto de cero y la ruta afectada; sus padres no se publican.** Los conflictos quedan disponibles para resolverlos. El resumen muestra las ramas y commits publicados y, si hay un fallo posterior, identifica las publicaciones ya completadas como una sincronización incompleta.

En Ubuntu/WSL el instalador habilita `tunning.syncSign=true`: los nuevos commits y los merges creados por el comando se firman. En Cloud Shell su valor inicial es `false`, como en la variante anterior. Una preferencia `tunning.syncSign` ya existente se conserva.

```bash
# Preferencias opcionales
git config --global tunning.syncProduction false   # omitir la integración de production
git config --global tunning.syncSign false         # usar la política habitual commit.gpgsign
```

Puedes clonar este repositorio público por HTTPS para preparar una terminal sin tener SSH configurado. Para publicar después, configura tu nombre y correo, la autenticación del remoto y tu clave de firma. Comprueba los ajustes con `git config --get user.name`, `git config --get user.email` y `git config --get user.signingkey`. La configuración de shell establece `GPG_TTY` en sesiones interactivas.

`git sync` publica todos los archivos no ignorados de cada repositorio. Mantén credenciales, claves privadas y archivos `.env` fuera del control de versiones; `.gitignore` no protege archivos que ya están versionados. La firma verifica la autoría e integridad, pero no cifra los archivos. Consulta la [guía de GitHub para evitar publicar datos sensibles](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository#avoiding-accidental-commits-in-the-future).

Antes de sincronizar, revisa los archivos pendientes y el resumen de los cambios:

```bash
git status --short --ignore-submodules=none
git diff --stat
git diff --cached --stat
```

Para revisar también las ramas y los cambios propios de los submódulos ya inicializados, usa `git submodule foreach --recursive 'git status --short --branch'`.
Los modos `git syncPR` y `git syncPRmerge` añaden creación de PR y fusión
condicionada. Sus requisitos y evidencias están en la [guía de PR](GIT-PR.md).

Los tres modos ejecutan `scripts/verify.sh` cuando existe en el repositorio.
Puedes configurar `tunning.testCommands` para elegir las comprobaciones de un
proyecto; esa preferencia tiene prioridad. Su valor es un array JSON de
comandos, cada uno expresado como un array de argumentos. Se ejecutan en la raíz
de ese repositorio; no se interpretan como código de shell.
La lectura JSON rechaza claves duplicadas y caracteres NUL; estos últimos no
se pueden representar en argumentos de terminal.

```bash
git config tunning.testCommands '[["bash", "scripts/verify.sh"]]'
```

Configura las comprobaciones de cada proyecto y submódulo que las necesite antes
de publicar. Los repositorios sin verificador ni esta preferencia continúan
directamente con el push.

Esta configuración no elige una rama para los submódulos ni certifica las
comprobaciones de otro proyecto. Si cambias el checkout de Terminal Tuning, reinstala la copia
del motor antes de usar los alias. Los resultados se comprueban en local antes
de publicar; los modos PR usan GitHub para gestionar issues y PR y consultar sus
reglas. `git sync` conserva su flujo sin usar la API de GitHub.

## devup

[Scripts de actualización](../scripts/devup.sh) recuperados de la copia de trabajo y compartidos por ambos entornos:

```bash
devup          # pregunta: todo / ligero / no; espera hasta 15 segundos
devup -y       # apt update, upgrade y autoremove; después las CLI
devup -l       # solo Firebase mediante npm, codex update y claude update
devup --boot   # pregunta una vez por arranque, únicamente con entrada interactiva
```

Sin conexión, `--boot` lo intenta al abrir otra terminal. Varias terminales comparten el marcador de arranque; un bloqueo evita actualizaciones simultáneas. Si una actualización falla, las restantes se intentan y el comando termina con error y un resumen. Una actualización completa exitosa registra la fecha bajo `~/.cache/devup/` (o `XDG_CACHE_HOME`).

Las herramientas ausentes se omiten. `devup` no instala NVM, Codex ni Claude; Firebase se instala/actualiza cuando está disponible npm. La configuración carga NVM antes de invocar el actualizador. Usa `TUNNING_DEVUP_BOOT=0` para omitir la pregunta de arranque en una sesión.

## Google Cloud Shell

```bash
bash setup-cloudshell.sh
source ~/.bashrc
```

El instalador común también lo detecta con `bash setup.sh`. Una instalación nueva selecciona Starship y extras; las reinstalaciones conservan tu elección. Mantiene la inicialización de Google antes de la personalización, hostname `CSE`, fastfetch y eza sin iconos, y `America/Bogota` como zona predeterminada cuando `TZ` no está definida. También el prompt Bash de respaldo evita glifos Nerd Font.

Los tres binarios se instalan en `~/.local/bin`, con versiones y SHA256 oficiales fijados. Esa descarga está preparada para x86_64 y comprueba todos los archivos antes de instalarlos; conserva ejecutables de usuario existentes. La configuración y los comandos permanecen en HOME. Los temas y fuentes del navegador/editor requieren sus propias opciones: [compatibilidad y límites](COMPATIBILIDAD.md), [prompt de validación real](../promptTMP.md).

## Comprobaciones y documentación

```bash
bash scripts/verify.sh
```

Este verificador comprueba sintaxis Bash y JSON, incluidos los archivos JSONC
del proyecto con comentarios en líneas independientes. Comprueba enlaces y
anclas locales de Markdown fuera de bloques de código, y las cabeceras y
dimensiones de los PNG.
No analiza la sintaxis TOML ni sustituye una comprobación funcional de Starship.
Usa Bash, awk y herramientas básicas de Ubuntu, sin ejecutar instaladores
ni utilizar la red. Ejecuta las comprobaciones en local antes de publicar.
Terminal Tuning mantiene sus comprobaciones en la terminal, sin configuración `.github`
ni publicación de estados de pruebas o criterios en GitHub. La
[guía de PR](GIT-PR.md) explica cómo registrar evidencia local firmada y conservar
las demás protecciones remotas.

[VALIDACION-Ubuntu-26-WSL2.md](../VALIDACION-Ubuntu-26-WSL2.md) conserva el diagnóstico inicial y el estado de su reconciliación. [SETUP-Firebase-Ubuntu-26.md](../SETUP-Firebase-Ubuntu-26.md) documenta por separado WSL, Node y Firebase; sus versiones son una referencia histórica.

[![Cierre de la guía de uso: reinstala las copias y comprueba tu configuración](../assets/brand/guia-de-uso-terminal-tuning-jovanny-co-footer.png)](#comprobaciones-y-documentación)

[Revisar las comprobaciones →](#comprobaciones-y-documentación)
