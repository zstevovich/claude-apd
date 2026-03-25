# APD Init Skill — Design Spec

**Cilj:** Claude Code skill (`/apd-init`) koji interaktivno postavlja APD framework u novi projekat — pita 7 pitanja, popunjava sve fajlove, kreira prvog agenta i ADR-0001, commituje.
**Effort:** max
**Van scope-a:** CLI alat, npm paket, GitHub template repo. Ovo je isključivo Claude Code skill — instrukcije za orkestratora koji koristi Write/Edit alate.
**Pogođeni moduli:** `.claude/skills/apd-init.md` (novi skill), svi template fajlovi (kopiraju se/generišu u ciljni projekat)
**Human gate:** Ne (kreira fajlove u korisnikovom projektu, korisnik vidi sve pre commit-a)
**Rollback:** `git revert` poslednjeg commit-a ili `rm -rf .claude/ docs/adr/ docs/plans/ CLAUDE.md`
**ADR:** ADR-0001 (generisan kao deo init procesa)

---

## Problem

Trenutni setup zahteva:
1. Ručno kopiranje template fajlova
2. Pokretanje `setup.sh` (zamenjuje samo `[APSOLUTNA_PUTANJA]` i opciono `[PROJECT_NAME]`)
3. Ručno popunjavanje 5+ fajlova sa placeholder-ima (`CLAUDE.md`, `principles.md`, `conventions.md`, `verify-all.sh`, agenti)
4. Ručno kreiranje prvog agenta
5. Ručna konfiguracija `verify-all.sh`

Rezultat: nepopunjeni placeholder-i, zaboravljeni fajlovi, nefunkcionalan `verify-all.sh`, nema ADR-a za inicijalne odluke.

## Rešenje

### Skill mehanika

Claude Code skill `apd-init` koji:
1. Korisnik pokrene `/apd-init` u svom projektu
2. Skill učita instrukcije za orkestratora
3. Orkestrator interaktivno pita 7 pitanja (jedno po jedno, multiple choice gde je moguće)
4. Na osnovu odgovora generiše sve fajlove
5. Commituje kao "Initial APD setup"

**Skill ne sadrži kod** — sadrži instrukcije za orkestratora koji koristi Write/Edit alate da kreira i popuni fajlove. Nema bash skripte, nema generatora.

### Tok pitanja

| # | Pitanje | Primer odgovora | Šta popunjava |
|---|---------|-----------------|---------------|
| 1 | Naziv projekta | "MyApp" | `[PROJECT_NAME]` u svim fajlovima |
| 2 | Backend stack (jezik + framework + baza/ORM) | "TypeScript + Express + PostgreSQL/Prisma" | CLAUDE.md, principles.md, prvi agent, ADR-0001 |
| 3 | Frontend stack (ili "Nema") | "React + TypeScript" | CLAUDE.md, conventions.md, opciono drugi agent |
| 4 | Arhitekturni pattern | "Vertical Slice" | principles.md, CLAUDE.md, ADR-0001 |
| 5 | Jezik dokumentacije | "Srpski" | principles.md, CLAUDE.md |
| 6 | Build/test komande | "npm test" | verify-all.sh |
| 7 | Deployment (sve opciono): | | |
| 7a | — Lokalni dev | "docker-compose up" | CLAUDE.md (Infrastruktura) |
| 7b | — Staging | "AWS ECS" / "Nema" | CLAUDE.md, human gate kontekst |
| 7c | — Produkcija | "AWS ECS" / "Nema" | CLAUDE.md, human gate kontekst |

Pitanje 7 je jedno pitanje sa tri pod-pitanja (lokalno, staging, produkcija). Korisnik može preskočiti bilo koje sa "Nema".

### Šta skill kopira as-is (univerzalni fajlovi)

Ovi fajlovi se kopiraju bez izmena iz template-a:

- `.claude/rules/workflow.md` — APD pipeline definicija
- `.claude/scripts/guard-git.sh` — git guardrail
- `.claude/scripts/guard-scope.sh` — file scope guardrail
- `.claude/skills/TEMPLATE.md` — skill šablon
- `.claude/agents/TEMPLATE.md` — agent šablon (sa placeholder-ima za buduće agente)
- `.claude/memory/session-log.md` — prazan log
- `docs/adr/TEMPLATE.md` — ADR šablon
- `docs/plans/TEMPLATE.md` — plan šablon

### Šta skill generiše (popunjeni fajlovi)

Ovi fajlovi se generišu sa popunjenim sadržajem na osnovu odgovora:

| Fajl | Šta se popunjava |
|------|------------------|
| `CLAUDE.md` | Naziv, stack, pravila, deployment, struktura. **APD Hard Rules sekcija se kopira VERBATIM iz template CLAUDE.md — orkestrator NE sme parafrazirati ili skraćivati ovu sekciju.** |
| `.claude/rules/principles.md` | Jezik dokumentacije, error handling za izabrani stack, arhitekturni pattern |
| `.claude/rules/conventions.md` | Naming konvencije za izabrani stack (camelCase/snake_case, struktura fajlova) |
| `.claude/scripts/verify-all.sh` | Otkomentarisan sa pravim build/test komandama za izabrani stack |
| `.claude/scripts/session-start.sh` | Zameni `[PROJECT_NAME]` sa nazivom projekta |
| `.claude/settings.json` | Zameni `[APSOLUTNA_PUTANJA]` u hook komandama i `[PROJECT_NAME]` u Notification hook-u |
| `.claude/agents/[stack]-builder.md` | Prvi agent sa konkretnim stack-om, scope-om, hook-ovima |
| `.claude/memory/MEMORY.md` | Naziv projekta, inicijalna faza |
| `.claude/memory/status.md` | Inicijalni status ("Faza: Setup završen") |
| `docs/adr/README.md` | Indeks sa ADR-0001 |
| `docs/adr/0001-inicijalni-stack.md` | Dokumentuje sve stack odluke sa alternativama |

### Šta se NE kopira

- `EXAMPLE-backend-builder.md` — nepotreban kad skill kreira pravog agenta
- `setup.sh` — nepotreban jer skill radi sve što setup.sh radi i više

### ADR-0001 format

ADR-0001 mora pratiti format iz `docs/adr/TEMPLATE.md`:

```markdown
# ADR-0001: Inicijalni tehnički stack

**Status:** Prihvaćen
**Datum:** [datum pokretanja]
**Zamenjuje:** —
**Zamenjen sa:** —

## Kontekst

Projekat [naziv] zahteva inicijalni izbor tehnološkog stack-a.

## Razmatrane opcije

[Orkestrator generiše relevantne alternative za izabrani stack]

## Odluka

- Backend: [odgovor na pitanje 2 — jezik + framework + baza/ORM]
- Frontend: [odgovor na pitanje 3]
- Arhitektura: [odgovor na pitanje 4]
- Deployment: [odgovor na pitanje 7]

## Posledice

- **Pozitivne:** [generisane na osnovu stack-a]
- **Negativne:** [trade-off-ovi izabranog stack-a]
- **Rizici:** [rizici izabranog stack-a]
```

### Scope detekcija za agenta

Kad kreira prvog agenta, skill detektuje dozvoljene putanje:
1. Ako postoji `src/` → koristi `src/` i `tests/` (ako postoji)
2. Ako postoji `app/` → koristi `app/`
3. Ako ništa ne postoji → pita korisnika: "Gde će živeti backend kod? (npr. src/, app/, lib/)"

### Commit

Na kraju, skill commituje sve kreirane fajlove. Koristi eksplicitno dodavanje svakog kreiranog fajla po imenu (ne `git add .claude/` jer to može uhvatiti neželjene fajlove ako `docs/` već postoji sa drugim sadržajem).

**VAŽNO:** Orkestrator MORA zameniti `[stack]` sa stvarnim imenom stack-a (npr. `express-builder.md`) i `[PROJECT_NAME]` sa nazivom projekta pre izvršavanja ovih komandi:

```bash
APD_ORCHESTRATOR_COMMIT=1 git add .claude/rules/workflow.md .claude/rules/principles.md .claude/rules/conventions.md \
  .claude/scripts/guard-git.sh .claude/scripts/guard-scope.sh .claude/scripts/verify-all.sh .claude/scripts/session-start.sh \
  .claude/settings.json .claude/skills/TEMPLATE.md .claude/agents/TEMPLATE.md .claude/agents/[stack]-builder.md \
  .claude/memory/MEMORY.md .claude/memory/session-log.md .claude/memory/status.md \
  CLAUDE.md docs/adr/TEMPLATE.md docs/adr/README.md docs/adr/0001-inicijalni-stack.md docs/plans/TEMPLATE.md
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: inicijalni APD setup za [PROJECT_NAME]"
```

### Pre-flight provere

Pre početka, skill proverava:
1. **Git inicijalizovan** — `git rev-parse --is-inside-work-tree`. Ako nije, ponudi `git init`.
2. **Postojeći `.claude/`** — ako postoji, pita korisnika da li želi overwrite ili prekid.
3. **jq instaliran** — `command -v jq`. Ako nije, obavesti korisnika da je potreban za hook skripte.

---

## Kompletna lista pogođenih fajlova

**U template repo-u:**

| Fajl | Akcija |
|------|--------|
| `.claude/skills/apd-init.md` | Create — skill definicija |

**U ciljnom projektu (kreira skill):**

| Fajl | Akcija |
|------|--------|
| `.claude/rules/workflow.md` | Kopira as-is |
| `.claude/scripts/guard-git.sh` | Kopira as-is |
| `.claude/scripts/guard-scope.sh` | Kopira as-is |
| `.claude/scripts/session-start.sh` | Generiše — zameni `[PROJECT_NAME]` |
| `.claude/skills/TEMPLATE.md` | Kopira as-is |
| `.claude/agents/TEMPLATE.md` | Kopira as-is |
| `.claude/memory/session-log.md` | Kopira as-is |
| `docs/adr/TEMPLATE.md` | Kopira as-is |
| `docs/plans/TEMPLATE.md` | Kopira as-is |
| `CLAUDE.md` | Generiše — popuni stack, pravila, deployment; APD Hard Rules verbatim |
| `.claude/rules/principles.md` | Generiše — jezik, error handling, arhitektura |
| `.claude/rules/conventions.md` | Generiše — naming konvencije za stack |
| `.claude/scripts/verify-all.sh` | Generiše — otkomentariše build/test komande |
| `.claude/settings.json` | Generiše — apsolutne putanje, `[PROJECT_NAME]` u Notification |
| `.claude/agents/[stack]-builder.md` | Generiše — prvi agent sa stack-om i scope-om |
| `.claude/memory/MEMORY.md` | Generiše — naziv, faza |
| `.claude/memory/status.md` | Generiše — inicijalni status |
| `docs/adr/README.md` | Generiše — indeks sa ADR-0001 |
| `docs/adr/0001-inicijalni-stack.md` | Generiše — stack odluke |

## Rizici

| Rizik | Mitigacija |
|-------|-----------|
| Korisnik pokrene skill u projektu koji već ima `.claude/` | Skill proverava na početku i pita da li želi overwrite |
| Korisnik da nepotpune odgovore | Skill ima default-ove za svako pitanje i validira odgovore |
| verify-all.sh ne radi za nepoznat stack | Skill stavlja komentare sa TODO za ručnu konfiguraciju |
| Skill je predugačak za context window | Skill sadrži samo instrukcije (~200 linija), ne kod — kompaktan |

## Acceptance kriterijumi

- [ ] Skill postoji u `.claude/skills/apd-init.md` i može se pozvati sa `/apd-init`
  - **Verifikacija:** Pročitaj fajl, proveri frontmatter format
- [ ] Skill pita svih 7 pitanja interaktivno
  - **Verifikacija:** Pokreni skill i verifikuj da pita svako pitanje
- [ ] Svi placeholder-i su zamenjeni u generisanim fajlovima (nijedan `[PROJECT_NAME]`, `[APSOLUTNA_PUTANJA]`, `[DOZVOLJENE_PUTANJE]` ne ostaje)
  - **Verifikacija:** `grep -r '\[PROJECT_NAME\]\|\[APSOLUTNA_PUTANJA\]\|\[DOZVOLJENE_PUTANJE\]' .claude/ CLAUDE.md` → 0 rezultata (osim u TEMPLATE fajlovima)
- [ ] verify-all.sh ima otkomentarisane build/test komande za izabrani stack
  - **Verifikacija:** Pročitaj fajl, proveri da nije sve zakomentarisano
- [ ] Prvi agent je kreiran sa konkretnim stack-om i scope-om
  - **Verifikacija:** Pročitaj `.claude/agents/[stack]-builder.md`
- [ ] ADR-0001 je kreiran sa stack odlukama
  - **Verifikacija:** Pročitaj `docs/adr/0001-inicijalni-stack.md`
- [ ] Sve je commitovano kao jedan commit
  - **Verifikacija:** `git log -1 --oneline`
- [ ] Skill detektuje postojeći `.claude/` i pita za overwrite
  - **Verifikacija:** Pokreni skill u projektu koji već ima `.claude/`
