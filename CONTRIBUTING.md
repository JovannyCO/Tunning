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
python3 scripts/verify.py
python3 -m unittest discover -s tests -v
```

Las comprobaciones requieren Python 3.11 o posterior, Git, Bash y GnuPG. Los
tests usan repositorios y destinos temporales: no necesitan GitHub ni claves
reales. Las descargas de extras se simulan, sin instalar paquetes. Prueba una
instalación aislada si cambias el instalador y añade una regresión cuando haya
un fallo funcional. Para cambios visuales, indica qué interfaz revisaste.

Tus contribuciones se distribuyen bajo [MIT](LICENSE), conservando los avisos
de autor y licencia. Las herramientas externas mantienen sus propias licencias.
