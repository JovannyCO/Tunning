# Tunning — Terminal PRO Setup

Setup completo para una terminal de desarrollo profesional con estética **Material Design 3**.

## Paleta MD3
| Rol | Color |
|-----|-------|
| Primario | `#FF6D00` naranja |
| Secundario | `#00897B` teal |
| Superficie | `#1C1B1F` |
| Superficie variante | `#2B2930` |

## Stack
| Herramienta | Propósito |
|-------------|-----------|
| [Starship](https://starship.rs) | Prompt con cápsulas redondeadas MD3 |
| [fastfetch](https://github.com/fastfetch-cli/fastfetch) | Bienvenida al abrir terminal |
| [eza](https://github.com/eza-community/eza) | `ls` moderno con íconos Nerd Font |
| JetBrainsMono Nerd Font Mono | Fuente developer con íconos |
| Windows Terminal | Color scheme Material MD3 |

## Prompt

```
( Ubuntu  me@DELL )  (  ~/proyecto )  (  main ↑1 )  ────  ( 22:45 )
╰ ❯
```

### Indicadores git
| Símbolo | Significado |
|---------|-------------|
| ` N` | N commits sin push |
| ` N` | N commits por jalar |
| ` ` | Archivos modificados |
| ` ` | Cambios stageados |
| ` ` | Archivos sin rastrear |
| sin flecha | Sincronizado con remoto |

---

## 🔄 Git Sync (Sincronización automatizada)

El entorno local cuenta con un alias avanzado para Git que simplifica el flujo de desarrollo.

### ¿Qué hace `git sync`?
Este comando automatiza el proceso de commit y push de forma segura en un solo paso:
1. **Stage**: Agrega todos los cambios (`git add -A`).
2. **Commit firmado**: Crea un commit (`-S`) con un mensaje estructurado.
   - Formato: `usuario@hostname fecha - mensaje`
   - Ejemplo: `i7@DELL 16julio09:34 - Cambios en la matrix`
3. **Pull actual**: Hace pull de la rama actual (`origin $current_branch`) para evitar conflictos locales.
4. **Pull production**: Hace pull de la rama `production` desde `origin`.
5. **Push**: Sube los cambios locales (`origin HEAD`).

### Uso
- Sin argumentos (mensaje por defecto): `git sync`
- Con mensaje personalizado: `git sync "Fix del botón de login"`

### Configuración en Ubuntu 26
Para añadir este alias a tu entorno global, copia y pega el siguiente bloque en tu terminal:

```bash
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
    echo "=> Creating signed commit: \"$commit_msg\"..."; \
    git commit -S -m "$commit_msg" && \
    echo "=> Pulling from origin $current_branch..."; \
    git pull origin "$current_branch" && \
    echo "=> Pulling from origin production..."; \
    git pull origin production && \
    echo "=> Pushing to origin..."; \
    git push origin HEAD; \
}; f'
```

---


## Entornos soportados

### 🖥️ Ubuntu 26.04 en WSL2

Entorno principal. Usa `setup.sh` que instala vía `apt` y configura la fuente Nerd Font a nivel de sistema.

```bash
chmod +x setup.sh && bash setup.sh
source ~/.bashrc
```

**Fuente (Windows):** Instalar **JetBrainsMono Nerd Font Mono** v3.4.0 desde
[nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases/latest).

Windows Terminal → Settings → perfil Ubuntu → Font face: `JetBrainsMono Nerd Font Mono`

### ☁️ Google Cloud Shell Editor

Adaptado para Cloud Shell (Ubuntu 24.04 Noble). Diferencias clave:

| Aspecto | WSL2 / Ubuntu 26 | Cloud Shell Editor |
|---------|-------------------|--------------------|
| Instalación | `sudo apt install` | Binarios en `~/.local/bin` (starship, eza) + `.deb` (fastfetch) |
| Hostname | Dinámico (`$hostname`) | Fijo: `CSE` (Cloud Shell Editor) |
| Fuentes | Nerd Font instalada en sistema | Depende del navegador (ver nota) |
| Windows Terminal | Esquema de color Material MD3 | N/A |
| `bashrc.google` | N/A | Se preserva `source /google/devshell/bashrc.google` |
| Persistencia | Disco local | `~/` persiste entre sesiones de Cloud Shell |

```bash
chmod +x setup-cloudshell.sh && bash setup-cloudshell.sh
source ~/.bashrc
```

> **Nota sobre fuentes en Cloud Shell:** Cloud Shell renderiza la terminal en el navegador.
> Para ver los íconos Nerd Font correctamente, instala
> [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest)
> en tu **máquina local** y configúrala en la terminal del navegador
> (Chrome → DevTools → Settings no aplica; usa una extensión como
> [Custom CSS](https://chromewebstore.google.com/detail/custom-css) o accede
> desde un emulador de terminal externo con SSH).

## Estructura del repo

```
Tunning/
├── README.md
├── SETUP-Firebase-Ubuntu-26.md
├── setup.sh                          # Instalador para Ubuntu 26 / WSL2
├── setup-cloudshell.sh               # Instalador para Google Cloud Shell Editor
└── configs/
    ├── bashrc_append.sh              # Aliases, funciones, historia (compartido)
    ├── starship.toml                 # Prompt Starship — hostname dinámico
    ├── starship-cloudshell.toml      # Prompt Starship — hostname fijo "CSE"
    ├── fastfetch.jsonc               # Bienvenida fastfetch (compartido)
    └── windows_terminal_scheme.json  # Esquema de color para Windows Terminal
```

## Instalación rápida (manual)

```bash
# Dependencias
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
sudo apt-get update && sudo apt-get install -y fastfetch

curl -fLo /tmp/eza.tar.gz \
  https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz
tar -xzf /tmp/eza.tar.gz -C /tmp/ && sudo mv /tmp/eza /usr/local/bin/eza

curl -sS https://starship.rs/install.sh | sh

# Configs
mkdir -p ~/.config/fastfetch
cp configs/starship.toml ~/.config/starship.toml          # o starship-cloudshell.toml
cp configs/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
cat configs/bashrc_append.sh >> ~/.bashrc
```
