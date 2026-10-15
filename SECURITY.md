[![Seguridad de Terminal Tuning: reporta riesgos sin exponer secretos e incluye versión, impacto y reproducción](assets/brand/seguridad-terminal-tuning-jovanny-co-header.png)](mailto:proyectos@Jovanny.CO)

[Escribir por canal privado →](mailto:proyectos@Jovanny.CO)

# Seguridad

Para informar de una vulnerabilidad, escribe a
[proyectos@Jovanny.CO](mailto:proyectos@Jovanny.CO) con la versión, el impacto y
una reproducción sin secretos. No publiques credenciales, claves ni datos de
proyectos privados en un issue. No hay un plazo de respuesta garantizado.

El código y la configuración pueden auditarse antes de instalar. Los extras
de Cloud Shell se descargan de releases oficiales con versiones y SHA256
fijados en [el instalador](scripts/install-cloudshell-extras.sh). Un hash
comprueba que el archivo coincide con el revisado; la confianza también depende
del proveedor y del código de Terminal Tuning. Los ejecutables normales ya presentes
en `~/.local/bin` se conservan.

La instalación no recupera sesiones ni claves de otros proyectos. `git sync`
agrega todos los archivos no ignorados y publica en los remotos configurados;
revisa esos archivos antes de usarlo. La firma no cifra su contenido. Consulta
[la guía de Git sync](docs/USO.md#git-sync) para sus requisitos y errores.

[![Audita el código y cuida lo que publicas; reporta vulnerabilidades a proyectos@Jovanny.CO sin secretos](assets/brand/seguridad-terminal-tuning-jovanny-co-footer.png)](mailto:proyectos@Jovanny.CO)

[proyectos@Jovanny.CO →](mailto:proyectos@Jovanny.CO)
