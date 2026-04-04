# {{PROJECT_NAME}}

> {{PROJECT_DESCRIPTION}}

## Kritična pravila

- **Jezik:** {{LANGUAGE}}
- **Autor:** {{AUTHOR_NAME}} — BEZ AI potpisa/watermarks
- **Stil:** Profesionalan, konkretan, human style

## Stack

| Layer | Tehnologija |
|-------|-------------|
| Backend | {{BACKEND_STACK}} |
| Database | {{DATABASE}} |
| Frontend | {{FRONTEND_STACK}} |
| Mobile | {{MOBILE_STACK}} (ako postoji) |
| Design | {{FIGMA_URL}} (ako postoji) |

## Portovi (lokalni razvoj)

| Service | Port |
|---------|------|
| API | {{API_PORT}} |
| Database | {{DB_PORT}} |
| Cache | {{CACHE_PORT}} |
| Frontend | {{FRONTEND_PORT}} |

## Arhitektura

```
{{PROJECT_STRUCTURE}}
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
{{AGENT_TABLE}}

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

<!-- Obriši ovu sekciju ako projekat nema Figma dizajn -->

- **Figma fajl:** {{FIGMA_URL}}
- Koristi `figma:figma-implement-design` skill za implementaciju iz Figma-e
- Pre implementacije UI komponente — uvek proveri da li postoji Figma dizajn
- Builder agent koji radi frontend MORA koristiti `get_design_context` za dizajn kontekst
- Dizajn tokeni i boje iz Figma-e su izvor istine — ne izmišljaj vrednosti

## Anti-patterns

```
❌ AI potpisi u kodu/dokumentaciji → ✅ Human style
❌ Commit bez pipeline-a           → ✅ Spec → Builder → Reviewer → Verifier
❌ Agent piše van svog scope-a     → ✅ guard-scope.sh blokira
❌ git add . / git add -A          → ✅ Eksplicitno staging po fajlu
❌ --no-verify                     → ✅ Hook-ovi moraju proći
```
