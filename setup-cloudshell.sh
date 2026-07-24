#!/usr/bin/env bash

# Setup script for Terminal PRO (Material MD3)
# Adapted for Google Cloud Shell Editor (Ubuntu 24.04 Noble)

set -euo pipefail

# Colores para salida elegante
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}====================================================${NC}"
echo -e "${MAGENTA}   🚀  Terminal PRO - Material MD3 (Cloud Shell)  🚀  ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo

# 1. Detectar entorno
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${BLUE}[i] Detectado:${NC} $NAME $VERSION"
else
    echo -e "${YELLOW}[!] No se pudo verificar la distribución.${NC}"
fi

if [ -f /google/devshell/bashrc.google ]; then
    echo -e "${BLUE}[i] Entorno:${NC} Google Cloud Shell ✓"
else
    echo -e "${YELLOW}[!] No parece ser Google Cloud Shell. Procediendo igualmente...${NC}"
fi

# 2. Crear directorios necesarios
echo
echo -e "${YELLOW}[1/7] Preparando directorios...${NC}"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/fastfetch"
export PATH="$HOME/.local/bin:$PATH"
echo -e "${GREEN}[✓] Directorios listos.${NC}"

# 3. Instalar Starship
echo
echo -e "${YELLOW}[2/7] Instalando Starship prompt...${NC}"
if command -v starship &>/dev/null; then
    echo -e "${GREEN}[✓] Starship ya está instalado: $(starship --version 2>/dev/null | head -1)${NC}"
else
    echo -e "${BLUE}[i] Descargando e instalando Starship...${NC}"
    curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
    echo -e "${GREEN}[✓] Starship instalado en ~/.local/bin/starship${NC}"
fi

# 4. Instalar eza
echo
echo -e "${YELLOW}[3/7] Instalando eza (ls moderno)...${NC}"
if command -v eza &>/dev/null; then
    echo -e "${GREEN}[✓] eza ya está instalado.${NC}"
else
    echo -e "${BLUE}[i] Descargando eza...${NC}"
    EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
    EZA_URL="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"
    curl -fLo /tmp/eza.tar.gz "$EZA_URL"
    tar -xzf /tmp/eza.tar.gz -C /tmp/
    mv /tmp/eza "$HOME/.local/bin/eza"
    chmod +x "$HOME/.local/bin/eza"
    rm -f /tmp/eza.tar.gz
    echo -e "${GREEN}[✓] eza instalado en ~/.local/bin/eza${NC}"
fi

# 5. Instalar fastfetch
echo
echo -e "${YELLOW}[4/7] Instalando fastfetch...${NC}"
if command -v fastfetch &>/dev/null; then
    echo -e "${GREEN}[✓] fastfetch ya está instalado.${NC}"
else
    echo -e "${BLUE}[i] Descargando fastfetch...${NC}"
    FF_VERSION=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    FF_URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
    curl -fLo /tmp/fastfetch.deb "$FF_URL"
    sudo dpkg -i /tmp/fastfetch.deb || sudo apt-get install -f -y
    rm -f /tmp/fastfetch.deb
    echo -e "${GREEN}[✓] fastfetch instalado.${NC}"
fi

# 6. Copiar archivos de configuración (adaptados para Cloud Shell)
echo
echo -e "${YELLOW}[5/7] Copiando configuraciones adaptadas para Cloud Shell...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Starship config — versión Cloud Shell (hostname = CSE)
cp "$SCRIPT_DIR/configs/starship-cloudshell.toml" "$HOME/.config/starship.toml"
echo -e "${GREEN}[✓] Starship config (Cloud Shell) → ~/.config/starship.toml${NC}"

# Fastfetch config — versión Cloud Shell (sin íconos Nerd Font en las keys;
# el panel de terminal no puede pintarlos, ver nota en starship-cloudshell.toml)
cp "$SCRIPT_DIR/configs/fastfetch-cloudshell.jsonc" "$HOME/.config/fastfetch/config.jsonc"
echo -e "${GREEN}[✓] Fastfetch config (Cloud Shell, sin íconos) → ~/.config/fastfetch/config.jsonc${NC}"

# 7. Configurar git sync alias (hostname = CSE)
echo
echo -e "${YELLOW}[6/7] Configurando alias git sync (hostname=CSE)...${NC}"

git config --global alias.sync '!f() { \
    msg="${1:-Cambios en la matrix}"; \
    m_num=$(date +%m); \
    case "$m_num" in \
        01) m_name="enero" ;; \
        02) m_name="febrero" ;; \
        03) m_name="marzo" ;; \
        04) m_name="abril" ;; \
        05) m_name="mayo" ;; \
        06) m_name="junio" ;; \
        07) m_name="julio" ;; \
        08) m_name="agosto" ;; \
        09) m_name="septiembre" ;; \
        10) m_name="octubre" ;; \
        11) m_name="noviembre" ;; \
        12) m_name="diciembre" ;; \
    esac; \
    day=$(date +%d); \
    day=${day#0}; \
    date_str="${day}${m_name}$(date +%H:%M)"; \
    commit_msg="$(whoami)@CSE ${date_str} - ${msg}"; \
    current_branch=$(git branch --show-current); \
    echo "=> Staging all changes..."; \
    git add -A; \
    echo "=> Creating commit: \"$commit_msg\"..."; \
    git commit -m "$commit_msg" && \
    echo "=> Pulling from origin $current_branch..."; \
    git pull origin "$current_branch" && \
    if git ls-remote --exit-code --heads origin production >/dev/null 2>&1; then \
        echo "=> Pulling from origin production..."; \
        git pull origin production; \
    fi && \
    echo "=> Pushing to origin..."; \
    git push origin HEAD; \
}; f'

echo -e "${GREEN}[✓] Alias 'git sync' configurado globalmente (hostname=CSE).${NC}"

# 8. Configurar .bashrc
echo
echo -e "${YELLOW}[7/7] Integrando configuración en ~/.bashrc...${NC}"

BASHRC="$HOME/.bashrc"
APPEND_FILE="$SCRIPT_DIR/configs/bashrc_append.sh"
MARKER="# === TUNNING TERMINAL SETUP - MATERIAL MD3 ==="
END_MARKER="## FIN TUNNING TERMINAL SETUP ##"
GOOGLE_LINE="source /google/devshell/bashrc.google"

if [ -f "$APPEND_FILE" ]; then
    # Eliminar sección anterior si existe
    if grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
        echo -e "${BLUE}[i] Configuración previa encontrada. Actualizando...${NC}"
        TEMP_BASHRC=$(mktemp)
        sed "/$MARKER/,/$END_MARKER/d" "$BASHRC" > "$TEMP_BASHRC"
        mv "$TEMP_BASHRC" "$BASHRC"
    fi

    # Primero removemos la línea de Google Cloud Shell si ya existe, para reinsertarla
    # en la posición correcta (ver nota IMPORTANTE abajo).
    if grep -qF "$GOOGLE_LINE" "$BASHRC" 2>/dev/null; then
        TEMP_BASHRC=$(mktemp)
        grep -vF "$GOOGLE_LINE" "$BASHRC" > "$TEMP_BASHRC"
        mv "$TEMP_BASHRC" "$BASHRC"
    fi

    # IMPORTANTE: bashrc.google debe cargarse ANTES del bloque Tunning, no después.
    # bashrc.google define sus propios alias (ls, ll, la, l, grep...) sin condicional;
    # si se carga al final, esos alias pisan silenciosamente los de eza/colores de
    # Tunning y el tema "Terminal PRO" deja de verse pese a estar instalado.
    # Cargándolo primero, Cloud Shell inicializa su entorno (Docker, PATH de gcloud,
    # chequeo de disco, etc.) con normalidad y el bloque Tunning queda como última
    # palabra sobre el prompt y los alias visibles.
    {
        echo ""
        echo "# === Google Cloud Shell (NO ELIMINAR) ==="
        echo "$GOOGLE_LINE"
        echo ""
        echo "$MARKER"
        cat "$APPEND_FILE"
        echo "$END_MARKER"
    } >> "$BASHRC"

    echo -e "${GREEN}[✓] ~/.bashrc actualizado exitosamente.${NC}"
else
    echo -e "${RED}[✗] Error: No se encontró $APPEND_FILE${NC}"
    exit 1
fi

echo
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   ✨  ¡CONFIGURACIÓN COMPLETADA CON ÉXITO!  ✨       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo
echo -e "${CYAN}Diferencias con WSL2/Ubuntu 26:${NC}"
echo -e " • ${BLUE}Fuentes:${NC} Cloud Shell usa la fuente del navegador."
echo -e "   Los íconos Nerd Font se verán si tu navegador tiene soporte."
echo -e "   Tip: Instala una Nerd Font en tu sistema local y configúrala"
echo -e "   en la terminal de tu navegador (Chrome/Firefox)."
echo -e " • ${BLUE}Herramientas:${NC} Instaladas en ~/.local/bin (sin sudo para eza/starship)."
echo -e " • ${BLUE}Persistencia:${NC} Cloud Shell conserva ~/  entre sesiones, así que"
echo -e "   ~/.local/bin, ~/.config y ~/.bashrc persisten."
echo
echo -e "${CYAN}Para aplicar ahora:${NC}"
echo -e "    ${MAGENTA}source ~/.bashrc${NC}"
echo
echo -e " 🎉 ¡A disfrutar de tu terminal PRO en Cloud Shell! 🎉"
echo
