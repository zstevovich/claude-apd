---
name: apd-init
description: Inicijalizuj APD okruženje — generiše CLAUDE.md, agente, pravila, memory i verify-all.sh. Skripte žive u plugin-u.
effort: max
---

# APD Init — Generator

Generiše kompletno APD okruženje za projekat. Skripte žive u plugin-u (`${CLAUDE_PLUGIN_ROOT}/scripts/`), ovaj skill kreira samo projektno-specifične fajlove.

## Šta se generiše (u projektu)

| Fajl | Sadržaj |
|------|---------|
| `CLAUDE.md` | Projektne instrukcije — generisan iz odgovora korisnika |
| `.claude/agents/*.md` | Agenti sa scope-ovima i `${CLAUDE_PLUGIN_ROOT}` hook putanjama |
| `.claude/rules/principles.md` | Pravila za stack i jezik korisnika |
| `.claude/scripts/verify-all.sh` | Jedina skripta u projektu — build/test komande za stack |
| `.claude/memory/MEMORY.md` | Indeks projektne memorije |
| `.claude/memory/status.md` | Trenutni status |
| `.claude/memory/session-log.md` | Session log (prazan) |
| `.claude/memory/pipeline-skip-log.md` | Skip log (prazan) |
| `.claude/settings.json` | Minimalni hooks (Notification) + env + attribution |
| `.claude/.apd-config` | PROJECT_NAME, APD_VERSION, STACK |
| `.claude/.apd-version` | Verzija APD plugin-a |

## Šta NE generiše (živi u plugin-u)

Guard skripte, pipeline skripte, workflow.md, skills — sve je u plugin-u i koristi se preko `${CLAUDE_PLUGIN_ROOT}`.

## Koraci

### 1. Detektuj postojeće okruženje

Proveri da li `.claude/` ili `CLAUDE.md` već postoji:
- **Ako NE postoji** → čist init (ovaj flow)
- **Ako POSTOJI** → ponudi migraciju:
  1. Backup u `.claude-backup-{datum}/`
  2. Analiziraj postojeće fajlove i izvuci korisne podatke (ime, stack, agenti, pravila)
  3. Generiši APD okruženje sa izvučenim podacima pre-popunjenim
  4. Prikaži šta je migrirano, šta je sačuvano

### 2. Prikupi informacije od korisnika

- Ime projekta
- Opis projekta (jedna rečenica)
- Stack (backend, frontend, mobile, baza, cache)
- Portovi (API, baza, cache, frontend)
- Autor (ime za git)
- Jezik dokumentacije (srpski/engleski)
- Figma URL (opciono)
- Miro board URL (opciono)
- GitHub Projects URL (opciono)

### 3. Auto-detect agenata iz strukture projekta

Pročitaj strukturu sa `ls -d */` i predloži agente:

| Detektovan direktorijum | Predloženi agent | Scope |
|------------------------|-----------------|-------|
| `src/` ili `server/` ili `backend/` ili `api/` | backend-builder | detektovan dir |
| `client/` ili `frontend/` ili `web/` ili `apps/frontend/` | frontend-builder | detektovan dir |
| `mobile/` ili `apps/mobile/` | mobile-builder | detektovan dir |
| `tests/` ili `__tests__/` ili `test/` ili `src/test/` | testing | detektovan dir |
| `docker/` ili `.github/` ili `deploy/` ili `infra/` | devops | detektovani dirovi |
| `src/Commands/` + `src/Queries/` | CQRS agenti | po odgovornosti |

Prikaži predlog — korisnik odobri ili koriguje.

### 4. Generiši fajlove

#### 4.1 CLAUDE.md

Generiši sa sekcijama (SVE popunjeno, NEMA placeholder-a):
- `# {Ime}` + `> {Opis}`
- `## Kritična pravila` — jezik, autor, stil
- `## Stack` — tabela sa slojevima (backend, database, frontend, mobile, design, board, tracking)
- `## Portovi` — tabela
- `## Arhitektura` — `ls` output
- `## APD` — pipeline, guardrail-i, agenti tabela, human gate, session memory
- `## Memorija` — `@.claude/memory/` reference
- `## Pravila` — reference na rules
- `## Figma dizajn` — samo ako postoji
- `## Miro board` — samo ako postoji
- `## GitHub Projects` — samo ako postoji
- `## Anti-patterns`

#### 4.2 Agenti

Za svakog agenta generiši `.claude/agents/{ime}.md`:
- Frontmatter: name, description, tools, model (sonnet), effort (high), permissionMode, memory
- Hooks sa `${CLAUDE_PLUGIN_ROOT}/scripts/` putanjama
- guard-scope.sh i guard-bash-scope.sh sa tačnim SCOPE_PATHS
- Body: uloga, stack, workflow, ZABRANJENO

Koristi format iz `${CLAUDE_PLUGIN_ROOT}/agents/TEMPLATE.md` ali GENERIŠI — ne kopiraj.

#### 4.3 verify-all.sh

Pročitaj snippet iz `${CLAUDE_PLUGIN_ROOT}/templates/verify-all/{stack}.sh`.
Generiši `.claude/scripts/verify-all.sh` sa:
- Shebang + header komentar
- Verifier cache check blok
- Stack-specifični build/test snippet
- Error reporting footer
- `chmod +x`

#### 4.4 principles.md

Pročitaj `${CLAUDE_PLUGIN_ROOT}/templates/principles/{jezik}.md`.
Prilagodi za stack — dodaj arhitekturni pattern i port range.
Postavi u `.claude/rules/principles.md`.

#### 4.5 Memory fajlovi

Generiši u `.claude/memory/`:
- `MEMORY.md` — ime, agenti, stack, port range
- `status.md` — početna faza
- `session-log.md` — prazan sa header-om
- `pipeline-skip-log.md` — prazan sa header-om i tabelom

#### 4.6 Konfiguracija

`.claude/settings.json` — Notification hook sa imenom projekta + env + attribution

`.claude/.apd-config`:
```
PROJECT_NAME={ime}
APD_VERSION=3.0.0
STACK={stack}
```

`.claude/.apd-version`: `3.0.0`

#### 4.7 Gitignore

Dodaj entry-je iz `${CLAUDE_PLUGIN_ROOT}/templates/gitignore-entries.txt` ako fale.

### 5. Verifikuj

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

## Primer

```
Korisnik: /apd-init
Claude: Kako se zove projekat?
Korisnik: MyCRM
Claude: Stack?
Korisnik: Node.js + Express, React + Vite, PostgreSQL
Claude: Portovi?
Korisnik: 3000 API, 5433 PG, 6380 Redis, 5173 Frontend
Claude: Figma?
Korisnik: https://www.figma.com/design/abc123
Claude: Miro?
Korisnik: Ne
Claude: Čitam strukturu...

  Predloženi agenti:
  | Agent             | Scope          |
  | backend-builder   | server/        |
  | frontend-builder  | client/        |
  | testing           | tests/         |
  | devops            | docker/ .github/ |

  Odobri ili koriguj:
Korisnik: Ok

Claude:
  ✓ CLAUDE.md generisan
  ✓ 4 agenta kreirana
  ✓ verify-all.sh konfigurisan za Node.js
  ✓ principles.md generisan
  ✓ Memory inicijalizovan
  ✓ .apd-config kreiran

  verify-apd.sh: 52 PASS, 0 FAIL
```
