# Trabajar en Tunning

Tunning prepara una terminal nueva y muestra el trabajo de **Jovanny Medina
Cifuentes**, **Analista de Sistemas** y **Desarrollador de Software**. Conserva
ambos propósitos, la atribución MIT y los dos roles al modificar la portada.

## Antes de cambiar una terminal

- Lee [README.md](README.md), [docs/USO.md](docs/USO.md) y la
  [matriz de compatibilidad](docs/COMPATIBILIDAD.md). Comprueba el entorno real.
- La implementación del instalador está en `scripts/install.py`; los wrappers
  llaman a esa implementación. `scripts/git-sync.sh` es la única fuente del
  alias instalado. Cambiar el checkout requiere reinstalar las copias.
- Conserva identidad, autenticación, firmas, preferencias, zona horaria y los
  bloques ajenos de Bash. Usa el instalador y sus respaldos; no reemplaces
  archivos completos con ejemplos. No guardes secretos en este repositorio.
- `--profile` con otro entorno sirve únicamente para fixtures con
  `--target-dir` y `--no-packages`. No falsees la detección en una instalación real.
- En Cloud Shell conserva la inicialización de Google y las herramientas de
  usuario en HOME. Evita glifos Nerd Font. El navegador y Cloud Shell Editor
  tienen ajustes propios; no prometas instalar extensiones ni fuentes propias
  allí. [promptTMP.md](promptTMP.md) guía la validación en una sesión real.

## Verificar los cambios

```bash
python3 scripts/verify.py
python3 -m unittest discover -s tests -v
bash setup.sh --no-packages --target-dir /tmp/tunning-revision --dry-run
bash setup.sh --no-packages --target-dir /tmp/tunning-revision
```

Usa destinos temporales únicos para pruebas; no ejecutes actualizadores o sync
en proyectos del usuario como fixtures. No desactives firmas para eludir
errores. Comprueba la reinstalación y la conservación de preferencias si
cambias el instalador. Las pruebas de Git emplean remotos locales temporales.

Publica únicamente si forma parte de la petición del usuario. Conserva la rama
activa, comprueba el árbol y los remotos antes de `git sync`, y asocia los PR
a su issue cuando proceda. `main` es la principal pública de Tunning; otros
proyectos pueden usar `production`. No impongas una rama a los submódulos ni
fusiones PR automáticamente.

Comunica qué se verificó y qué queda pendiente. Una prueba local del perfil
Cloud Shell no certifica su navegador, sus fuentes ni la persistencia real.
