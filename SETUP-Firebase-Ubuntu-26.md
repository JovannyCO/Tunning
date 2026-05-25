# SETUP — Firebase · Ubuntu 26 · WSL2
> Stack validado: Windows 11 Pro · Dell i7-8650U · 32 GB RAM  
> Fecha: 2026-05-25 | Claude Code 2.1.150 · Antigravity 2 · Firebase CLI 15.18.0

---

## 1. Hardware de referencia

| Componente | Detalle |
|---|---|
| CPU | Intel Core i7-8650U — 4 cores / 8 threads |
| RAM | 32 GB (31.9 utilizable) |
| GPU | Intel UHD 620 (128 MB compartidos de RAM) |
| Almacenamiento | 480 GB usado |

---

## 2. Configuración WSL2

### `%UserProfile%\.wslconfig`
```ini
[wsl2]
memory=20GB
processors=8
swap=6GB
networkingMode=mirrored
dnsTunneling=true
firewall=true

[experimental]
autoMemoryReclaim=gradual
```

> **Notas:**
> - `memory=20GB` — deja 12 GB para Windows + VRAM compartida UHD 620.
> - `pageReportingMode=windows` **no existe** en la doc oficial — omitir.
> - `networkingMode`, `dnsTunneling`, `firewall` van en `[wsl2]`, no en `[experimental]`.

### `/etc/wsl.conf` (dentro de Ubuntu)
```ini
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true
```

> `systemd=true` y `[interop]` pertenecen a `wsl.conf`, **no** a `.wslconfig`.

### Aplicar cambios
```powershell
# PowerShell — esperar ~8 segundos antes de reiniciar
wsl --shutdown
```

---

## 3. Kernel tunables

Archivo: `/etc/sysctl.d/99-wsl-dev.conf`

```bash
sudo tee /etc/sysctl.d/99-wsl-dev.conf << 'EOF'
# inotify: crítico para Antigravity agentes paralelos + Claude Code + TypeScript watcher
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
fs.inotify.max_queued_events=32768

# Memoria: priorizar RAM sobre swap
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

sudo sysctl --system
```

| Parámetro | Valor | Por qué |
|---|---|---|
| `max_user_watches` | 524288 | File watchers TS + Antigravity agents |
| `max_user_instances` | 512 | Agentes paralelos simultáneos |
| `max_queued_events` | 32768 | Burst de eventos en compilación |
| `vm.swappiness` | 10 | 20 GB RAM disponible — evitar swap |
| `vm.vfs_cache_pressure` | 50 | Cachear entradas de `node_modules` |

---

## 4. Instalación del stack

### 4.1 Sistema base
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git build-essential ca-certificates unzip
```

### 4.2 Java 21 LTS (Firebase Emulator Suite)
```bash
sudo apt install -y openjdk-21-jdk-headless
java --version
# openjdk 21.0.11-ea 2026-04-21
```

### 4.3 Node.js via nvm
```bash
# Instalar nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

# Cargar en sesión actual
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Instalar y fijar LTS
nvm install --lts
nvm alias default lts/*
node --version   # v24.16.0
npm --version    # 11.13.0
```

> **Regla Microsoft oficial:** mantener Node.js en el filesystem Linux.  
> Confirmar: `which node` debe apuntar a `/home/<user>/.nvm/...`, **nunca** a `/mnt/c/`.

### 4.4 Firebase CLI
```bash
npm install -g firebase-tools
firebase --version   # 15.18.0
```

### 4.5 Claude Code
```bash
# Instalador nativo oficial (Linux/WSL)
curl -fsSL https://claude.ai/install.sh | bash

# Agregar al PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc

claude --version    # 2.1.150
claude doctor       # verificar tipo de instalación
```

---

## 5. Firebase Agent Skills

Al inicializar un proyecto nuevo, habilitar Agent Skills para que Claude Code y Antigravity 2 operen Firestore, Auth y otros servicios vía MCP:

```bash
cd ~/projects/mi-app
firebase init
# → "Would you like to install agent skills for Firebase?" → Yes
```

Archivos generados: `firebase.json`, `.firebaserc`, `.gitignore`

---

## 6. Workspace — regla de oro

```
✅  ~/projects/mi-app/     →  I/O nativo ~1 GB/s
❌  /mnt/c/Users/.../      →  I/O cross-filesystem ~100 MB/s
```

```bash
mkdir -p ~/projects
cd ~/projects/mi-app
claude        # Claude Code
# o abrir con Antigravity 2 desde este path
```

---

## 7. Verificación del entorno

```bash
# Stack completo
node --version && npm --version && firebase --version && \
  java --version 2>&1 | head -1 && claude --version

# Tunables activos
cat /proc/sys/fs/inotify/max_user_watches    # 524288
cat /proc/sys/fs/inotify/max_user_instances  # 512
cat /proc/sys/vm/swappiness                   # 10

# Recursos WSL
free -h | grep Mem   # ~19 Gi total, ~18 Gi disponible
nproc                # 8
```

### Smoke test Firebase Emulator
```bash
cd ~/projects/mi-app
firebase emulators:start --only firestore,auth --project demo-test
# Emulator UI → http://localhost:4000
# Firestore   → http://localhost:8080
# Auth        → http://localhost:9099
```

---

## 8. Referencia rápida — comandos clave

```bash
# WSL
wsl --shutdown                        # reiniciar WSL (aplicar .wslconfig)
wsl --list --running                  # ver distros activas

# nvm
nvm use --lts                         # usar LTS en proyecto actual
nvm ls                                # listar versiones instaladas

# Firebase
firebase login --no-localhost         # login en WSL (copia link al browser)
firebase emulators:start              # arrancar todos los emulators
firebase deploy                       # deploy a producción

# Claude Code
claude                                # iniciar sesión interactiva
claude doctor                         # diagnóstico de instalación
```

---

## 9. Versiones validadas

| Componente | Versión |
|---|---|
| WSL2 Kernel | 6.6.87.2-microsoft-standard-WSL2 |
| Ubuntu | 26 |
| Node.js | v24.16.0 LTS |
| npm | 11.13.0 |
| Firebase CLI | 15.18.0 |
| Java | OpenJDK 21.0.11-ea |
| Claude Code | 2.1.150 |
| Antigravity | 2.0 |
