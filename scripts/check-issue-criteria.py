#!/usr/bin/env python3
"""Validación local; el contrato de criterios vive en el motor común instalado."""
from pathlib import Path
import subprocess
import sys


if __name__ == '__main__':
    engine = Path(__file__).with_name('git-sync.sh')
    raise SystemExit(subprocess.call(['bash', str(engine), '--tunning-mode=criteria', *sys.argv[1:]]))
