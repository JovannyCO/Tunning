# Tunning — Terminal PRO

Configuración reproducible de los tres componentes de uso diario: **prompt Material MD3**, **`git sync`** y **`devup`**. Ubuntu 26 sobre WSL2 usa el prompt Bash de la terminal de referencia. Se conservan Starship, fastfetch y eza como opciones, y la variante de Google Cloud Shell sin iconos Nerd Font.

## Instalar o actualizar

En Ubuntu 26.04, con `git` y `python3` disponibles, clona este repo y ejecuta:

```bash
bash setup.sh
source ~/.bashrc
```

Puedes invocar `setup.sh` por ruta absoluta desde cualquier directorio. Detecta Ubuntu/WSL2 o Cloud Shell antes de instalar. Instala los paquetes base necesarios y copia los comandos y la configuración a tu usuario:

```text
~/.local/bin/devup
~/.local/bin/git-sync
~/.config/tunning/bashrc_append.sh
~/.config/tunning/prompt-bash.sh
~/.config/tunning/settings.sh
```

Los comandos instalados son archivos independientes: mover o borrar el checkout no los rompe. El instalador integra un bloque en `.bashrc` y configura `git sync` en `.gitconfig`, conservando la identidad, firma y demás ajustes existentes.

Para aplicar solo los archivos cuando ya tienes las dependencias, o inspeccionar primero los cambios:

```bash
bash setup.sh --no-packages
bash setup.sh --no-packages --dry-run
```

Cada actualización guarda los archivos reemplazados bajo `~/.local/state/tunning/backups/<fecha>/`, con sus rutas relativas y un `manifest.json`. Si hay un error al escribir los archivos, intenta restaurar los ya modificados. Una reinstalación sin cambios no duplica bloques ni crea nuevos respaldos. Los marcadores incompletos de `.bashrc` provocan un error antes de modificar la configuración.

`--target-dir /tmp/tunning-prueba --no-packages` prepara una instalación aislada sin cambiar `HOME`. Sirve para inspeccionar archivos; no activa esa configuración en tu sesión.

## Apariencia y teclado

El prompt Bash conserva los colores y la distribución actuales: usuario/host en naranja, directorio en gris, rama Git en teal, reloj a la derecha y `╰ ❯` en la segunda línea. La flecha cambia de verde a rojo cuando falla un comando.

| Rol | Color |
|---|---|
| Primario | `#FF6D00` |
| Secundario | `#00897B` |
| Superficie | `#1C1B1F` |
| Superficie variante | `#2B2930` |

Incluye los atajos de la terminal de referencia: flechas arriba/abajo para buscar en el historial por prefijo, Tab para recorrer completados y Shift+Tab para retroceder. Conserva la zona horaria del sistema en Ubuntu/WSL y el tipo de terminal declarado por el emulador.

Para activar también fastfetch y eza, o elegir el prompt Starship anterior:

```bash
bash setup.sh --extras
bash setup.sh --prompt starship
```

Starship activa también los extras. Para volver a la configuración Bash de referencia: `bash setup.sh --no-packages --prompt bash`.

### Windows Terminal

1. Instala **JetBrainsMono Nerd Font Mono** en **Windows** desde [Nerd Fonts v3.4.0](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.4.0).
2. En el `settings.json` de Windows Terminal, añade el objeto interior `Material MD3` de [configs/windows_terminal_scheme.json](configs/windows_terminal_scheme.json) al array `schemes`.
3. Añade las propiedades de [configs/windows_terminal_profile.json](configs/windows_terminal_profile.json) al perfil `Ubuntu-26.04`, conservando sus campos de identificación. También puedes aplicarlas a `profiles.defaults` si quieres esa apariencia en todos los perfiles.

El perfil reproduce fuente tamaño 13, peso normal, opacidad 92, acrílico, márgenes `14, 10, 14, 10` y antialiasing `cleartype`. El instalador Linux no modifica Windows Terminal; Microsoft documenta los [esquemas](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes) y la [apariencia por perfil](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance).

En Ubuntu fuera de WSL, instala la misma fuente en el sistema que ejecuta tu emulador y selecciónala en sus preferencias.

## Git sync

```bash
git sync
git sync "Fix del botón de login"
```

El alias instalado invoca una única implementación: [scripts/git-sync.sh](scripts/git-sync.sh).

1. Comprueba que hay una rama activa, remoto `origin` y ninguna operación Git pendiente.
2. Agrega todos los cambios del repositorio con `git add -A`.
3. Si hay cambios preparados, crea el commit con formato `usuario@hostname 4octubre12:34 - mensaje`. El mensaje predeterminado es `Cambios en la matrix`; Cloud Shell usa `CSE` como hostname.
4. Integra mediante merge la rama actual de `origin`, si existe, y `production`, si existe y es otra rama. No reescribe los commits locales con rebase.
5. Hace push de la rama actual y establece su upstream. También funciona sin cambios nuevos o con una rama que todavía no existe en el remoto.

**Un error de staging, commit, firma, conexión o merge detiene el flujo antes del push y devuelve un código distinto de cero.** Si un merge tiene conflictos, quedan disponibles para resolverlos; no se descartan cambios automáticamente.

En Ubuntu/WSL el instalador habilita `tunning.syncSign=true`: los nuevos commits y los merges creados por el comando se firman. En Cloud Shell su valor inicial es `false`, como en la variante anterior. Una preferencia `tunning.syncSign` ya existente se conserva.

```bash
# Preferencias opcionales
git config --global tunning.syncProduction false   # omitir la integración de production
git config --global tunning.syncSign false         # usar la política habitual commit.gpgsign
```

En una máquina nueva debes configurar tu nombre y correo, autenticar el acceso al remoto e importar/configurar tu clave de firma. Puedes comprobar los ajustes con `git config --get user.name`, `git config --get user.email` y `git config --get user.signingkey`. El repo no contiene credenciales ni claves privadas. La configuración de shell establece `GPG_TTY` en sesiones interactivas.

## devup

[Scripts de actualización](scripts/devup.sh) recuperados de la copia de trabajo y compartidos por ambos entornos:

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

El instalador común también lo detecta con `bash setup.sh`. Conserva la inicialización de Google antes de la personalización, Starship con hostname `CSE`, fastfetch y eza sin iconos, y `America/Bogota` como zona predeterminada cuando `TZ` no está definida. El panel de Cloud Shell Editor usa una lista fija de fuentes; esta variante conserva los símbolos Unicode estándar del repo.

Los binarios de Starship y eza se instalan en `~/.local/bin`; fastfetch mediante su paquete oficial. Esa descarga está preparada para x86_64. La configuración y los comandos de usuario permanecen en `~/`.

## Comprobaciones y documentación

```bash
python3 -m unittest discover -s tests -v
```

Las pruebas usan repositorios y remotos Git temporales locales, configuraciones aisladas y sustitutos de los actualizadores. No instalan paquetes, no actualizan herramientas reales y no publican cambios en servidores.

[VALIDACION-Ubuntu-26-WSL2.md](VALIDACION-Ubuntu-26-WSL2.md) conserva el diagnóstico inicial y el estado de su reconciliación. [SETUP-Firebase-Ubuntu-26.md](SETUP-Firebase-Ubuntu-26.md) documenta por separado WSL, Node y Firebase; sus versiones son una referencia histórica.
