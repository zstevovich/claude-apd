---
name: apd-init
description: Interaktivno postavlja APD framework u novi projekat — pita pitanja, generiše sve fajlove, kreira prvog agenta i ADR-0001
---

# APD Init

Interaktivni bootstrap za Agent Pipeline Development framework.

## Pre-flight provere

Pre bilo čega, proveri:

1. **Git inicijalizovan** — pokreni `git rev-parse --is-inside-work-tree`. Ako nije, ponudi korisniku `git init`.
2. **Postojeći `.claude/`** — ako direktorijum postoji, pitaj korisnika: "Projekat već ima .claude/ direktorijum. Da li želiš overwrite (briše postojeći) ili prekid?" Ako prekid, zaustavi skill.
3. **jq instaliran** — pokreni `command -v jq`. Ako nije, obavesti: "jq je potreban za APD hook skripte. Instaliraj sa: brew install jq (macOS) ili apt install jq (Linux)."

## Pitanja — jedno po jedno

Postavi svako pitanje pojedinačno. Čekaj odgovor pre sledećeg.

### Pitanje 1: Naziv projekta
> Kako se zove projekat?

Default: naziv direktorijuma.

### Pitanje 2: Backend stack
> Backend stack — jezik, framework, baza/ORM? (npr. "TypeScript + Express + PostgreSQL/Prisma", "Python + FastAPI + PostgreSQL/SQLAlchemy", "Go + Gin + PostgreSQL/GORM")

### Pitanje 3: Frontend stack
> Frontend stack? (npr. "React + TypeScript", "Vue + TypeScript", "Next.js", ili "Nema")

Default: "Nema"

### Pitanje 4: Arhitekturni pattern
> Arhitekturni pattern? (a) Vertical Slice, (b) Clean Architecture, (c) MVC, (d) Drugo

### Pitanje 5: Jezik dokumentacije
> Jezik dokumentacije i komunikacije? (a) Srpski, (b) Engleski, (c) Drugo

Default: Srpski

### Pitanje 6: Build/test komande
> Build i test komande? (npr. "npm run build && npm test", "pytest", "go build ./... && go test ./...")

### Pitanje 7: Deployment
> Deployment setup (preskoči sa "Nema" za bilo koje):
> - Lokalni dev? (npr. "docker-compose up", "npm run dev")
> - Staging? (npr. "AWS ECS", "Vercel preview", "Nema")
> - Produkcija? (npr. "AWS ECS", "Fly.io", "Nema")

## Generisanje fajlova

Posle svih odgovora, generiši fajlove u dve grupe.

### Grupa 1: Kopiraj as-is (univerzalni fajlovi)

Ovi fajlovi se kreiraju sa TAČNIM sadržajem iz template-a. NE menjaj ništa.

#### `.claude/rules/workflow.md`

Kopiraj CELOKUPAN sadržaj iz APD template workflow.md. Ovo uključuje:
- HARD GATE sekciju
- Spec karticu sa ADR poljem
- Tri role agenata
- Mikro-zadaci
- Verifikacija pre "gotovo"
- Human gate
- Session memory update
- Cross-layer verifikacija
- Reasoning effort

**NE skraćuj i NE parafraziraj. Kopiraj verbatim.**

#### `.claude/scripts/guard-git.sh`

Kopiraj CELOKUPAN sadržaj APD template guard-git.sh. Ovo uključuje:
- jq provera
- RAW_COMMAND čuvanje pre normalizacije
- --no-verify blokada
- Masovni staging blokada (git add ., -A, --all, -u, *)
- git commit blokada bez APD_ORCHESTRATOR_COMMIT=1 prefiksa
- git commit -a blokada
- verify-all.sh poziv pre commit-a
- git push blokada
- AI potpis blokada
- .claude/ zaštita
- Destruktivne operacije blokada

**NE skraćuj. Kopiraj verbatim.**

#### `.claude/scripts/guard-scope.sh`

Kopiraj CELOKUPAN sadržaj APD template guard-scope.sh. Ovo uključuje:
- Allowed paths iz argumenata
- jq provera
- file_path ekstrakcija iz JSON-a
- Apsolutna → relativna putanja konverzija
- Trailing slash normalizacija
- Blokada sa jasnom porukom

**NE skraćuj. Kopiraj verbatim.**

#### `.claude/skills/TEMPLATE.md`

```markdown
---
name: [skill-name]
description: [Kada koristiti ovaj skill — jedna rečenica]
---

# [Skill Name]

## Kada koristiti

- [Situacija 1]
- [Situacija 2]

## Konvencije

### [Kategorija 1]

- [Pravilo/pattern]
- [Primer]

## Primeri

### Dobro

[Primer koda koji poštuje konvenciju]

### Loše

[Primer koda koji krši konvenciju]
```

#### `.claude/agents/TEMPLATE.md`

Kopiraj CELOKUPAN sadržaj APD template TEMPLATE.md za agente. Ovo uključuje:
- Frontmatter sa name, description, tools, model, permissionMode, memory, hooks
- Write|Edit hook sa guard-scope.sh i [DOZVOLJENE_PUTANJE] placeholder
- Bash hook sa guard-git.sh i [APSOLUTNA_PUTANJA] placeholder
- Body sa Stack, Arhitektura, Workflow, API Contract Rule, ZABRANJENO, Agent Memory sekcijama

**NE skraćuj. Kopiraj verbatim.**

#### `.claude/memory/session-log.md`

```markdown
# Session Log

<!-- Svaki završen task dobija zapis ispod. Format: pogledaj .claude/rules/workflow.md sekcija 6. -->
```

#### `docs/adr/TEMPLATE.md`

Kopiraj CELOKUPAN sadržaj APD template ADR TEMPLATE.md sa svim sekcijama:
- Status, Datum, Zamenjuje, Zamenjen sa
- Kontekst, Razmatrane opcije, Odluka, Posledice (Pozitivne, Negativne, Rizici)

#### `docs/plans/TEMPLATE.md`

Kopiraj CELOKUPAN sadržaj APD template plan TEMPLATE.md sa:
- Goal, Architecture, Tech Stack header
- File Map tabela
- Task struktura sa Steps
- Redosled izvršavanja
- Finalna verifikacija

### Grupa 2: Generiši (popunjeni fajlovi)

Zameni SVE placeholder-e sa stvarnim vrednostima. Nijedan `[PROJECT_NAME]`, `[APSOLUTNA_PUTANJA]`, `[DOZVOLJENE_PUTANJE]` ne sme ostati (osim u TEMPLATE fajlovima).

#### `CLAUDE.md`

Generiši na osnovu odgovora. MORA sadržati ove sekcije:

1. `# {naziv}` — heading sa nazivom projekta
2. `## O projektu` — placeholder za korisnika
3. `## Faza projekta` — "Inicijalna faza"
4. `## Tehnički stack` — popunjeno iz odgovora (Backend, Frontend, Infrastruktura)
5. `## APD Hard Rules — NE KOMPRESOVATI, NE ZAOBILAZITI` — **KOPIRAJ VERBATIM:**

```markdown
## APD Hard Rules — NE KOMPRESOVATI, NE ZAOBILAZITI

### Commit pravilo

- Svaki git commit MORA koristiti prefix: `APD_ORCHESTRATOR_COMMIT=1 git commit ...`
- Svaki git push MORA koristiti prefix: `APD_ORCHESTRATOR_COMMIT=1 git push ...`
- Bez prefiksa → hook blokira. NE pokušavaj bez njega.

### Pipeline redosled — OBAVEZAN

Spec → Builder → Reviewer → Verifier → Commit

- NIKADA preskočiti Reviewer, čak ni za "trivijalne" promene
- NIKADA commitovati pre nego Verifier prođe

### Agent scope

- Builder agenti menjaju SAMO fajlove u svom domenu
- SAMO orkestrator commituje, push-uje, komunicira sa korisnikom

### Human gate

- API promene, migracije, auth logika, deploy → korisnik MORA odobriti pre akcije

### Session memory

- Posle SVAKOG taska → append u .claude/memory/session-log.md
```

6. `## Pravila` — jezik, git konvencije, APD reference, ADR sekcija, plugini
7. `## Struktura projekta` — tree sa svim kreiranim direktorijumima

#### `.claude/rules/principles.md`

```markdown
# Principi

## Jezik
- {jezik dokumentacije iz pitanja 5}
- Stručni termini ostaju na engleskom: endpoint, middleware, handler, cache, repository
- Ton: profesionalan i konkretan

## Kod
- Minimalni komentari — samo gde logika nije očigledna
- {error handling pattern za izabrani stack} (vidi ADR-0001)
- {arhitekturni pattern iz pitanja 4} (vidi ADR-0001)
- Arhitekturne odluke se dokumentuju kao ADR u `docs/adr/`

## Git
- Nema AI potpisa u commitima — nikakav Co-Authored-By
- Grane: develop → staging → main, feature/* po potrebi
- .claude/ direktorijum je deo repozitorijuma (deljeni workflow)
```

#### `.claude/rules/conventions.md`

Generiši naming konvencije za izabrani stack. Npr. za TypeScript:
- Fajlovi: kebab-case (`user-service.ts`)
- Varijable/funkcije: camelCase
- Klase/tipovi: PascalCase
- Konstante: UPPER_SNAKE_CASE

Za Python: snake_case za fajlove i funkcije, PascalCase za klase, itd.

Popuni i struktura fajlova sekciju na osnovu arhitekturnog pattern-a.

#### `.claude/scripts/verify-all.sh`

Generiši sa OTKOMENTARISANIM build/test komandama iz pitanja 6:

```bash
#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

ERRORS=()

if git rev-parse HEAD &>/dev/null; then
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null)
else
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
fi

# Backend verifikacija
if echo "$CHANGED_FILES" | grep -qE '{backend putanja pattern}'; then
    echo "→ Backend promene detektovane..."
    if ! {build komanda} 2>&1; then
        ERRORS+=("Backend build FAILED")
    fi
    if ! {test komanda} 2>&1; then
        ERRORS+=("Backend testovi FAILED")
    fi
fi

# Frontend verifikacija (ako ima frontend)
# ... analogan blok za frontend ako pitanje 3 nije "Nema"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "VERIFIKACIJA NIJE PROŠLA:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

echo "Verifikacija prošla"
exit 0
```

#### `.claude/scripts/session-start.sh`

```bash
#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MEMORY_DIR=".claude/memory"

echo "=== {naziv projekta} ==="
echo ""

if [ -f "$MEMORY_DIR/status.md" ]; then
    echo "--- Trenutni status ---"
    head -30 "$MEMORY_DIR/status.md"
    echo ""
fi

if [ -f "$MEMORY_DIR/session-log.md" ]; then
    echo "--- Poslednja sesija ---"
    tail -20 "$MEMORY_DIR/session-log.md"
fi
```

#### `.claude/settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "bash {apsolutna putanja}/.claude/scripts/session-start.sh",
            "timeout": 5,
            "statusMessage": "Učitavanje konteksta projekta..."
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash {apsolutna putanja}/.claude/scripts/guard-git.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if command -v osascript &>/dev/null; then osascript -e 'display notification \"Claude Code treba pažnju\" with title \"{naziv projekta}\"'; elif command -v notify-send &>/dev/null; then notify-send '{naziv projekta}' 'Claude Code treba pažnju'; fi"
          }
        ]
      }
    ]
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

#### `.claude/agents/{stack}-builder.md`

Generiši prvog agenta na osnovu izabranog stack-a. Ime: npr. `express-builder.md`, `fastapi-builder.md`.

Sadržaj prati TEMPLATE.md format ali sa popunjenim:
- name, description za izabrani stack
- model: sonnet
- permissionMode: bypassPermissions
- hooks sa guard-scope.sh ({detektovane putanje}) i guard-git.sh ({apsolutna putanja})
- Stack sekcija sa konkretnim jezikom, framework-om, bazom, ORM-om
- Arhitektura sekcija sa izabranim pattern-om
- Workflow koraci specifični za stack

**Scope detekcija:** Proveri da li postoji `src/`, `app/`, `lib/`. Ako postoji, koristi kao dozvoljene putanje. Ako ne, pitaj korisnika.

#### `.claude/memory/MEMORY.md`

```markdown
# Orkestrator memorija

## Dva sistema memorije — ne mešati

| | APD memorija (`.claude/memory/`) | Claude auto memorija (`~/.claude/projects/`) |
|---|---|---|
| **Šta čuva** | Projektno znanje — status, session log, naučene lekcije | Lične preference korisnika, feedback, kontekst |
| **Ko koristi** | Svi na projektu (orkestrator + agenti) | Samo taj korisnik na toj mašini |
| **Gde živi** | U repozitorijumu — commituje se | Lokalno — NE commituje se |
| **Ko piše** | Orkestrator (posle svakog taska) | Claude automatski |

## Projekat

- **Naziv:** {naziv}
- **Faza:** Inicijalna
- **Rok:** —

## Roadmap

1. [Definisati roadmap]

## Naučene lekcije

- (Akumulira se tokom rada — pogledaj session-log.md za detalje)
```

#### `.claude/memory/status.md`

```markdown
# Status

**Faza:** Inicijalna — APD setup završen
**Fokus:** [Definisati prvi task]
**Blokirano:** Ništa
```

#### `docs/adr/README.md`

```markdown
# Architecture Decision Records

Arhitekturne odluke za {naziv}. Svaka odluka je dokumentovana kao ADR.

## Konvencije

- Numeracija: 0001, 0002, ... (4 cifre sa vodećim nulama)
- Immutable posle prihvatanja — ako se odluka promeni, novi ADR zamenjuje starog
- Životni ciklus: Predložen → Prihvaćen → [Zamenjen | Povučen]
- Template: [TEMPLATE.md](TEMPLATE.md)

## Indeks

| # | Naslov | Status | Datum |
|---|--------|--------|-------|
| 0001 | [Inicijalni tehnički stack](0001-inicijalni-stack.md) | Prihvaćen | {datum} |
```

#### `docs/adr/0001-inicijalni-stack.md`

Generiši ADR-0001 koji dokumentuje sve stack odluke iz pitanja 2-4 i 7. Prati format iz `docs/adr/TEMPLATE.md`. Uključi relevantne alternative i trade-off-ove za izabrani stack.

## Commit

Posle generisanja SVIH fajlova, commituj eksplicitno po imenu:

```bash
APD_ORCHESTRATOR_COMMIT=1 git add \
  .claude/rules/workflow.md .claude/rules/principles.md .claude/rules/conventions.md \
  .claude/scripts/guard-git.sh .claude/scripts/guard-scope.sh .claude/scripts/verify-all.sh .claude/scripts/session-start.sh \
  .claude/settings.json .claude/skills/TEMPLATE.md .claude/agents/TEMPLATE.md .claude/agents/{stack}-builder.md \
  .claude/memory/MEMORY.md .claude/memory/session-log.md .claude/memory/status.md \
  CLAUDE.md docs/adr/TEMPLATE.md docs/adr/README.md docs/adr/0001-inicijalni-stack.md docs/plans/TEMPLATE.md

APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: inicijalni APD setup za {naziv}"
```

Zameni `{stack}` i `{naziv}` sa stvarnim vrednostima pre izvršavanja.

## Završna poruka

Posle commit-a, prikaži korisniku:

```
APD framework je postavljen za {naziv}.

Kreirano:
- CLAUDE.md sa stack-om i pravilima
- .claude/ sa workflow-om, guardrail-ima, prvim agentom
- ADR-0001 sa dokumentovanim stack odlukama
- verify-all.sh konfigurisan za {build/test komande}

Sledeći koraci:
1. Pregledaj CLAUDE.md i prilagodi sekcije označene sa [...]
2. Kreiraj dodatne agente po potrebi (kopiraj .claude/agents/TEMPLATE.md)
3. Počni sa prvim taskom — kreiraj spec karticu
```
