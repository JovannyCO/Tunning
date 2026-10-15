# Prompt temporal: comprobar Terminal Tuning en Google Cloud Shell

Copia el texto de abajo en tu agente de IA **dentro de Google Cloud Shell**.
Es una instrucción para el agente, no un script para pegar directamente en Bash.
Mientras este cambio se revisa, usa el checkout de la rama `Ubuntu26` que
contiene este archivo; después de integrar el PR, el clon habitual de `main`
también lo tendrá.

---

Trabaja con Terminal Tuning de Jovanny Medina Cifuentes en mi sesión real de Google
Cloud Shell. Prepara mi terminal de forma eficaz, reproducible y estética, y
comprueba el resultado. Puedes instalar Terminal Tuning y sus dependencias necesarias;
conserva mis preferencias, configuración, autenticación y claves existentes.

1. Localiza el checkout de `https://github.com/JovannyCO/terminal-tuning`. Si falta,
   clona por HTTPS bajo HOME. Durante la revisión del cambio usa
   `git clone --branch Ubuntu26 https://github.com/JovannyCO/terminal-tuning.git` en
   un destino libre. Lee `AGENTS.md`, `README.md`, `docs/USO.md` y
   `docs/COMPATIBILIDAD.md`. Revisa el árbol sin descartarlo ni cambiar la rama
   de un checkout con trabajo existente. Comprueba `CLOUD_SHELL`, `uname -m`,
   la versión de Bash y Git y la inicialización de Google. Si no estás en
   Cloud Shell, detente y explica el entorno detectado; no falsees el perfil.
2. Inspecciona `bash setup-cloudshell.sh --dry-run`. Guarda un inventario de
   hashes y permisos de los archivos que el instalador reemplaza, sin copiar
   secretos al repo ni mostrar su contenido. Prepara primero un destino único
   con `mktemp -d /tmp/tunning-cloud-check-XXXXXX` y ejecuta allí
   `bash setup-cloudshell.sh --no-packages --target-dir RUTA_TEMPORAL`.
   Verifica que hay un solo bloque gestionado y que la inicialización de Google
   aparece antes de Terminal Tuning; no alteres `/google/devshell`.
3. Ejecuta `bash scripts/verify.sh`. Si falta una dependencia, identifica
   e instala únicamente la necesaria. Si hay un fallo, resuélvelo antes de
   instalar en mi usuario y registra el cambio; no eludas la comprobación de
   hashes o firmas.
4. Instala con `bash setup-cloudshell.sh`. Una instalación nueva usa Starship
   y extras sin Nerd Font; una existente conserva mi selección. No fuerces
   otro prompt ni una zona horaria diferente. Comprueba que los binarios de
   Starship, eza y fastfetch activados residen como archivos ejecutables en
   `~/.local/bin` y funcionan con `--version`. La descarga debe usar las URLs,
   versiones y SHA256 fijados. Para Bash sin extras usa la opción explícita
   `--prompt bash --no-extras` solo si esa es mi preferencia.
5. Reinstala con los mismos argumentos. Compara hashes y preferencias: no
   deben cambiar ni duplicarse bloques en `.bashrc`. Verifica que identidad,
   firma y los demás ajustes Git permanecen intactos, y que el alias apunta a
   la copia instalada. Usa `git sync --help` para comprobar su disponibilidad;
   no ejecutes una sincronización real ni publiques cambios de mis proyectos.
6. Comprueba una Bash interactiva nueva con `TUNNING_DEVUP_BOOT=0`, para que
   la prueba no lance actualizaciones. Prueba el directorio, una rama de un
   fixture Git, éxito/error del último comando, reloj, historial por prefijo,
   Tab/Shift+Tab y `eza --icons=never` si está activado. Verifica el prompt Bash
   de respaldo sin glifos privados, además de Starship cuando esté seleccionado.
   No consideres una sesión no interactiva como prueba del prompt. Conserva los
   respaldos y detén la instalación si falla una operación necesaria.
7. Distingue la terminal de la VM de la interfaz web. En Cloud Shell Editor no
   se admiten extensiones propias; una fuente instalada en Linux no añade una
   fuente al navegador. Ajusta solo temas y fuentes disponibles mediante las
   opciones documentadas si tienes acceso a la interfaz. Si no lo tienes,
   indícame los pasos manuales concretos y deja pendiente la comprobación
   visual. Revisa a 80 y 120 columnas la legibilidad, el azul cian `#02BCF9`,
   las dos líneas del prompt y la ausencia de cuadrados por glifos ausentes.
8. Entrega un informe breve con entorno, comandos y versiones, respaldo,
   comprobaciones aprobadas/fallidas y pasos manuales pendientes. Después de
   reconectar o cambiar de VM, vuelve a comprobar las rutas bajo HOME antes
   de afirmar que la persistencia real está validada. No reinicies ni borres
   archivos de otros proyectos para simular esa prueba. No añadas credenciales
   ni datos personales de la sesión al repositorio.

La terminal es el objetivo operativo. La portada pública debe conservar el
nombre Jovanny Medina Cifuentes y sus dos roles, Analista de Sistemas y
Desarrollador de Software. No atribuyas capacidades que las pruebas no demuestren.
