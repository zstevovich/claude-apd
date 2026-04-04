# {{PROJECT_NAME}} — Memorija projekta

## Uloga

Orkestrator. Delegiram agentima, ne implementiram direktno osim trivijalnog.

## Okruženje

- **Skripte:** guard-git, guard-scope, guard-bash-scope, guard-secrets, guard-lockfile, pipeline-advance, pipeline-gate, rotate-session-log, session-start, verify-all
- **Agenti:** {{AGENT_LIST}}
- **Rules:** workflow, principles
- **Pipeline:** Spec → Builder → Reviewer → Verifier → Commit (tehnički zaštićen)

## Brza referenca

| Stavka | Vrednost |
|--------|---------|
| Stack | {{STACK}} |
| Grane | develop → staging → main |
| Port range | {{PORT_RANGE}} |

## Memory fajlovi (po temama)

### Status
- [status.md](status.md) — aktuelna faza i fokus
- [session-log.md](session-log.md) — hronološki pregled sesija
- [pipeline-skip-log.md](pipeline-skip-log.md) — skip log za analizu
