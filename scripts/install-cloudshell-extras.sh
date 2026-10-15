#!/usr/bin/env bash
# Versiones oficiales verificadas el 2026-10-13. No ejecuta instaladores remotos.
set -Eeuo pipefail
[[ $(uname -m) == x86_64 ]] || { echo 'Los binarios Cloud Shell requieren x86_64.' >&2; exit 1; }
for dependencia in curl tar sha256sum install mktemp; do
    command -v "$dependencia" >/dev/null || { echo "Falta $dependencia." >&2; exit 1; }
done
directorio_descarga=$(mktemp -d)
archivo_temporal=''
herramienta='preparación'
trap 'rm -rf -- "$directorio_descarga"; [[ -z $archivo_temporal ]] || rm -f -- "$archivo_temporal"' EXIT
trap 'printf "Error al preparar %s para Cloud Shell; instalación incompleta.\n" "$herramienta" >&2' ERR
herramientas_pendientes=()

preparar_binario() {
    local version=$2 direccion_descarga=$3 huella_sha256=$4 archivo_del_paquete=$5
    herramienta=$1
    # Un binario del sistema puede desaparecer con la VM. Conservar solo copias
    # ejecutables normales dentro de HOME; no seguir enlaces al reemplazarlas.
    if [[ -x $HOME/.local/bin/$herramienta && ! -L $HOME/.local/bin/$herramienta ]]; then
        printf 'Conservar: %s\n' "$HOME/.local/bin/$herramienta"
        return
    fi
    printf 'Preparar %s %s\n' "$herramienta" "$version"
    local paquete_comprimido="$directorio_descarga/$herramienta.tar.gz"
    curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 "$direccion_descarga" --output "$paquete_comprimido"
    printf '%s  %s\n' "$huella_sha256" "$paquete_comprimido" | sha256sum --check --status
    mkdir -p "$directorio_descarga/$herramienta"
    tar -xzf "$paquete_comprimido" -C "$directorio_descarga/$herramienta" -- "$archivo_del_paquete"
    [[ -f $directorio_descarga/$herramienta/$archivo_del_paquete && ! -L $directorio_descarga/$herramienta/$archivo_del_paquete ]]
    install -m 755 "$directorio_descarga/$herramienta/$archivo_del_paquete" "$directorio_descarga/$herramienta.bin"
    "$directorio_descarga/$herramienta.bin" --version
    herramientas_pendientes+=("$herramienta")
}

preparar_binario starship v1.26.0 \
    https://github.com/starship/starship/releases/download/v1.26.0/starship-x86_64-unknown-linux-musl.tar.gz \
    b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3 starship
preparar_binario eza v0.23.5 \
    https://github.com/eza-community/eza/releases/download/v0.23.5/eza_x86_64-unknown-linux-musl.tar.gz \
    e06eebab74b73d6b7d51a796a353824b001bea82df077706382e100815d28904 ./eza
preparar_binario fastfetch 2.69.0 \
    https://github.com/fastfetch-cli/fastfetch/releases/download/2.69.0/fastfetch-linux-amd64.tar.gz \
    9fe880a34de3fec88e57a69230c02fd7be0846db3f3ea9f88f2b74489a79ff55 fastfetch-linux-amd64/usr/bin/fastfetch

# Descargar, verificar y probar todos antes de escribir en el usuario.
if (( ${#herramientas_pendientes[@]} )); then
    mkdir -p "$HOME/.local/bin"
    directorio_respaldo="$HOME/.local/state/tunning/backups/$(date +%Y%m%d-%H%M%S-%N)/extras"
    for herramienta in "${herramientas_pendientes[@]}"; do
        ruta_destino="$HOME/.local/bin/$herramienta"
        if [[ -e $ruta_destino || -L $ruta_destino ]]; then
            mkdir -p "$directorio_respaldo"
            cp -a -- "$ruta_destino" "$directorio_respaldo/$herramienta"
            printf 'Respaldo: %s\n' "$directorio_respaldo/$herramienta"
        fi
        archivo_temporal=$(mktemp "$HOME/.local/bin/.tunning-XXXXXX")
        install -m 755 "$directorio_descarga/$herramienta.bin" "$archivo_temporal"
        mv -f -- "$archivo_temporal" "$ruta_destino"
        archivo_temporal=''
        printf 'Instalado: %s\n' "$ruta_destino"
    done
fi
