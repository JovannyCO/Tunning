#!/usr/bin/env bash
# El contrato de criterios vive en el motor común instalado.
set -euo pipefail
exec bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/git-sync.sh" --tunning-mode=criteria "$@"
