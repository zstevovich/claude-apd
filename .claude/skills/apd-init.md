---
name: apd-init
description: Interaktivno postavlja APD framework u novi projekat — pita pitanja, generiše sve fajlove, kreira prvog agenta i ADR-0001
---

# APD Init

Interaktivni bootstrap za Agent Pipeline Development framework.

## Pre-flight provere

Pre bilo čega, proveri:

1. **Git inicijalizovan** — pokreni `git rev-parse --is-inside-work-tree`. Ako nije, ponudi korisniku `git init`.
2. **Postojeći `.claude/` ili `CLAUDE.md`** — ako postoji, detektuj situaciju:

   **Detekcija:** Proveri da li postoji `.claude/rules/workflow.md`. Ako postoji, projekat VEĆ IMA APD. Ako ne, ima Claude Code ali bez APD-a.

   **Projekat VEĆ IMA APD** (workflow.md postoji):
   > Projekat već koristi APD framework.
   > (a) **Update** — ažurira APD na najnoviju verziju iz template-a (guardrail-i, workflow, template-i)
   > (b) **Fresh install** — briše sve i kreira iznova (OPREZ: gubi session-log i memoriju)
   > (c) **Prekid**

   Ako korisnik izabere **(a) Update**, prati sekciju "Update režim" ispod.

   **Projekat IMA Claude Code ali NE APD** (workflow.md ne postoji):
   > Projekat ima Claude Code konfiguraciju ali ne koristi APD.
   > (a) **Fresh install** — briše postojeći `.claude/` i `CLAUDE.md`, kreira sve iznova
   > (b) **Merge** — dodaje APD fajlove uz očuvanje postojećih podešavanja
   > (c) **Prekid**

   Ako korisnik izabere **(b) Merge**, prati sekciju "Merge režim" ispod.
   Ako korisnik izabere **(a) Fresh install**, nastavi normalno (Grupa 1 + Grupa 2).
   Ako korisnik izabere **(c) Prekid**, zaustavi skill.
3. **jq instaliran** — pokreni `command -v jq`. Ako nije, obavesti: "jq je potreban za APD hook skripte. Instaliraj sa: brew install jq (macOS) ili apt install jq (Linux)."

## Pitanja — jedno po jedno

Postavi svako pitanje pojedinačno. Čekaj odgovor pre sledećeg.

### Pitanje 0: Putanja do APD template-a
> Putanja do APD template repozitorijuma? (npr. ~/Projects/apd-template)

Proveri da putanja postoji i da sadrži `.claude/rules/workflow.md`. Ako ne, obavesti korisnika da putanja nije validna.

Ovu putanju koristi za čitanje univerzalnih fajlova (Grupa 1) — Read alatom čitaj direktno iz template repo-a i Write alatom piši u ciljni projekat.

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

Za svaki fajl u ovoj grupi: **Read** iz `{template putanja}/{fajl}`, zatim **Write** u ciljni projekat sa identičnim sadržajem. NE menjaj ništa.

Za svaki fajl ispod: `Read` iz template putanje, `Write` u ciljni projekat. Sadržaj mora biti **identičan** — ne parafraziraj, ne skraćuj.

| Template putanja | Ciljni fajl |
|-----------------|-------------|
| `.claude/rules/workflow.md` | `.claude/rules/workflow.md` |
| `.claude/scripts/guard-git.sh` | `.claude/scripts/guard-git.sh` |
| `.claude/scripts/guard-scope.sh` | `.claude/scripts/guard-scope.sh` |
| `.claude/skills/TEMPLATE.md` | `.claude/skills/TEMPLATE.md` |
| `.claude/agents/TEMPLATE.md` | `.claude/agents/TEMPLATE.md` |
| `.claude/memory/session-log.md` | `.claude/memory/session-log.md` |
| `docs/adr/TEMPLATE.md` | `docs/adr/TEMPLATE.md` |
| `docs/plans/TEMPLATE.md` | `docs/plans/TEMPLATE.md` |

Posle kopiranja, postavi execute permisije na shell skripte:
```bash
chmod +x .claude/scripts/guard-git.sh .claude/scripts/guard-scope.sh
```

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

## Merge režim

Ako korisnik izabere **(b) Merge** u pre-flight proveri, prati ove instrukcije umesto standardnog toka za Grupu 2. Grupa 1 (as-is fajlovi) se kopira normalno jer su to novi fajlovi koji ne postoje u projektu.

### CLAUDE.md — merge

1. Pročitaj postojeći CLAUDE.md
2. Proveri da li postoji `## APD Hard Rules` sekcija — ako ne, dodaj je PRE prvog `## Pravila` ili ekvivalentnog heading-a. Kopiraj VERBATIM.
3. Proveri da li postoji `## Tehnički stack` sekcija — ako ne, dodaj je. Ako postoji, ostavi korisnikov sadržaj.
4. Dodaj sekcije koje nedostaju: `### Agent Pipeline Development (APD)`, `### ADR (Architecture Decision Records)`, `### Plugini i alati`
5. Ažuriraj `## Struktura projekta` da uključi `.claude/` i `docs/adr/` ako ih nema
6. **NE briši** postojeći sadržaj korisnika — samo dodaj APD sekcije

### settings.json — merge

1. Pročitaj postojeći `.claude/settings.json`
2. Dodaj hook-ove koji nedostaju:
   - `SessionStart` → `session-start.sh` (ako nema SessionStart hook-a)
   - `PreToolUse (Bash)` → `guard-git.sh` (ako nema Bash matcher-a)
   - `Notification` → desktop notifikacija (ako nema Notification hook-a)
3. Dodaj `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"` ako ne postoji
4. Postavi `attribution.commit: ""` i `attribution.pr: ""` ako ne postoje
5. **NE briši** postojeće hook-ove ili env varijable

### .claude/agents/ — merge

1. Ako direktorijum postoji i ima fajlove, **NE briši** ih
2. Dodaj `TEMPLATE.md` ako ne postoji
3. Kreira prvog APD agenta ({stack}-builder.md) normalno
4. Prikaži korisniku listu postojećih agenata i predloži da doda guard-scope.sh hook u njihove definicije

### .claude/memory/ — merge

1. Ako direktorijum postoji, **NE briši** postojeće fajlove
2. Ako `MEMORY.md` postoji, dodaj APD sekcije (Dva sistema memorije tabela, Naučene lekcije) na kraj
3. Ako `session-log.md` ne postoji, kreiraj
4. Ako `status.md` ne postoji, kreiraj

### .claude/rules/ — uvek kreira

Rules direktorijum obično ne postoji u projektima bez APD-a. Kreiraj normalno:
- `workflow.md` — kopiraj as-is
- `principles.md` — generiši
- `conventions.md` — generiši

### .claude/skills/ — merge

1. Ako direktorijum postoji, **NE briši** postojeće skill-ove
2. Dodaj `TEMPLATE.md` ako ne postoji

### docs/ — uvek kreira

Kreiraj `docs/adr/` i `docs/plans/` normalno — ovi direktorijumi obično ne postoje.

### Commit poruka za merge

```bash
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: dodaj APD framework u postojeći projekat {naziv}"
```

### Završna poruka za merge

```
APD framework je integrisan u {naziv}.

Dodano:
- APD Hard Rules u CLAUDE.md
- Guard hook-ovi u settings.json
- .claude/rules/ sa workflow-om i pravilima
- Prvi APD agent ({stack}-builder)
- ADR-0001 sa dokumentovanim stack odlukama

VAŽNO — pregledaj ove fajlove:
1. CLAUDE.md — proveri da merge nije pokvario strukturu
2. settings.json — proveri da stari hook-ovi rade
3. Postojeći agenti — dodaj guard-scope.sh hook ako želiš file-scope zaštitu
```

---

## Update režim

Ako korisnik izabere **(a) Update** u pre-flight proveri (projekat već ima APD), prati ove instrukcije. Cilj: ažurirati APD infrastrukturu na najnoviju verziju iz template-a bez gubitka projektnih podataka.

### Šta se AŽURIRA (univerzalni fajlovi iz template-a)

Ovi fajlovi se prepisuju sa najnovijom verzijom iz template-a:

| Fajl | Razlog |
|------|--------|
| `.claude/rules/workflow.md` | Workflow pravila mogu biti ažurirana |
| `.claude/scripts/guard-git.sh` | Guardrail-i mogu imati nove blokade |
| `.claude/scripts/guard-scope.sh` | Scope guard može biti poboljšan |
| `.claude/scripts/session-start.sh` | Zameni `[PROJECT_NAME]` sa postojećim nazivom projekta |
| `.claude/skills/TEMPLATE.md` | Template može biti ažuriran |
| `.claude/agents/TEMPLATE.md` | Agent template može imati nove hook-ove |
| `docs/adr/TEMPLATE.md` | ADR format može biti proširen |
| `docs/plans/TEMPLATE.md` | Plan format može biti proširen |

**Za session-start.sh:** Pročitaj postojeći fajl da izvučeš naziv projekta (iz `echo "=== ... ==="` linije), pa zameni `[PROJECT_NAME]` u novoj verziji.

### Šta se AŽURIRA u CLAUDE.md

1. Pročitaj postojeći CLAUDE.md
2. Zameni `## APD Hard Rules` sekciju sa najnovijom verzijom iz template-a (VERBATIM)
3. Proveri da li nedostaju nove APD sekcije (npr. ADR sekcija ako je dodata u novijoj verziji) — dodaj ih
4. **NE diraj** korisnikov sadržaj (stack, pravila, struktura)

### Šta se AŽURIRA u settings.json

1. Pročitaj postojeći settings.json
2. Proveri da li hook komande referenciraju iste skripte — ažuriraj putanje ako treba
3. Dodaj nove hook-ove koji ne postoje (npr. ako je dodat novi hook u novijoj verziji)
4. **NE briši** korisnikove custom hook-ove

### Šta se NE DIRA

Ovi fajlovi su projektno-specifični i NE smeju se prepisati:

- `.claude/rules/principles.md` — korisnikova pravila
- `.claude/rules/conventions.md` — korisnikove konvencije
- `.claude/scripts/verify-all.sh` — korisnikove build/test komande
- `.claude/agents/*-builder.md` — korisnikovi agenti (osim TEMPLATE.md)
- `.claude/memory/MEMORY.md` — projektna memorija
- `.claude/memory/session-log.md` — session log (NIKADA ne brisati)
- `.claude/memory/status.md` — trenutni status
- `docs/adr/README.md` — ADR indeks
- `docs/adr/0001-*.md` — postojeći ADR-ovi
- `CLAUDE.md` — osim APD Hard Rules sekcije (vidi gore)

### Pitanja u Update režimu

NE postavljaj svih 8 pitanja. Postavi samo:
- **Pitanje 0:** Putanja do APD template-a (obavezno — za čitanje novih verzija fajlova)

Sve ostale informacije (naziv, stack, itd.) već postoje u projektu.

### Commit za update

```bash
APD_ORCHESTRATOR_COMMIT=1 git commit -m "chore: ažuriraj APD framework na najnoviju verziju"
```

### Završna poruka za update

```
APD framework ažuriran.

Ažurirano:
- workflow.md — najnovija pravila
- guard-git.sh — najnoviji guardrail-i
- guard-scope.sh — najnoviji scope guard
- APD Hard Rules u CLAUDE.md — najnovija verzija
- Template fajlovi (agent, ADR, plan)

Nije dirano:
- Vaši agenti, pravila, konvencije, memorija, ADR-ovi, verify-all.sh
```

---

## Commit

Posle generisanja SVIH fajlova (fresh install režim), commituj eksplicitno po imenu:

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
