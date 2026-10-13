# Seguridad

Para informar de una vulnerabilidad, escribe a
[proyectos@Jovanny.CO](mailto:proyectos@Jovanny.CO) con la versión, el impacto y
una reproducción sin secretos. No publiques credenciales, claves ni datos de
proyectos privados en un issue. No hay un plazo de respuesta garantizado.

El código y la configuración pueden auditarse antes de instalar. Los extras
de Cloud Shell se descargan de releases oficiales con versiones y SHA256
fijados en [el instalador](scripts/install-cloudshell-extras.sh). Un hash
comprueba que el archivo coincide con el revisado; la confianza también depende
del proveedor y del código de Tunning. Los ejecutables normales ya presentes
en `~/.local/bin` se conservan.

La instalación no recupera sesiones ni claves de otros proyectos. `git sync`
agrega todos los archivos no ignorados y publica en los remotos configurados;
revisa esos archivos antes de usarlo. La firma no cifra su contenido. Consulta
[la guía de Git sync](docs/USO.md#git-sync) para sus requisitos y errores.
