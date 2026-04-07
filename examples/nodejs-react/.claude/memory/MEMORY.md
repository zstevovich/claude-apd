# TaskFlow — Project Memory

## Role

Orchestrator. I delegate to agents, I do not implement directly except for trivial changes.

## Environment

- **Scripts:** guard-git, guard-scope, guard-bash-scope, guard-secrets, guard-lockfile, pipeline-advance, pipeline-gate, rotate-session-log, session-start, verify-all
- **Agents:** backend-builder, frontend-builder, testing, devops
- **Rules:** workflow, principles
- **Pipeline:** Spec → Builder → Reviewer → Verifier → Commit (technically enforced)

## Quick Reference

| Item | Value |
|------|-------|
| Stack | Node.js + Express, React + Vite, PostgreSQL |
| Branches | develop → staging → main |
| Port range | 3000+ |

## Memory files (by topic)

### Status
- [status.md](status.md) — current phase and focus
- [session-log.md](session-log.md) — chronological session overview
- [pipeline-skip-log.md](pipeline-skip-log.md) — skip log for analysis
