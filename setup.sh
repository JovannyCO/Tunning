#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null || { echo 'Instala python3: sudo apt-get install -y python3' >&2; exit 1; }
exec python3 "$SCRIPT_DIR/scripts/install.py" "$@"
