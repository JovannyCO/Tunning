# Contribuir a Tunning

Describe el problema, el entorno y el resultado esperado en un issue. Para
defectos del instalador incluye la versión de Ubuntu o si usas Cloud Shell,
los argumentos y el error observado. Revisa los registros antes de publicarlos;
para información sensible usa [el canal de seguridad](SECURITY.md).

Los cambios se proponen mediante un PR hacia `main`, asociado a su issue.
Explica el comportamiento resultante y las comprobaciones realizadas. Conserva
la instalación reproducible, la identidad Git, las firmas y las preferencias.
Consulta [AGENTS.md](AGENTS.md) y [la compatibilidad](docs/COMPATIBILIDAD.md).

```bash
python3 scripts/test-local.py --jobs 8
```

Las comprobaciones requieren Python 3.11 o posterior, Git, Bash y GnuPG. Los
tests usan repositorios y destinos temporales: no necesitan GitHub ni claves
reales. Las descargas de extras se simulan, sin instalar paquetes. Prueba una
instalación aislada si cambias el instalador y añade una regresión cuando haya
un fallo funcional. Para cambios visuales, indica qué interfaz revisaste.

Ejecuta las comprobaciones en local, corrige los fallos y publica después de
pasarlas. El runner verifica sintaxis/enlaces y distribuye la suite entre
procesos; `--jobs` permite ajustar la concurrencia a tu equipo. Tunning mantiene
estas comprobaciones en la terminal, sin configuración `.github` ni publicación
de estados de pruebas o criterios en GitHub. `git sync` y los modos PR
comprueban las suites locales antes del push; tras cambiar el motor reinstala la copia
con `bash setup.sh --no-packages`.

Pasar las pruebas no completa por sí solo los criterios de aceptación. Antes
de una fusión solicitada, el motor valida en local la evidencia del SHA y base
vigentes y una auditoría independiente firmada. Consulta [la política de
PR](docs/GIT-PR.md). Las revisiones y demás protecciones remotas siguen
aplicándose; el motor no usa excepciones de administrador para fusionar.

Tus contribuciones se distribuyen bajo [MIT](LICENSE), conservando los avisos
de autor y licencia. Las herramientas externas mantienen sus propias licencias.
