#!/usr/bin/env bash
# Composición solicitada para Markdown de subcarpetas: ImageMagick y originales.
set -euo pipefail

if (( $# != 4 )); then
  printf 'Uso: bash scripts/render-doc-brand.sh "Título" "Apoyo" "CTA" assets/brand/nombre.png\n' >&2
  exit 2
fi

titulo=$1 apoyo=$2 cta=$3 salida=$4
raiz=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
plantilla="$raiz/.brand/assets/brands/jovanny-co/plantilla-vacia-jovanny-co.png"
emoji="$raiz/.brand/assets/brands/jovanny-co/logo-jovanny-co.png"
fuente=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
negrita=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

command -v magick >/dev/null || { printf 'Falta ImageMagick del sistema.\n' >&2; exit 1; }
for archivo in "$plantilla" "$emoji" "$fuente" "$negrita"; do
  [[ -r $archivo ]] || { printf 'No se puede leer %s\n' "$archivo" >&2; exit 1; }
done
[[ $salida == assets/brand/*.png && ! -e $salida ]] || {
  printf 'La salida debe ser un PNG nuevo en assets/brand/.\n' >&2; exit 1;
}

temporal=$(mktemp -d /tmp/terminal-tuning-brand.XXXXXXXX)
trap 'rm -rf -- "$temporal"' EXIT

# ImageMagick interpreta secuencias especiales: conservar texto literal.
literal() {
  local valor=${1//\\/\\\\}
  valor=${valor//%/%%}
  valor=${valor//@/\\@}
  valor=${valor//&/\\&}
  printf '%s' "$valor"
}

capa() {
  local nombre=$1 texto=$2 tamano=$3 color=$4 alto=$5 tipo=$6 medidas ancho altura
  magick -background none -fill "$color" -font "$tipo" -pointsize "$tamano" \
    -interline-spacing 4 -gravity northwest -size 828x \
    "caption:$(literal "$texto")" "$temporal/$nombre.png"
  medidas=$(magick "$temporal/$nombre.png" -format '%w %h' info:)
  read -r ancho altura <<< "$medidas"
  (( ancho <= 828 && altura <= alto )) || {
    printf 'El texto %s no cabe; resúmelo antes de generar.\n' "$nombre" >&2; exit 1;
  }
}

capa marca 'Jovanny.CO' 34 '#FF6D00' 48 "$negrita"
capa titulo "$titulo" 64 '#F4EFF4' 170 "$negrita"
capa apoyo "$apoyo" 36 '#D5D0D9' 102 "$fuente"
capa autor 'Jovanny Medina Cifuentes' 40 '#F4EFF4' 58 "$fuente"
# Dos líneas, mismo tamaño y peso: ambos roles conservan igual jerarquía.
capa analista 'Analista de Sistemas' 36 '#35C7AE' 52 "$fuente"
capa desarrollador 'Desarrollador de Software' 36 '#02BCF9' 52 "$fuente"
capa cta "$cta" 36 '#FF6D00' 54 "$negrita"

# Preparar el tamaño antes del distintivo. No reescalar tras insertarlo.
magick "$plantilla" -gravity northwest -crop 1942x809+0+0 +repage \
  "$temporal/marca.png" -geometry +112+94 -composite \
  "$temporal/titulo.png" -geometry +112+173 -composite \
  "$temporal/apoyo.png" -geometry +112+370 -composite \
  "$temporal/autor.png" -geometry +112+504 -composite \
  "$temporal/analista.png" -geometry +112+565 -composite \
  "$temporal/desarrollador.png" -geometry +112+612 -composite \
  "$temporal/cta.png" -geometry +112+705 -composite \
  \( "$emoji" -resize 64x64 \) -gravity northeast -geometry +32+32 \
  -compose over -composite -strip "PNG:$salida"
printf 'Creado: %s\n' "$salida"
