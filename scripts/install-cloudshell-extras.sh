#!/usr/bin/env bash
# Versiones oficiales verificadas el 2026-10-13. No ejecuta instaladores remotos.
set -Eeuo pipefail
[[ $(uname -m) == x86_64 ]] || { echo 'Los binarios Cloud Shell requieren x86_64.' >&2; exit 1; }
for dependency in curl tar sha256sum install mktemp; do
    command -v "$dependency" >/dev/null || { echo "Falta $dependency." >&2; exit 1; }
done
download_dir=$(mktemp -d)
temporary=''
tool='preparación'
trap 'rm -rf -- "$download_dir"; [[ -z $temporary ]] || rm -f -- "$temporary"' EXIT
trap 'printf "Error al preparar %s para Cloud Shell; instalación incompleta.\n" "$tool" >&2' ERR
pending=()

fetch_binary() {
    local version=$2 url=$3 checksum=$4 member=$5
    tool=$1
    # Un binario del sistema puede desaparecer con la VM. Conservar solo copias
    # ejecutables normales dentro de HOME; no seguir enlaces al reemplazarlas.
    if [[ -x $HOME/.local/bin/$tool && ! -L $HOME/.local/bin/$tool ]]; then
        printf 'Conservar: %s\n' "$HOME/.local/bin/$tool"
        return
    fi
    printf 'Preparar %s %s\n' "$tool" "$version"
    local archive="$download_dir/$tool.tar.gz"
    curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 "$url" --output "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
    mkdir -p "$download_dir/$tool"
    tar -xzf "$archive" -C "$download_dir/$tool" -- "$member"
    [[ -f $download_dir/$tool/$member && ! -L $download_dir/$tool/$member ]]
    install -m 755 "$download_dir/$tool/$member" "$download_dir/$tool.bin"
    "$download_dir/$tool.bin" --version
    pending+=("$tool")
}

fetch_binary starship v1.26.0 \
    https://github.com/starship/starship/releases/download/v1.26.0/starship-x86_64-unknown-linux-musl.tar.gz \
    b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3 starship
fetch_binary eza v0.23.5 \
    https://github.com/eza-community/eza/releases/download/v0.23.5/eza_x86_64-unknown-linux-musl.tar.gz \
    e06eebab74b73d6b7d51a796a353824b001bea82df077706382e100815d28904 ./eza
fetch_binary fastfetch 2.69.0 \
    https://github.com/fastfetch-cli/fastfetch/releases/download/2.69.0/fastfetch-linux-amd64.tar.gz \
    9fe880a34de3fec88e57a69230c02fd7be0846db3f3ea9f88f2b74489a79ff55 fastfetch-linux-amd64/usr/bin/fastfetch

# Descargar, verificar y probar todos antes de escribir en el usuario.
if (( ${#pending[@]} )); then
    mkdir -p "$HOME/.local/bin"
    backup="$HOME/.local/state/tunning/backups/$(date +%Y%m%d-%H%M%S-%N)/extras"
    for tool in "${pending[@]}"; do
        destination="$HOME/.local/bin/$tool"
        if [[ -e $destination || -L $destination ]]; then
            mkdir -p "$backup"
            cp -a -- "$destination" "$backup/$tool"
            printf 'Respaldo: %s\n' "$backup/$tool"
        fi
        temporary=$(mktemp "$HOME/.local/bin/.tunning-XXXXXX")
        install -m 755 "$download_dir/$tool.bin" "$temporary"
        mv -f -- "$temporary" "$destination"
        temporary=''
        printf 'Instalado: %s\n' "$destination"
    done
fi
