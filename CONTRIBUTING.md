[![Contribuir a Terminal Tuning: propone cambios con contexto, pruebas y resultados verificables](assets/brand/contribuir-terminal-tuning-jovanny-co-header.png)](https://github.com/JovannyCO/terminal-tuning/issues/new)

[Describir el problema →](https://github.com/JovannyCO/terminal-tuning/issues/new)

# Contribuir a Terminal Tuning

Describe el problema, el entorno y el resultado esperado en un issue. Para
defectos del instalador incluye la versión de Ubuntu o si usas Cloud Shell,
los argumentos y el error observado. Revisa los registros antes de publicarlos;
para información sensible usa [el canal de seguridad](SECURITY.md).

Los cambios se proponen mediante un PR hacia `main`, asociado a su issue.
Explica el comportamiento resultante y las comprobaciones realizadas. Conserva
la instalación reproducible, la identidad Git, las firmas y las preferencias.
Consulta [AGENTS.md](AGENTS.md) y [la compatibilidad](docs/COMPATIBILIDAD.md).

Para revisar sintaxis y enlaces locales:

```bash
bash scripts/verify.sh
```

La verificación estática requiere Bash, awk y las herramientas básicas de
Ubuntu. Prueba una instalación aislada si cambias el instalador. Para cambios
visuales, indica qué interfaz revisaste.

Ejecuta las comprobaciones en local, corrige los fallos y publica después de
pasarlas. Terminal Tuning mantiene estas comprobaciones en la terminal, sin
configuración `.github` ni publicación de estados de pruebas o criterios en
GitHub. `git sync` y los modos PR comprueban las suites locales antes del push;
tras cambiar el motor reinstala la copia con `bash setup.sh --no-packages`.

Pasar las pruebas no completa por sí solo los criterios de aceptación. Antes
de una fusión solicitada, el motor valida en local la evidencia del SHA y base
vigentes y una auditoría independiente firmada. Consulta [la política de
PR](docs/GIT-PR.md). Las revisiones y demás protecciones remotas siguen
aplicándose; el motor no usa excepciones de administrador para fusionar.

Tus contribuciones se distribuyen bajo [MIT](LICENSE), conservando los avisos
de autor y licencia. Las herramientas externas mantienen sus propias licencias.

[![Un PR con evidencia facilita la revisión y conserva identidad, firmas y preferencias](assets/brand/contribuir-terminal-tuning-jovanny-co-footer.png)](docs/GIT-PR.md)

[Consultar la política de PR →](docs/GIT-PR.md)
