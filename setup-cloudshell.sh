#!/usr/bin/env bash
set -euo pipefail
DIRECTORIO_INSTALADOR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIRECTORIO_INSTALADOR/setup.sh" --profile cloudshell "$@"
