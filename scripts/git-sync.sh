#!/usr/bin/env bash
# git sync: commit firmado, integración de origin y push, deteniéndose ante errores.
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    cat <<'EOF'
Uso: git sync ["mensaje"]
Agrega todos los cambios, crea un commit si hace falta, integra la rama remota
y production (si existe) mediante merge y publica la rama actual.
Configuración: tunning.syncSign (true por defecto), tunning.syncProduction (true).
Con syncSign=false se respeta la configuración habitual commit.gpgsign de Git.
EOF
    exit 0
fi

fail() { printf 'git sync: %s\n' "$*" >&2; exit 1; }
root=$(git rev-parse --show-toplevel) || fail 'Ejecuta el comando dentro de un repositorio.'
cd "$root"
branch=$(git symbolic-ref --quiet --short HEAD) || fail 'HEAD está separado; selecciona una rama.'
git remote get-url origin >/dev/null || fail 'Falta el remoto origin.'
for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ ! -e $(git rev-parse --git-path "$state") ]] || fail 'Hay una operación Git pendiente; resuélvela primero.'
done

config_bool() {
    local value status
    if value=$(git config --type=bool --get "$1"); then
        printf '%s' "$value"
    else
        status=$?
        [[ $status == 1 ]] || return "$status"
        printf '%s' "$2"
    fi
}
sign=$(config_bool tunning.syncSign true)
production=$(config_bool tunning.syncProduction true)
sign_args=()
[[ $sign != true ]] || sign_args=(-S)

printf '=> Agregando cambios...\n'
git add -A
if git diff --cached --quiet; then
    printf '=> No hay cambios para crear un commit.\n'
else
    status=$?
    [[ $status == 1 ]] || exit "$status"
    months=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    read -r day month time < <(date '+%d %m %H:%M')
    host=$(hostname)
    if [[ ${TUNNING_PROFILE:-} == cloudshell || -n ${CLOUD_SHELL:-} || -f /google/devshell/bashrc.google ]]; then
        host=CSE
    fi
    message="$(whoami)@${host} ${day#0}${months[10#$month-1]}${time} - ${*:-Cambios en la matrix}"
    printf '=> Creando commit: %s\n' "$message"
    git commit "${sign_args[@]}" -m "$message"
fi
git rev-parse --verify HEAD >/dev/null || fail 'La rama todavía no tiene commits.'

# Una salida vacía indica rama ausente; un error de red debe detener el flujo.
heads=$(git ls-remote --heads origin "refs/heads/$branch" refs/heads/production)
has_branch=false
has_production=false
while read -r oid ref; do
    [[ $ref != "refs/heads/$branch" ]] || has_branch=true
    [[ $ref != refs/heads/production ]] || has_production=true
done <<< "$heads"
if [[ $has_branch == true ]]; then
    printf '=> Integrando origin/%s...\n' "$branch"
    git pull --no-rebase --no-edit --no-autostash "${sign_args[@]}" origin "$branch"
fi
if [[ $production == true && $has_production == true && $branch != production ]]; then
    printf '=> Integrando origin/production...\n'
    git pull --no-rebase --no-edit --no-autostash "${sign_args[@]}" origin production
fi
printf '=> Publicando %s...\n' "$branch"
git push --set-upstream origin "HEAD:refs/heads/$branch"
