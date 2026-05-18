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

## Instalación rápida

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
cp configs/starship.toml ~/.config/starship.toml
cp configs/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
cat configs/bashrc_append.sh >> ~/.bashrc
```

## Fuente (Windows)
Instalar **JetBrainsMono Nerd Font Mono** v3.4.0 desde
[nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases/latest).

Windows Terminal → Settings → perfil Ubuntu → Font face: `JetBrainsMono Nerd Font Mono`
