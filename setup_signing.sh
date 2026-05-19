#!/usr/bin/env bash

# Setup script for Git Commit/Tag Signing
# Works with GPG or SSH (recommended)
# Optimized for Ubuntu 26.04 and modern Git

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
echo -e "${MAGENTA}   🔐  Configurador de Firma de Commits Git  🔐   ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo

# 1. Obtener datos de Git actual
GIT_USER=$(git config --global user.name || echo "")
GIT_EMAIL=$(git config --global user.email || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
    echo -e "${YELLOW}[!] Advertencia: No se detectó configuración global de usuario en Git.${NC}"
    read -rp "Ingresa tu nombre para Git (ej. Juan Pérez): " GIT_USER
    read -rp "Ingresa tu correo para Git (ej. juan@ejemplo.com): " GIT_EMAIL
    git config --global user.name "$GIT_USER"
    git config --global user.email "$GIT_EMAIL"
    echo -e "${GREEN}[✓] Configuración global de Git guardada.${NC}"
else
    echo -e "${BLUE}[i] Detectado usuario Git:${NC} $GIT_USER <$GIT_EMAIL>"
fi

echo
echo -e "${CYAN}Elige el método de firma preferido:${NC}"
echo -e "  ${GREEN}1)${NC} ${BOLD:-}Firma SSH${NC} (Recomendado: súper rápido, moderno y fácil de configurar)"
echo -e "  ${GREEN}2)${NC} ${BOLD:-}Firma GPG${NC} (Tradicional, requiere passphrase y dependencias GPG)"
read -rp "Selecciona una opción (1 o 2) [Por defecto: 1]: " OPTION
OPTION=${OPTION:-1}

setup_ssh() {
    echo
    echo -e "${YELLOW}[i] Configurando Firma de Commits con SSH...${NC}"
    
    KEY_PATH="$HOME/.ssh/id_ed25519_signing"
    
    if [ -f "$KEY_PATH" ]; then
        echo -e "${YELLOW}[!] Ya existe una llave de firma SSH en $KEY_PATH.${NC}"
        read -rp "¿Deseas sobrescribirla? (s/N): " OVERWRITE
        OVERWRITE=${OVERWRITE:-n}
        if [[ "$OVERWRITE" =~ ^[Ss]$ ]]; then
            rm -f "$KEY_PATH" "${KEY_PATH}.pub"
            ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_PATH" -N ""
            echo -e "${GREEN}[✓] Nueva llave generada.${NC}"
        else
            echo -e "${BLUE}[i] Usando llave SSH existente.${NC}"
        fi
    else
        echo -e "${BLUE}[i] Generando llave SSH Ed25519 para firma...${NC}"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$KEY_PATH" -N ""
        echo -e "${GREEN}[✓] Llave generada exitosamente en $KEY_PATH.${NC}"
    fi

    # Configurar Git para usar SSH
    echo -e "${BLUE}[i] Aplicando configuraciones globales de Git...${NC}"
    git config --global gpg.format ssh
    git config --global user.signingkey "${KEY_PATH}.pub"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    echo -e "${GREEN}[✓] ¡Git configurado para firmar con SSH!${NC}"
    echo
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}   🎉  ¡PASO FINAL REQUERIDO EN TU CUENTA DE GITHUB!  🎉${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo
    echo -e "1. Copia tu llave pública de firma mostrada abajo:"
    echo -e "${YELLOW}"
    cat "${KEY_PATH}.pub"
    echo -e "${NC}"
    echo -e "2. Ve a tu cuenta de GitHub: ${BLUE}https://github.com/settings/keys${NC}"
    echo -e "3. Haz clic en ${GREEN}\"New SSH key\" (Nueva llave SSH)${NC}."
    echo -e "4. En ${CYAN}\"Title\" (Título)${NC}, pon algo descriptivo (ej. 'Firma PC i5')."
    echo -e "5. En ${CYAN}\"Key type\" (Tipo de llave)${NC}, selecciona ${MAGENTA}\"Signing Key\" (Llave de Firma)${NC}. ${RED}<- ¡MUY IMPORTANTE!${NC}"
    echo -e "6. Pega el contenido de la llave copiada en el campo de texto."
    echo -e "7. Haz clic en ${GREEN}\"Add SSH key\"${NC}."
}

setup_gpg() {
    echo
    echo -e "${YELLOW}[i] Configurando Firma de Commits con GPG...${NC}"
    
    if ! command -v gpg &>/dev/null; then
        echo -e "${BLUE}[i] Instalando gpg en el sistema...${NC}"
        sudo apt-get update && sudo apt-get install -y gnupg
    fi

    # Listar llaves existentes
    KEYS=$(gpg --list-secret-keys --keyid-format=long || echo "")
    
    if [ -n "$KEYS" ]; then
        echo -e "${GREEN}[✓] Llaves GPG existentes detectadas:${NC}"
        gpg --list-secret-keys --keyid-format=long
        echo
        read -rp "Ingresa el ID de la llave GPG que deseas usar (ej. 3AA5C34371567BD2) o presiona ENTER para generar una nueva: " GPG_KEY_ID
    else
        GPG_KEY_ID=""
    fi

    if [ -z "$GPG_KEY_ID" ]; then
        echo -e "${BLUE}[i] Generando nueva llave GPG...${NC}"
        echo -e "${YELLOW}[!] Se te solicitará tu nombre, correo y una contraseña segura en la terminal.${NC}"
        echo
        
        # Crear archivo de configuración temporal para lote o usar el modo interactivo
        gpg --full-generate-key
        
        # Obtener el ID de la llave recién creada
        GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format=long | grep sec | head -n1 | awk '{print $2}' | cut -d'/' -f2 || "")
        
        if [ -z "$GPG_KEY_ID" ]; then
            echo -e "${RED}[✗] Error: No se pudo recuperar el ID de la llave GPG generada.${NC}"
            exit 1
        fi
        echo -e "${GREEN}[✓] Nueva llave GPG detectada: $GPG_KEY_ID${NC}"
    fi

    # Configurar Git para usar GPG
    echo -e "${BLUE}[i] Aplicando configuraciones globales de Git...${NC}"
    git config --global gpg.format openpgp
    git config --global user.signingkey "$GPG_KEY_ID"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true

    echo -e "${GREEN}[✓] ¡Git configurado para firmar con GPG!${NC}"
    echo
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}   🎉  ¡PASO FINAL REQUERIDO EN TU CUENTA DE GITHUB!  🎉${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo
    echo -e "1. Exporta tu llave pública GPG con el siguiente comando (ya formateado):"
    echo -e "${YELLOW}gpg --armour --export $GPG_KEY_ID${NC}"
    echo -e "   Aquí tienes el contenido directo para copiar:"
    echo -e "${BLUE}"
    gpg --armour --export "$GPG_KEY_ID"
    echo -e "${NC}"
    echo -e "2. Ve a tu cuenta de GitHub: ${BLUE}https://github.com/settings/keys${NC}"
    echo -e "3. Haz clic en ${GREEN}\"New GPG key\" (Nueva llave GPG)${NC}."
    echo -e "4. Pega el bloque de texto completo (incluyendo los encabezados BEGIN y END)."
    echo -e "5. Haz clic en ${GREEN}\"Add GPG key\"${NC}."
}

if [ "$OPTION" -eq 1 ]; then
    setup_ssh
else
    setup_gpg
fi

echo
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}  🚀 ¡Felicidades! Todo está configurado localmente. ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Una vez que hayas agregado la llave a GitHub, tus nuevos commits"
echo -e "mostrarán automáticamente el tag verde ${GREEN}Verified${NC}."
echo
