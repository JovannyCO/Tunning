[![Imágenes de Terminal Tuning: referencias, composición y trazabilidad de cada pieza](brand/imagenes-terminal-tuning-jovanny-co-header.png)](#imágenes-de-terminal-tuning)

[Revisar los recursos →](#imágenes-de-terminal-tuning)

# Imágenes de Terminal Tuning

La documentación aplica la identidad **Jovanny.CO** de **Jovanny Medina Cifuentes**,
**Analista de Sistemas · Desarrollador de Software**. Cada Markdown del consumidor
tiene un header que presenta su tema y un footer que resume su utilidad y enlaza
el siguiente paso.

## Piezas actuales

La vía de creación sigue la distinción solicitada: los siete documentos de la
raíz usan **14 imágenes nuevas generadas con imagegen**; los cinco documentos de
subcarpetas usan **10 composiciones con ImageMagick** sobre la plantilla original.
En la raíz, ImageMagick se utiliza únicamente para el ajuste técnico del lienzo
y la inserción del PNG original.

| Documento | Creación | Piezas |
|---|---|---|
| [README.md](../README.md) | IA | [Header](brand/terminal-tuning-portafolio-jovanny-co-header.png) · [Footer](brand/terminal-tuning-portafolio-jovanny-co-footer.png) |
| [AGENTS.md](../AGENTS.md) | IA | [Header](brand/agentes-terminal-tuning-jovanny-co-header.png) · [Footer](brand/agentes-terminal-tuning-jovanny-co-footer.png) |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | IA | [Header](brand/contribuir-terminal-tuning-jovanny-co-header.png) · [Footer](brand/contribuir-terminal-tuning-jovanny-co-footer.png) |
| [SECURITY.md](../SECURITY.md) | IA | [Header](brand/seguridad-terminal-tuning-jovanny-co-header.png) · [Footer](brand/seguridad-terminal-tuning-jovanny-co-footer.png) |
| [SETUP-Firebase-Ubuntu-26.md](../SETUP-Firebase-Ubuntu-26.md) | IA | [Header](brand/entorno-firebase-ubuntu-26-jovanny-co-header.png) · [Footer](brand/entorno-firebase-ubuntu-26-jovanny-co-footer.png) |
| [VALIDACION-Ubuntu-26-WSL2.md](../VALIDACION-Ubuntu-26-WSL2.md) | IA | [Header](brand/diagnostico-ubuntu-26-wsl2-jovanny-co-header.png) · [Footer](brand/diagnostico-ubuntu-26-wsl2-jovanny-co-footer.png) |
| [promptTMP.md](../promptTMP.md) | IA | [Header](brand/validacion-cloud-shell-jovanny-co-header.png) · [Footer](brand/validacion-cloud-shell-jovanny-co-footer.png) |
| [docs/USO.md](../docs/USO.md) | ImageMagick | [Header](brand/guia-de-uso-terminal-tuning-jovanny-co-header.png) · [Footer](brand/guia-de-uso-terminal-tuning-jovanny-co-footer.png) |
| [docs/COMPATIBILIDAD.md](../docs/COMPATIBILIDAD.md) | ImageMagick | [Header](brand/compatibilidad-terminal-tuning-jovanny-co-header.png) · [Footer](brand/compatibilidad-terminal-tuning-jovanny-co-footer.png) |
| [docs/GIT-PR.md](../docs/GIT-PR.md) | ImageMagick | [Header](brand/flujo-git-pr-terminal-tuning-jovanny-co-header.png) · [Footer](brand/flujo-git-pr-terminal-tuning-jovanny-co-footer.png) |
| [docs/GITHUB.md](../docs/GITHUB.md) | ImageMagick | [Header](brand/presentacion-github-terminal-tuning-jovanny-co-header.png) · [Footer](brand/presentacion-github-terminal-tuning-jovanny-co-footer.png) |
| [assets/README.md](README.md) | ImageMagick | [Header](brand/imagenes-terminal-tuning-jovanny-co-header.png) · [Footer](brand/imagenes-terminal-tuning-jovanny-co-footer.png) |

Todos los finales son PNG opacos de **1942 × 809 px**. Se conserva la paleta
`#FF6D00`, `#00897B`, `#02BCF9`, `#1C1B1F` y `#2B2930`, el texto a la izquierda,
la ilustración 3D a la derecha y tipografía equivalente a Inter/Roboto. El nombre
completo y los dos roles mantienen una jerarquía legible.

El único emoji de marca es el **PNG original**, insertado en una caja de
**64 × 64 px** arriba a la derecha, con **32 px de margen**. Se mantiene su
lienzo transparente completo, sin recorte, perspectiva, marcos ni sombras.
La escena temática permanece separada del distintivo.

Los textos alternativos describen cada tema; las imágenes enlazan destinos
reales y las llamadas a la acción están disponibles también como texto.

## Referencias y trazabilidad

Las referencias pertenecen al submódulo privado `JovannyCO/__Brands`, consultado
en el commit `b8427372bff2f254727a31c8fcf0056c27e89b15`. Permanecen intactas:

- Guía: `.brand/README.md` y `.brand/marcas/jovanny-co.md`.
- Referencias IA: `.brand/assets/brand/identidad-de-marca-jovanny-co-header.png`
  y `identidad-de-marca-jovanny-co-footer.png`.
- Plantilla IM: `.brand/assets/brands/jovanny-co/plantilla-vacia-jovanny-co.png`.
- PNG original: `.brand/assets/brands/jovanny-co/logo-jovanny-co.png`.

El [manifiesto](brand/manifest.json) registra el documento, método, textos,
destinos, prompts exactos o comandos de composición, dimensiones y SHA256 de
cada final. La regeneración requiere acceso autorizado a las referencias;
las imágenes finales y las comprobaciones normales del consumidor son locales.

## Reproducir las piezas

Para los Markdown de la **raíz**, aporta al generador integrado la referencia
indicada y el prompt completo del manifiesto. El generador crea el banner con
su tipografía e ilustración temática, reservando la esquina del distintivo sin
dibujar bombillas. Antes de insertar el PNG original, ajusta el lienzo sin
deformarlo a 1942 × 809 px. Después:

```bash
magick banner-base.png \( .brand/assets/brands/jovanny-co/logo-jovanny-co.png -resize 64x64 \) \
  -gravity northeast -geometry +32+32 -compose over -composite banner-final.png
```

Para los Markdown de **subcarpetas**, el manifiesto incluye los textos exactos
para el [compositor del consumidor](../scripts/render-doc-brand.sh). Ejecútalo
desde la raíz, con ImageMagick y las fuentes indicadas ya disponibles:

```bash
bash scripts/render-doc-brand.sh \
  'Instala y conserva tu terminal' \
  'Prompt, Git sync y devup, con preferencias y respaldos.' \
  'Ir a la instalación →' \
  assets/brand/guia-de-uso-terminal-tuning-jovanny-co-header-v2.png
```

El compositor utiliza la plantilla y el PNG originales, conserva ambos roles
y crea un archivo nuevo. Revisa textos, proporción, márgenes y legibilidad a
830 px antes de enlazar una nueva versión.

## Revisión de descartes

`assets/_borrar/` es una carpeta temporal para revisar imágenes antes de
eliminarlas. El usuario puede borrar su contenido cuando termine la revisión.
Los documentos activos no deben enlazar esos descartes ni exigir que se restauren.


[![Cierre de imágenes: conserva el método, los textos y las huellas de cada banner](brand/imagenes-terminal-tuning-jovanny-co-footer.png)](#reproducir-las-piezas)

[Consultar la reproducción →](#reproducir-las-piezas)

