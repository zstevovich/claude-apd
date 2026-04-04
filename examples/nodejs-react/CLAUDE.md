# TaskFlow

> Task management platform with real-time collaboration, team boards, and automated workflows.

## Kritična pravila

- **Jezik:** English
- **Autor:** Alex Morgan — BEZ AI potpisa/watermarks
- **Stil:** Profesionalan, konkretan, human style

## Stack

| Layer | Tehnologija |
|-------|-------------|
| Backend | Node.js 20 + Express 5 + TypeScript |
| Database | PostgreSQL 16 + Prisma ORM |
| Frontend | React 19 + Vite + TypeScript + TailwindCSS |
| Mobile | — |
| Design | https://www.figma.com/design/xK9mR2p/TaskFlow |
| Board | https://miro.com/app/board/uXjVNq8/TaskFlow-Architecture |

## Portovi (lokalni razvoj)

| Service | Port |
|---------|------|
| API | 3000 |
| Database | 5433 |
| Cache | 6380 |
| Frontend | 5173 |

## Arhitektura

```
taskflow/
├── server/
│   ├── src/
│   │   ├── routes/
│   │   ├── services/
│   │   ├── repositories/
│   │   ├── middleware/
│   │   ├── validators/
│   │   └── types/
│   ├── prisma/
│   │   ├── schema.prisma
│   │   └── migrations/
│   └── tests/
├── client/
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   ├── services/
│   │   └── types/
│   └── tests/
├── docker/
│   └── docker-compose.yml
└── .github/
    └── workflows/
```

## APD — Agent Pipeline Development

### Pipeline — TEHNIČKI ZAŠTIĆEN

Spec → Builder → Reviewer → Verifier → Commit

- **Hook-ovi BLOKIRAJU commit** ako pipeline koraci nisu završeni
- Svaki korak: `bash .claude/scripts/pipeline-advance.sh {korak}`
- Hotfix: `pipeline-advance.sh skip "razlog"` — samo za urgentne situacije

### Guardrail-i

- `guard-git.sh` — git zaštita (commit/push samo orkestrator, bez force push, bez mass staging)
- `guard-scope.sh` — file scope po agentu (Write/Edit)
- `guard-bash-scope.sh` — bash write scope
- `guard-secrets.sh` — osetljivi fajlovi
- `guard-lockfile.sh` — lock fajlovi
- `verify-all.sh` — build + test pre commit-a
- `pipeline-advance.sh` + `pipeline-gate.sh` — pipeline flag sistem
- `rotate-session-log.sh` — automatska arhivacija session log-a

### Agenti

| Agent | Domen | Scope |
|-------|-------|-------|
| backend-builder | API, servisi, repozitorijumi | server/ |
| frontend-builder | React komponente, stranice, hookovi | client/ |
| testing | Unit + integration testovi | server/tests/ client/tests/ |
| devops | Docker, CI/CD | docker/ .github/ |

### Human gate

API promene, migracije, auth logika, deploy → korisnik MORA odobriti pre akcije.

### Session memory

Posle SVAKOG taska → append u .claude/memory/session-log.md

## Memorija

@.claude/memory/MEMORY.md
@.claude/memory/status.md
@.claude/memory/session-log.md

## Pravila

- `.claude/rules/workflow.md` — APD pipeline pravila
- `.claude/rules/principles.md` — jezik, kod, git konvencije

## Figma dizajn

- **Figma fajl:** https://www.figma.com/design/xK9mR2p/TaskFlow
- Koristi `figma:figma-implement-design` skill za implementaciju iz Figma-e
- Pre implementacije UI komponente — uvek proveri da li postoji Figma dizajn
- Builder agent koji radi frontend MORA koristiti `get_design_context` za dizajn kontekst
- Dizajn tokeni i boje iz Figma-e su izvor istine — ne izmišljaj vrednosti

## Miro board

- **Miro board:** https://miro.com/app/board/uXjVNq8/TaskFlow-Architecture
- Miro MCP čita board sadržaj — sticky notes, frames, dijagrame, dokumente
- Pre kreiranja spec kartice — proveri da li postoji relevantan sadržaj na Miro boardu
- Orkestrator može čitati taskove, flow dijagrame i arhitekturu direktno sa boarda
- Za vizualizaciju arhitekture ili procesa — kreiraj dijagram na Miro boardu
- Instalacija: `claude mcp add --transport http miro https://mcp.miro.com`

## Anti-patterns

```
❌ AI potpisi u kodu/dokumentaciji → ✅ Human style
❌ Commit bez pipeline-a           → ✅ Spec → Builder → Reviewer → Verifier
❌ Agent piše van svog scope-a     → ✅ guard-scope.sh blokira
❌ git add . / git add -A          → ✅ Eksplicitno staging po fajlu
❌ --no-verify                     → ✅ Hook-ovi moraju proći
```
