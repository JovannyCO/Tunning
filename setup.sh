#!/usr/bin/env bash
set -euo pipefail
DIRECTORIO_INSTALADOR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    echo 'Se requiere Bash 4.4 o posterior para instalar Terminal Tuning.' >&2
    exit 1
fi
exec bash "$DIRECTORIO_INSTALADOR/scripts/install.sh" "$@"
