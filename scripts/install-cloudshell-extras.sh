#!/usr/bin/env bash
# Mantiene las herramientas y variantes sin iconos del setup Cloud Shell.
set -euo pipefail
[[ $(uname -m) == x86_64 ]] || { echo 'Los binarios Cloud Shell requieren x86_64.' >&2; exit 1; }
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT
if ! command -v starship >/dev/null; then
    curl -fsSL https://starship.rs/install.sh -o "$download_dir/starship-install.sh"
    sh "$download_dir/starship-install.sh" --yes --bin-dir "$HOME/.local/bin"
fi
if ! command -v eza >/dev/null; then
    curl -fL https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz -o "$download_dir/eza.tar.gz"
    tar -xzf "$download_dir/eza.tar.gz" -C "$download_dir"
    install -m 755 "$download_dir/eza" "$HOME/.local/bin/eza"
fi
if ! command -v fastfetch >/dev/null; then
    curl -fL https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb -o "$download_dir/fastfetch.deb"
    chmod 755 "$download_dir"
    chmod 644 "$download_dir/fastfetch.deb"
    sudo apt-get install -y "$download_dir/fastfetch.deb"
fi
