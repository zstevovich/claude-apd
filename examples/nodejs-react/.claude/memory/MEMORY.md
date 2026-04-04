# TaskFlow — Memorija projekta

## Uloga

Orkestrator. Delegiram agentima, ne implementiram direktno osim trivijalnog.

## Okruženje

- **Skripte:** guard-git, guard-scope, guard-bash-scope, guard-secrets, guard-lockfile, pipeline-advance, pipeline-gate, rotate-session-log, session-start, verify-all
- **Agenti:** backend-builder, frontend-builder, testing, devops
- **Rules:** workflow, principles
- **Pipeline:** Spec → Builder → Reviewer → Verifier → Commit (tehnički zaštićen)

## Brza referenca

| Stavka | Vrednost |
|--------|---------|
| Stack | Node.js + Express, React + Vite, PostgreSQL |
| Grane | develop → staging → main |
| Port range | 3000+ |

## Memory fajlovi (po temama)

### Status
- [status.md](status.md) — aktuelna faza i fokus
- [session-log.md](session-log.md) — hronološki pregled sesija
- [pipeline-skip-log.md](pipeline-skip-log.md) — skip log za analizu
