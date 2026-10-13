#!/usr/bin/env python3
"""Comprueba sintaxis y enlaces locales sin ejecutar instaladores ni usar red."""
import ast
import json
from pathlib import Path
import re
import struct
import subprocess
import tomllib
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent


def prose(path):
    lines = []
    fence = None
    for line in path.read_text().splitlines():
        marker = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        if marker:
            token = marker[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return '\n'.join(lines)


def headings(path):
    found = set()
    used = {}
    for title in re.findall(r'^#{1,6}\s+(.+)$', prose(path), re.MULTILINE):
        slug = re.sub(r'[^\w\- ]', '', title.strip().lower()).replace(' ', '-')
        number = used.get(slug, 0)
        used[slug] = number + 1
        found.add(slug + (f'-{number}' if number else ''))
    return found


def main():
    files = sorted(p for p in ROOT.rglob('*') if p.is_file() and
                   not {'.git', '.agents', '.codex', '.aws', '__pycache__'}.intersection(p.relative_to(ROOT).parts))
    syntax = links = images = 0
    for path in files:
        if path.suffix == '.sh':
            subprocess.run(['bash', '-n', str(path)], check=True)
            syntax += 1
        elif path.suffix == '.py':
            ast.parse(path.read_text(), filename=str(path))
            syntax += 1
        elif path.suffix in {'.json', '.jsonc'}:
            # Las configuraciones JSONC del repo usan comentarios de línea.
            json.loads(re.sub(r'^\s*//.*$', '', path.read_text(), flags=re.MULTILINE))
            syntax += 1
        elif path.suffix == '.toml':
            tomllib.loads(path.read_text())
            syntax += 1
        elif path.suffix == '.md':
            for raw in re.findall(r'\]\(([^)\n]+)\)', prose(path)):
                destination = urlsplit(raw)
                if destination.scheme or destination.netloc:
                    continue
                target = (path.parent / unquote(destination.path)).resolve() if destination.path else path
                if not target.exists():
                    raise ValueError(f'{path.relative_to(ROOT)}: enlace inexistente {raw}')
                if destination.fragment and target.suffix == '.md' and unquote(destination.fragment) not in headings(target):
                    raise ValueError(f'{path.relative_to(ROOT)}: ancla inexistente {raw}')
                links += 1
        elif path.suffix == '.png' and path.parent == ROOT / 'assets':
            data = path.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n' or len(data) < 24 or min(struct.unpack('>II', data[16:24])) == 0:
                raise ValueError(f'{path.relative_to(ROOT)}: PNG inválido')
            images += 1
    embedded = (ROOT / 'scripts/git-sync.sh').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
    ast.parse(embedded, filename='git-sync embedded Python')
    print(f'Sintaxis: {syntax + 1} archivos/bloques; enlaces locales: {links}; imágenes PNG: {images}. OK')


if __name__ == '__main__':
    main()
