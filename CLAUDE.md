# Instrucciones para Claude Code en este repo

- **Nunca firmes commits** (`git commit -S` ni ningún flag de firma GPG/SSH). Usa siempre `--no-gpg-sign` explícito al commitear, incluso si `commit.gpgsign=true` está activo globalmente en la máquina. Solo el dueño del repo firma sus propios commits.
- **Nunca agregues atribución de Claude** a commits ni PRs: nada de `Co-Authored-By: Claude`, `Claude-Session:`, ni el pie "🤖 Generated with Claude Code". El usuario paga la suscripción; eso no incluye publicidad de Claude/Anthropic en su historial de git.

Esto ya se refuerza en `.claude/settings.json` (`attribution.commit`/`attribution.pr` vacíos, `sessionUrl: false`), pero la regla aplica siempre — en cualquier rama, máquina o herramienta usada para trabajar en este repo.
