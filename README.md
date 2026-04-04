# APD Template — Agent Pipeline Development

Šablon za Claude Code okruženje sa strogo enforced razvojnim pipeline-om.

## Šta je APD?

Agent Pipeline Development je framework gde AI orkestrator koordiniše specijalizovane agente kroz disciplinovan pipeline:

```
Spec → Builder → Reviewer → Verifier → Commit
```

Svaki korak je **tehnički zaštićen** — hook-ovi blokiraju commit ako koraci nisu završeni.

## Šta dobijaš

### Skripte (11)
| Skripta | Funkcija |
|---------|----------|
| `guard-git.sh` | Blokira neovlašćen git (commit/push samo orkestrator, bez force push, bez mass staging) |
| `guard-scope.sh` | Blokira Write/Edit van agentovog scope-a |
| `guard-bash-scope.sh` | Upozorava na bash write van scope-a |
| `guard-secrets.sh` | Blokira pristup osetljivim fajlovima |
| `guard-lockfile.sh` | Blokira modifikaciju lock fajlova |
| `test-hooks.sh` | Verifikuje da su hook-ovi i skripte ispravno konfigurisani |
| `pipeline-advance.sh` | Pipeline flag sistem sa timestampovima i skip log-om |
| `pipeline-gate.sh` | Blokira commit bez svih 4 pipeline koraka |
| `rotate-session-log.sh` | Automatski arhivira stare session log entry-je |
| `session-start.sh` | Učitava kontekst projekta na startu sesije |
| `verify-all.sh` | Build + test + contract check pre commit-a |

### Pravila
- `workflow.md` — APD pipeline (univerzalan)
- `principles.md` — jezik, kod, git konvencije (prilagodljiv)

### Memory sistem
- `MEMORY.md` — indeks (uvek se učitava, minimalan kontekst)
- `status.md` — aktuelna faza
- `session-log.md` — hronološki pregled sesija (sa rotacijom)
- `pipeline-skip-log.md` — skip metrika za analizu

### Agent template
- `TEMPLATE.md` — šablon za kreiranje agenata sa punim hook coverage-om

### Ostalo
- `.mcp.json.example` — MCP serveri (context7, postgres, docker, github)
- `docs/adr/` — ADR framework sa template-om
- `settings.json` — hook konfiguracija

## Quick Start

### 1. Kloniraj template u svoj projekat

```bash
# Kopiraj .claude/ direktorijum u postojeći projekat
cp -r apd-template/.claude/ /path/to/my-project/.claude/
cp apd-template/CLAUDE.md /path/to/my-project/
cp apd-template/.mcp.json.example /path/to/my-project/.mcp.json
cp -r apd-template/docs/ /path/to/my-project/docs/
```

### 2. Pokreni APD Init

U Claude Code na svom projektu:
```
/apd-init
```

Skill će te provesti kroz konfiguraciju — ime projekta, stack, putanje, agenti.

### 3. Ili ručno prilagodi

Zameni `{{PLACEHOLDER}}` vrednosti u:
- `CLAUDE.md` — projektne instrukcije
- `.claude/settings.json` — putanje do skripti
- `.claude/scripts/session-start.sh` — ime projekta
- `.claude/scripts/verify-all.sh` — build komande
- `.claude/scripts/guard-secrets.sh` — osetljivi fajlovi
- `.claude/memory/MEMORY.md` — indeks
- `.claude/agents/TEMPLATE.md` → kopiraj za svakog agenta

### 4. Učini skripte executable

```bash
chmod +x .claude/scripts/*.sh
```

### 5. Verifikuj

```bash
bash .claude/scripts/test-hooks.sh
# → PASS: 15 | FAIL: 0 | WARN: 3

bash .claude/scripts/pipeline-advance.sh status
# → Pipeline status: [nema aktivnog taska]

bash .claude/scripts/session-start.sh
# → === Ime Projekta ===
```

## Kreiranje agenata

Za svaki sloj projekta kreiraj agenta iz `TEMPLATE.md`:

```bash
cp .claude/agents/TEMPLATE.md .claude/agents/backend-builder.md
```

Zameni:
- `{{agent-name}}` → `backend-builder`
- `{{SCOPE_PATHS}}` → `src/ tests/`
- `{{PROJECT_PATH}}` → apsolutna putanja
- `{{model}}` → `sonnet` (Builder) ili `opus` (Reviewer/Guardian)

## Tipični agenti po stack-u

### .NET / C#
| Agent | Scope | Model |
|-------|-------|-------|
| backend-api | src/ tests/ | sonnet |
| database | src/Infrastructure/ | sonnet |
| backoffice | apps/backoffice/ | sonnet |
| mobile | apps/mobile/ | sonnet |
| testing | tests/ | sonnet |
| devops | docker/ .github/ | sonnet |

### Node.js / TypeScript
| Agent | Scope | Model |
|-------|-------|-------|
| backend | server/ | sonnet |
| frontend | client/ | sonnet |
| testing | tests/ __tests__/ | sonnet |
| devops | docker/ .github/ | sonnet |

### PHP / Symfony
| Agent | Scope | Model |
|-------|-------|-------|
| symfony-builder | backend/src/ backend/tests/ | sonnet |
| frontend | web/ backoffice/ | sonnet |
| mobile | mobile/ | sonnet |
| devops | docker/ .github/ | sonnet |

## Pipeline u praksi

```bash
# 1. Spec
bash .claude/scripts/pipeline-advance.sh spec "Implementiraj user login"

# 2. Builder implementira
# ... agent radi ...
bash .claude/scripts/pipeline-advance.sh builder

# 3. Reviewer pregleda
# ... code review ...
bash .claude/scripts/pipeline-advance.sh reviewer

# 4. Verifier (build + test)
# ... dotnet build && dotnet test ...
bash .claude/scripts/pipeline-advance.sh verifier

# 5. Commit (dozvoljen tek sada)
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: user login"

# Pipeline se auto-resetuje za sledeći task
```

## Dodavanje projektno-specifičnih pravila

Kreiraj nove fajlove u `.claude/rules/`:
- `code-style.md` — naming, formatting konvencije
- `api-design.md` — REST/GraphQL konvencije
- `database.md` — šema, migracije, naming
- `security.md` — auth, validacija, secrets
- `logging.md` — log format, nivoi, šta ne logovati

## Skip analiza

```bash
bash .claude/scripts/pipeline-advance.sh stats
# Pipeline statistika:
#   Ukupno skip-ova: 4
#   Poslednjih 5:
#   | 2026-04-03 | Pre-existing TS greške | pre-existing-debt |
```

Ako je >30% commitova sa skip — nešto u pipeline-u treba popraviti.

## Licenca

MIT
