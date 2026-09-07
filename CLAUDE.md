# Instrucciones para Claude Code en este repo

- **Nunca firmes commits** (`git commit -S` ni ningún flag de firma GPG/SSH). Usa siempre `--no-gpg-sign` explícito al commitear, incluso si `commit.gpgsign=true` está activo globalmente en la máquina. Solo el dueño del repo firma sus propios commits.
- **Nunca agregues atribución de Claude** a commits ni PRs: nada de `Co-Authored-By: Claude`, `Claude-Session:`, ni el pie "🤖 Generated with Claude Code". El usuario paga la suscripción; eso no incluye publicidad de Claude/Anthropic en su historial de git.

Esto ya se refuerza en `.claude/settings.json` (`attribution.commit`/`attribution.pr` vacíos, `sessionUrl: false`), pero la regla aplica siempre — en cualquier rama, máquina o herramienta usada para trabajar en este repo.

- **Nunca invoques el alias global `git sync` directamente** (ni en este repo ni en ningún otro): tiene `git commit -S` fijo en el código del alias y el primer argumento se usa como mensaje del commit, no se reenvía a `git commit` — o sea, `git sync --no-gpg-sign "msg"` NO desactiva la firma, solo mete el texto "--no-gpg-sign" en el mensaje y firma igual. Si necesitas el flujo de `git sync` (stage + commit + pull + push), replica los pasos a mano con `git commit --no-gpg-sign` en vez de invocar el alias.
