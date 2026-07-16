#!/usr/bin/env bash

# Setup script for Terminal PRO (Material MD3)
# Optimized for pure Ubuntu 26.04 (resolute)

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
echo -e "${MAGENTA}   🚀  Instalación de Terminal PRO - Material MD3  🚀   ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo

# 1. Verificar si estamos en Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${BLUE}[i] Detectado:${NC} $NAME $VERSION"
else
    echo -e "${YELLOW}[!] Advertencia: No se pudo verificar la distribución de Linux.${NC}"
fi

# 2. Instalar paquetes de sistema (fastfetch, eza, starship)
echo
echo -e "${YELLOW}[1/5] Instalando herramientas del sistema (fastfetch, eza, starship)...${NC}"
echo -e "${BLUE}[i] Ubuntu 26.04 incluye estas herramientas en sus repositorios oficiales.${NC}"
sudo apt-get update
sudo apt-get install -y fastfetch eza starship curl unzip tar

# 3. Descargar e instalar JetBrainsMono Nerd Font
echo
echo -e "${YELLOW}[2/5] Instalando JetBrainsMono Nerd Font...${NC}"
SYS_FONT_DIR="/usr/share/fonts/truetype/jetbrains-mono-nerd"

if fc-list : family | grep -iq "JetBrainsMono Nerd Font"; then
    echo -e "${GREEN}[✓] JetBrainsMono Nerd Font ya está instalada en el sistema.${NC}"
else
    echo -e "${BLUE}[i] Descargando JetBrainsMono Nerd Font (v3.2.1)...${NC}"
    TEMP_TAR="/tmp/JetBrainsMono.tar.xz"
    
    # Descargar usando curl (siguiendo redirecciones)
    curl -L -f -o "$TEMP_TAR" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz"
    
    echo -e "${BLUE}[i] Extrayendo fuente a nivel de sistema en $SYS_FONT_DIR...${NC}"
    sudo mkdir -p "$SYS_FONT_DIR"
    sudo tar -xf "$TEMP_TAR" -C "$SYS_FONT_DIR"
    
    echo -e "${BLUE}[i] Actualizando la caché de fuentes del sistema...${NC}"
    sudo fc-cache -fv
    
    # Limpieza
    rm -f "$TEMP_TAR"
    echo -e "${GREEN}[✓] JetBrainsMono Nerd Font instalada correctamente en el sistema.${NC}"
fi

# 4. Configurar Starship y Fastfetch
echo
echo -e "${YELLOW}[3/5] Copiando archivos de configuración...${NC}"

# Starship config
mkdir -p "$HOME/.config"
if [ -f configs/starship.toml ]; then
    cp configs/starship.toml "$HOME/.config/starship.toml"
    echo -e "${GREEN}[✓] Configuración de Starship copiada a ~/.config/starship.toml${NC}"
else
    echo -e "${RED}[✗] Error: No se encontró configs/starship.toml${NC}"
    exit 1
fi

# Fastfetch config
mkdir -p "$HOME/.config/fastfetch"
if [ -f configs/fastfetch.jsonc ]; then
    cp configs/fastfetch.jsonc "$HOME/.config/fastfetch/config.jsonc"
    echo -e "${GREEN}[✓] Configuración de Fastfetch copiada a ~/.config/fastfetch/config.jsonc${NC}"
else
    echo -e "${RED}[✗] Error: No se encontró configs/fastfetch.jsonc${NC}"
    exit 1
fi

# 5. Configurar git sync alias
echo
echo -e "${YELLOW}[4/5] Configurando alias git sync...${NC}"

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
    commit_msg="$(whoami)@$(hostname) ${date_str} - ${msg}"; \
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

echo -e "${GREEN}[✓] Alias 'git sync' configurado globalmente.${NC}"

# 6. Configurar .bashrc
echo
echo -e "${YELLOW}[5/5] Integrando configuración en ~/.bashrc...${NC}"

BASHRC="$HOME/.bashrc"
APPEND_FILE="configs/bashrc_append.sh"
MARKER="# === TUNNING TERMINAL SETUP - MATERIAL MD3 ==="

if [ -f "$APPEND_FILE" ]; then
    if grep -qF "$MARKER" "$BASHRC"; then
        echo -e "${BLUE}[i] Las configuraciones ya estaban integradas en ~/.bashrc. Se actualizarán.${NC}"
        
        # Eliminar sección anterior para evitar duplicaciones
        # Usamos un archivo temporal para reescribir .bashrc de forma segura
        TEMP_BASHRC=$(mktemp)
        sed "/$MARKER/,/## FIN TUNNING TERMINAL SETUP ##/d" "$BASHRC" > "$TEMP_BASHRC"
        mv "$TEMP_BASHRC" "$BASHRC"
    fi
    
    # Agregar las nuevas configuraciones con marcadores
    echo -e "\n$MARKER" >> "$BASHRC"
    cat "$APPEND_FILE" >> "$BASHRC"
    echo -e "## FIN TUNNING TERMINAL SETUP ##" >> "$BASHRC"
    
    echo -e "${GREEN}[✓] Integración en ~/.bashrc completada con éxito.${NC}"
else
    echo -e "${RED}[✗] Error: No se encontró $APPEND_FILE${NC}"
    exit 1
fi

echo
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   ✨  ¡CONFIGURACIÓN COMPLETADA CON ÉXITO!  ✨       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo
echo -e "${CYAN}Próximos pasos requeridos:${NC}"
echo -e " 1. ${YELLOW}Recarga tu terminal${NC} ejecutando:"
echo -e "    ${MAGENTA}source ~/.bashrc${NC}"
echo
echo -e " 2. ${YELLOW}Configura la fuente en tu Terminal de Ubuntu:${NC}"
echo -e "    - Si usas ${BLUE}GNOME Terminal${NC} (la terminal por defecto de Ubuntu):"
echo -e "      a. Haz clic derecho en la terminal y ve a ${CYAN}Preferencia (Preferences)${NC}."
echo -e "      b. En el perfil activo (por ejemplo, 'Unnamed'), marca la casilla ${CYAN}\"Custom font\" (Fuente personalizada)${NC}."
echo -e "      c. Busca y selecciona: ${GREEN}JetBrainsMono Nerd Font Mono Regular${NC} o ${GREEN}JetBrainsMono NF Regular${NC}."
echo -e "      d. Guarda y cierra."
echo
echo -e " 🎉 ¡A disfrutar de tu nueva terminal PRO con Material MD3! 🎉"
echo
