[![Reglas para cambiar la terminal: conserva identidad y preferencias y verifica en local](assets/brand/agentes-terminal-tuning-jovanny-co-header.png)](#antes-de-cambiar-una-terminal)

[Leer las reglas →](#antes-de-cambiar-una-terminal)

# Trabajar en Terminal Tuning

Terminal Tuning prepara una terminal nueva y muestra el trabajo de **Jovanny Medina
Cifuentes**, **Analista de Sistemas** y **Desarrollador de Software**. Conserva
ambos propósitos, la atribución MIT y los dos roles al modificar la portada.

Marca: **Jovanny.CO**. Para crear o actualizar imágenes de Markdown, aplica
`.brand/README.md` y `.brand/marcas/jovanny-co.md` leyendo las referencias ya
disponibles. El usuario administra el acceso a `JovannyCO/__Brands`. La instalación
y las comprobaciones normales del consumidor no requieren esas referencias.
Limita la aplicación de la marca a las imágenes y documentos solicitados;
los Markdown existentes conservan su alcance. Excluye submódulos, dependencias
y archivos generados. Conserva intactos los originales de referencia de `.brand`
y guarda los nuevos resultados en `assets/brand/`.

`.brand` y los repositorios cuyo nombre comienza por `__` son dependencias
siempre de solo lectura. No los inicialices ni cambies su checkout, rama o
configuración; no ejecutes commit, merge, fetch, push ni PR en ellos.
`git sync`, `git syncPR` y `git syncPRmerge` procesan el padre conservando el
SHA ya seleccionado por el usuario, que puede registrarse como gitlink.
Si se invocan dentro de uno de esos repositorios, deben negarse a modificarlo.

## Antes de cambiar una terminal

- Lee [README.md](README.md), [docs/USO.md](docs/USO.md) y la
  [matriz de compatibilidad](docs/COMPATIBILIDAD.md). Comprueba el entorno real.
- La implementación del instalador está en `scripts/install.sh`; los wrappers
  llaman a esa implementación. Los tres alias comparten `scripts/git-sync.sh`
  y sus módulos `scripts/git-pr.sh` y `scripts/git-json.sh`, instalados juntos.
  Cambiar el checkout requiere reinstalar las copias.
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
bash scripts/verify.sh
revision_tunning=$(mktemp -d /tmp/tunning-revision.XXXXXX)
bash setup.sh --no-packages --target-dir "$revision_tunning" --dry-run
bash setup.sh --no-packages --target-dir "$revision_tunning"
```

Ejecuta y corrige las comprobaciones en local antes de publicar. El verificador
comprueba sintaxis Bash/JSON, enlaces locales y cabeceras y dimensiones PNG.
Terminal Tuning mantiene las comprobaciones en la terminal, sin configuración `.github`
ni publicación de estados de pruebas o
criterios en GitHub.

Usa destinos temporales únicos para pruebas; no ejecutes actualizadores o sync
en proyectos del usuario como fixtures. No desactives firmas para eludir
errores. Comprueba la reinstalación y la conservación de preferencias si
cambias el instalador. Para comprobar flujos de Git emplea remotos locales temporales.

Publica únicamente si forma parte de la petición del usuario. Conserva la rama
activa, comprueba el árbol y los remotos antes de `git sync`, y asocia los PR
a su issue cuando proceda. `main` es la principal pública de Terminal Tuning; otros
proyectos pueden usar `production`. No impongas una rama a los submódulos ni
fusiones PR automáticamente.

`git sync`, `git syncPR` y `git syncPRmerge` comprueban el resultado local
antes del push y se ejecutan 100 % en la terminal sin depender de un agente de IA.
Para otros proyectos configura sus comprobaciones mediante `tunning.testCommands`;
no supongas que las comprobaciones de Terminal Tuning validan sus submódulos.
La evidencia de criterios se registra y valida con el SHA, la base y los hashes de
logs reales de las comprobaciones locales. Consulta [docs/GIT-PR.md](docs/GIT-PR.md).

Comunica qué se verificó y qué queda pendiente. Una prueba local del perfil
Cloud Shell no certifica su navegador, sus fuentes ni la persistencia real.

[![Verifica antes de publicar cambios: pruebas locales y evidencia del resultado real](assets/brand/agentes-terminal-tuning-jovanny-co-footer.png)](#verificar-los-cambios)

[Revisar las comprobaciones →](#verificar-los-cambios)
