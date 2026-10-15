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

## Historial de las piezas anteriores

Los cuatro PNG anteriores se conservan bajo `assets/_borrar/`, con su
estructura relativa. Esta carpeta queda fuera del inventario de recursos activos.
Los prompts y las medidas que siguen describen ese diseño anterior; el contrato
vigente es el de las piezas actuales y el manifiesto.

<details>
<summary>Documentación histórica de la portada anterior</summary>

Header y footer nuevos, generados con la herramienta integrada **image_gen** y la
habilidad **imagegen** a partir de las referencias de **Jovanny.CO**, con
composición final del PNG original mediante **ImageMagick**. Son
ilustraciones de marca. Presentan el proyecto como caso de trabajo de
**Jovanny Medina Cifuentes**, **Analista de Sistemas · Desarrollador de Software**.

| Archivo final | Uso | Dimensiones PNG | Destino del enlace |
|---|---|---|---|
| [terminal-tuning-jovanny-co-header.png](_borrar/brand/terminal-tuning-jovanny-co-header.png) | Presentación profesional y del proyecto | 1944 × 809 | [Explora el proyecto](../README.md#de-una-terminal-nueva-a-un-entorno-de-trabajo) |
| [terminal-tuning-jovanny-co-footer.png](_borrar/brand/terminal-tuning-jovanny-co-footer.png) | Colaboración y contacto | 1942 × 809 | [Contacta al desarrollador](mailto:proyectos@Jovanny.CO) |

Ambas piezas tienen fondo opaco y composición panorámica cercana a 12:5. El
README conserva las llamadas a la acción como enlaces de texto real, además
del texto alternativo de las imágenes.

### Referencias conservadas

La carpeta `.brand` es el submódulo incorporado por el propietario. Sus
originales permanecen intactos; los entregables se guardan en este repositorio
consumidor, en `assets/brand/`.

Las referencias requieren acceso al submódulo privado `JovannyCO/__Brands`,
fijado al commit `0d3fc4148684016d34c17b5d16536a44f89e84df`. Sus rutas locales
desde la raíz del consumidor son:

- Instrucciones: `.brand/README.md` y `.brand/marcas/jovanny-co.md`.
- Header: `.brand/assets/brands/jovanny-co/marca-personal-jovanny-co-header.png`.
- Footer: `.brand/assets/brands/jovanny-co/marca-personal-jovanny-co-footer.png`.
- Emoji original: `.brand/assets/brands/jovanny-co/logo-jovanny-co.png`, usado como entrada junto a cada referencia.

Para regenerar imágenes, inicializa `.brand` con una cuenta autorizada. Los
gráficos finales y los prompts permanecen en el consumidor, y sus comprobaciones
normales funcionan también en una clonación pública sin ese submódulo.

Se conserva la composición de texto a la izquierda e ilustración a la derecha,
paneles Material Design 3, tipografía equivalente a Roboto/Inter y trazos
naranja, teal y cian. La paleta usa primario `#FF6D00`, secundario `#00897B`,
terciario `#02BCF9` y superficies `#1C1B1F` / `#2B2930`.
Los dos roles profesionales tienen igual importancia. Los PNG anteriores
permanecen como historial; la portada utiliza las dos piezas nuevas.

### Reproducir las piezas

Los siguientes son los prompts usados en la herramienta integrada. Las rutas
de `Input images` se resuelven desde la raíz del repositorio; abre primero las
referencias y aporta los archivos mediante `referenced_image_paths`. Cada
pieza requiere su propia llamada y fondo opaco. Guarda el resultado en la ruta
final, comprueba todos los textos y revisa su legibilidad a unos 830 px antes
de cambiar los enlaces de la portada. Una nueva generación puede variar.

### Prompt del encabezado

```text
Use case: ads-marketing
Asset type: final Markdown header banner for the Terminal Tuning repository, PNG, opaque background.
Primary request: Generate a new, polished Terminal Tuning banner in the same Jovanny.CO visual identity and design system as Image 1. This is a new project-specific composition, not a renamed copy of the reference.
Input images: Image 1 is the Jovanny.CO header STYLE AND COMPOSITION REFERENCE only. Image 2 is the ORIGINAL LIGHT-BULB LOGO, a supporting compositing insert. Preserve that exact original flat Microsoft emoji logo, its silhouette, proportions and colors; place it intact on the right-side foreground panel. Do not redraw, reinterpret or stylize the logo.
Scene/backdrop: dark Material Design 3 panels and overlapping softly rounded cards, background #1C1B1F, panels #2B2930, subtle dimensional edge lighting, clean premium presentation.
Composition/framing: panoramic 12:5, target 1944x810 pixels (or 1920x800), same generous margins and hierarchy as reference. Main copy on the left 65 percent; layered illustration on the right 35 percent. Keep every text line fully visible with comfortable outer margins. Right illustration combines the original light-bulb logo with a simple terminal panel motif; no extraneous terminal text. Three smooth connecting traces in orange #FF6D00, teal #00897B, cyan #02BCF9 connect left to right, as in the reference.
Typography: crisp bold Roboto or Inter equivalent. Render the exact Spanish copy below, with correct accents, capitalization and punctuation, and no extra words. Header title is very large and prominent; the author's full name is also prominent. Subtitle and both professional roles must remain easily readable when the entire banner is displayed at 830 pixels wide: minimum source text size about 36px. Give both roles exactly equal size and weight, first teal and second cyan, separated by the middle dot. Keep CTA orange with dark lettering, matching the reference's rounded button.
Text (verbatim), arranged as these five lines, left aligned:
"Terminal Tuning"
"Tu terminal preparada para retomar el trabajo."
"Jovanny Medina Cifuentes"
"Analista de Sistemas · Desarrollador de Software"
"Explora el proyecto →"
Constraints: preserve the style, color palette, panoramic proportions and strong contrast of the reference, while adapting the illustration to terminal preparation. Professional, composed, uncluttered. Exact project spelling is Terminal Tuning (single n in Tuning). No invented achievements, no old reference slogans, no additional labels, no watermark, no cropping, no transparency. Do not add the word Tunning.
```

### Retoque del encabezado

Tras la primera generación se pidió un espacio claramente visible entre las
dos palabras del nombre. Se aportó el encabezado generado como imagen objetivo.

```text
Use case: text-localization
Asset type: precise typographic correction to the supplied final Markdown header banner.
Primary request: Change ONLY the large title's word spacing. It must visibly read as TWO WORDS, exactly "Terminal Tuning", with a clear, generous normal word space between the white word "Terminal" and the orange word "Tuning". The current title visually joins those words; correct that. Place at least 35 pixels of clean visible horizontal gap between the final white lowercase l and the orange capital T at this 1942-pixel-wide canvas. If necessary reduce only the title font size very slightly to keep the full title within its current area.
Input image: Image 1 is the EDIT TARGET, the already-approved final header.
Constraints and invariants: Keep every other pixel and feature as close to identical as possible. Preserve the exact 1942x809 opaque PNG canvas, all margins, dark MD3 background and panels, three colored connecting traces, original bulb logo and terminal illustration, lighting, CTA, typography of all other lines, and all other text. Keep the title white "Terminal" and orange "Tuning", on a single line, with the same typeface and hierarchy. Do not alter the spelling, accents, sizes or placement of the subtitle, author, professional roles, or CTA.
Other text that must remain unchanged:
"Tu terminal preparada para retomar el trabajo."
"Jovanny Medina Cifuentes"
"Analista de Sistemas · Desarrollador de Software"
"Explora el proyecto →"
Avoid: merged words, joined title, spelling changes, layout changes outside the title, adding new objects, cropping, watermark, transparency.
```

### Prompt del footer

```text
Use case: ads-marketing
Asset type: final Markdown footer banner for the Terminal Tuning repository, PNG, opaque background.
Primary request: Generate a new, polished Terminal Tuning closing banner in the same Jovanny.CO visual identity and design system as Image 1. This is a new project-specific composition, not a renamed copy of the reference.
Input images: Image 1 is the Jovanny.CO footer STYLE AND COMPOSITION REFERENCE only. Image 2 is the ORIGINAL LIGHT-BULB LOGO, a supporting compositing insert. Preserve that exact original flat Microsoft emoji logo, its silhouette, proportions and colors; place it intact on the right-side foreground panel. Do not redraw, reinterpret or stylize the logo.
Scene/backdrop: dark Material Design 3 panels and overlapping softly rounded cards, background #1C1B1F, panels #2B2930, subtle dimensional edge lighting, clean premium presentation.
Composition/framing: panoramic 12:5, target 1944x810 pixels (or 1920x800), same generous margins and hierarchy as reference. All copy on the left 65 percent; layered illustration on the right 35 percent. Keep every text line fully visible with comfortable outer margins. Right illustration combines the original light-bulb logo with a simple terminal panel motif; no extraneous terminal text. Three smooth connecting traces in orange #FF6D00, teal #00897B, cyan #02BCF9 connect left to right, as in the reference.
Typography: crisp bold Roboto or Inter equivalent. Render the exact Spanish copy below, with correct accents, capitalization and punctuation, and no extra words. Two-line closing statement is very large, first line light and second orange. Author's full name must stay prominent. The signature, both professional roles, contact email, and CTA must remain easily readable when the entire banner is displayed at 830 pixels wide: minimum source text size about 36px. Give both roles exactly equal size and weight, first teal and second cyan, separated by the middle dot. Keep CTA orange with dark lettering in a rounded button matching the reference. Email is light with a small orange envelope icon.
Text (verbatim), arranged as these six lines, left aligned:
"Tu próximo proyecto,"
"del análisis al software."
"Terminal Tuning · Jovanny Medina Cifuentes"
"Analista de Sistemas · Desarrollador de Software"
"Contacta al desarrollador →"
"proyectos@Jovanny.CO"
Constraints: preserve the style, color palette, panoramic proportions and strong contrast of the reference, while adapting the illustration to terminal preparation. Professional, composed, uncluttered. Exact project spelling is Terminal Tuning (single n in Tuning). No invented achievements, no old reference slogans, no additional labels, no watermark, no cropping, no transparency. Do not add the word Tunning.
```

### Composición del PNG original

La composición final usa **ImageMagick 7.1.2-18 Q16**: una placa MD3 cubre la
bombilla reinterpretada por el generador y el PNG original se inserta mediante
escala uniforme y composición `Over`. Se conservan su borde negro, colores
planos, geometría y transparencia, sin volver a dibujarlo. Los textos y los
píxeles exteriores a las placas permanecen intactos.

Después de generar cada banner y corregir el espacio del título, aplica estos
comandos desde la raíz del repositorio, con ImageMagick disponible. Los nombres
`header-generado.png` y `footer-generado.png` representan esas salidas previas.
Las coordenadas corresponden a los lienzos actuales de 1944 × 809 y 1942 × 809;
si una nueva generación cambia la composición, ajusta las cajas sin cubrir texto.

```bash
magick header-generado.png -fill '#2B2930' -stroke '#4B4950' -strokewidth 1 -draw 'roundrectangle 1448,220 1722,610 24,24' '(' .brand/assets/brands/jovanny-co/logo-jovanny-co.png -filter Lanczos -resize 352x352 ')' -geometry +1409+238 -compose Over -composite PNG24:header-final.png
magick footer-generado.png -fill '#2B2930' -stroke '#4B4950' -strokewidth 1 -draw 'roundrectangle 1515,186 1818,611 24,24' '(' .brand/assets/brands/jovanny-co/logo-jovanny-co.png -filter Lanczos -resize 384x384 ')' -geometry +1476+205 -compose Over -composite PNG24:footer-final.png
```

Comprueba ambos resultados antes de copiarlos a las rutas finales de la tabla.
La revisión final verificó legibilidad a 830 px, ausencia de recortes y colores
exactos en los píxeles opacos del logo escalado. Los bordes suavizados conservan
el redondeo normal de la composición PNG de 8 bits.

| Archivo | SHA256 final |
|---|---|
| Header | `4c04a0495f1d8e8d4c29a459fda669e046d2764ab1a8f577e861071066c9bbfa` |
| Footer | `68dd8ef8e67da0f690810161da633fa9f875ec4287efaec36d64aadc8216a874` |

El PNG original conserva SHA256 `a53727c55a73f2bbdf2727c57573c3d7b55e1a2cd6e6d0a9bb50eeab4093446e`.

</details>

[![Cierre de imágenes: conserva el método, los textos y las huellas de cada banner](brand/imagenes-terminal-tuning-jovanny-co-footer.png)](#reproducir-las-piezas)

[Consultar la reproducción →](#reproducir-las-piezas)

