# Agent Pipeline Development (APD) Template

Softverski razvoj kroz specijalizovane agente u definisanom pipeline-u sa verifikacijama i human gate-ovima.

## Šta je APD?

APD je workflow za AI-asistiran razvoj softvera gde:
- **Agent** — rad dele specijalizovani agenti sa jasnim domenima, ne jedan generički AI
- **Pipeline** — definisan tok sa fazama, verifikacijama i gate-ovima koji se ne preskaču
- **Development** — softverski razvoj kao krajnji cilj

## Pipeline

```
Spec kartica → Builder → Reviewer → Verifier → Commit → [Human gate] → Push
```

Svaka implementacija prolazi sve faze — bez izuzetaka. Reviewer se nikad ne preskače, čak ni za "trivijalne" promene.

## Brzi start

### Preduslovi

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI instaliran
- `jq` instaliran (`brew install jq` na macOS, `apt install jq` na Linux) — potreban za hook skripte
- Git repozitorijum inicijalizovan

### Setup

```bash
# 1. Kopiraj template u svoj projekat
cp -r .claude/ /putanja/do/projekta/.claude/
cp CLAUDE.md /putanja/do/projekta/
cp -r docs/ /putanja/do/projekta/docs/

# 2. Pokreni setup (zamenjuje placeholder-e sa apsolutnim putanjama)
cd /putanja/do/projekta
bash .claude/scripts/setup.sh

# 3. Prilagodi za svoj projekat (vidi sekciju "Šta prilagoditi")
```

`setup.sh` interaktivno:
- Zamenjuje `[APSOLUTNA_PUTANJA]` u `settings.json` i agent fajlovima sa stvarnom putanjom projekta
- Opciono zamenjuje `[PROJECT_NAME]` sa nazivom tvog projekta

## Četiri role

### Orkestrator (Claude Code — glavna sesija)
Centralni koordinator koji upravlja celim pipeline-om:
- Kreira spec karticu i deli sa korisnikom pre implementacije
- Dispatch-uje Builder agente (paralelno gde je moguće)
- Automatski pokreće Reviewer-a posle svake implementacije
- Pokreće Verifier-a pre commitovanja
- **Jedini** commituje i push-uje (koristi `APD_ORCHESTRATOR_COMMIT=1` prefix)
- **Jedini** komunicira sa korisnikom

### Builder (subagent)
Specijalizovani agenti koji implementiraju kod prema spec-u:
- Jedan agent per domen (backend, frontend, mobile...)
- Max 3-4 edit operacije po dispatch-u
- Jasno vlasništvo nad fajlovima — bez preklapanja između agenata
- **Ne sme** commitovati, push-ovati, niti menjati fajlove van svog domena
- Definisan u `.claude/agents/` sa hook-ovima koji mehanički blokiraju kršenja

### Reviewer (subagent)
Traži bagove, rizike i propuste u Builder-ovom radu:
- Pokreće se automatski posle svakog Builder-a
- Traži: regresije, edge case-ove, security rupe, cross-layer mismatch
- **Ne** predlaže stilske promene ili refactoring van scope-a

### Verifier (skripta)
Automatska verifikacija pre commit-a:
- Pokreće `verify-all.sh` (build + test)
- Automatski se pokreće kroz `guard-git.sh` hook kad orkestrator pokušava commit
- Blokira commit ako build ili testovi ne prolaze

## Spec kartica

Pre svakog taska (bez obzira na veličinu), orkestrator kreira spec karticu:

```
## [Naziv taska]
**Cilj:** Jedna rečenica.
**Effort:** max | high
**Van scope-a:** Šta NE radimo.
**Acceptance kriterijumi:** Lista uslova za "gotovo".
**Pogođeni moduli:** Fajlovi/slojevi koji se menjaju.
**Rizici:** Šta može poći po zlu.
**Rollback:** Kako vratiti ako pukne.
**Human gate:** Da li zahteva odobrenje (API promene, migracije, auth, prod data).
**ADR:** ADR-NNNN | Potreban | N/A
```

Spec se deli sa korisnikom PRE implementacije. Korisnik odobrava ili koriguje.

### Effort nivoi

| Effort | Kada | Ko |
|--------|------|----|
| **max** | Odluke koje je skupo ispraviti | Orkestrator, Reviewer, Verifier |
| **high** | Implementacija po jasnom spec-u | Builder agenti |

## Human gate

Korisnik MORA odobriti pre:
- API promene (novi endpointi, promena potpisa)
- Migracije baze (nove tabele, promene kolona)
- Auth/role logika (promene u autorizaciji)
- Deploy na staging/produkciju
- Bilo šta što utiče na produkcijske podatke

Format: orkestrator prikaže diff summary → korisnik kaže "ok" → tek onda akcija.

## Guardrail sistem

APD koristi mehaničke guardrail-e (hook skripte) koji blokiraju kršenja čak i kad agent "zaboravi" pravila.

### guard-git.sh — Git operacije

PreToolUse hook na svakom Bash pozivu. Blokira:

| Operacija | Razlog |
|-----------|--------|
| `git commit` bez `APD_ORCHESTRATOR_COMMIT=1` prefiksa | Samo orkestrator sme commitovati |
| `git push` bez `APD_ORCHESTRATOR_COMMIT=1` prefiksa | Samo orkestrator sme push-ovati |
| `git add .` / `git add -A` / `git add --all` / `git add -u` / `git add *` | Forsira eksplicitno dodavanje fajlova po imenu |
| `git commit -a` / `git commit --all` | Forsira eksplicitno staging pre commit-a |
| `--no-verify` | Sprečava zaobilaženje hook-ova |
| `git reset --hard`, `git clean -f`, itd. | Blokira destruktivne operacije |
| `Co-Authored-By` | Blokira AI potpise u commitima |
| `git add .claude/` bez prefiksa | Štiti workflow fajlove |

Kad blokira commit/push, ispisuje tačnu sintaksu koju orkestrator treba da koristi.

### guard-scope.sh — File scope za agente

PreToolUse hook na Write/Edit pozivima u agent definicijama. Svaki agent definiše dozvoljene putanje:

```yaml
# U agent .md fajlu:
hooks:
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash /putanja/.claude/scripts/guard-scope.sh src/ tests/"
```

Agent koji pokuša da edituje fajl van `src/` ili `tests/` dobija:
```
BLOKIRANO: Fajl apps/frontend/App.tsx je van dozvoljenog scope-a.
Dozvoljene putanje: src/ tests/
```

### verify-all.sh — Build i test verifikacija

Automatski se pokreće pre svakog commit-a (poziva ga `guard-git.sh`). Detektuje koje fajlove commitujete i pokreće relevantne provere:
- Backend promene → build + test komande
- Frontend promene → type check + test komande

**VAŽNO:** Dolazi sa zakomentarisanim primerima — mora se konfigurisati za vaš build/test sistem.

### session-start.sh — Kontekst na početku sesije

SessionStart hook koji učitava:
- Trenutni status projekta iz `memory/status.md`
- Poslednjih 20 linija iz `memory/session-log.md`

Ovo daje orkestratoru kontekst o tome gde je projekat stao.

## ADR (Architecture Decision Records)

Arhitekturne odluke se dokumentuju u `docs/adr/` sa punim kontekstom: zašto je odluka doneta, koje alternative su razmatrane, i koje su posledice.

### Kada kreirati ADR

- Uvođenje nove tehnologije ili biblioteke
- Promena API dizajna ili komunikacionog paterna
- Izbor između dva validna arhitekturna pristupa
- Promena auth/security strategije
- Migracija podataka ili promena šeme

### Životni ciklus

```
Predložen → Prihvaćen → [Zamenjen (novi ADR) | Povučen]
```

- `Predložen` — može se menjati dok nije prihvaćen
- `Prihvaćen` — **immutable**. Ako se odluka promeni, kreira se novi ADR koji zamenjuje starog
- Numeracija: `0001`, `0002`, ... (4 cifre sa vodećim nulama)

### Veza sa principles.md

`principles.md` kaže **šta** (pravila), ADR kaže **zašto** (kontekst odluke):

```markdown
## Kod
- Error handling: Result pattern (vidi ADR-0004)
- Arhitekturni pattern: Vertical Slice (vidi ADR-0001)
```

## Session memory

Posle svakog završenog taska, orkestrator append-uje zapis u `memory/session-log.md`:

```markdown
## [YYYY-MM-DD] [Naziv taska]
**Status:** Završen | Delimičan | Blokiran
**Šta je urađeno:** [1-2 rečenice]
**Problemi:** [Šta je pošlo po zlu, ili "Bez problema"]
**Guardrail koji je pomogao:** [Koji mehanizam je uhvatio problem, ili "N/A"]
**Novo pravilo:** [Šta dodajemo u workflow, ili "Nema"]
```

Ako je novo pravilo identifikovano, orkestrator ga odmah dodaje u relevantni rules fajl. Greške postaju guardrail-i.

## Cross-layer verifikacija

Kad task uključuje backend + frontend/mobile:

1. Backend DTO/response model je **izvor istine**
2. Za svako polje, mapirati tip na frontend/mobile ekvivalent
3. Nullable polja moraju biti nullable na svim slojevima
4. Datumi: uvek ISO 8601 string na frontend/mobile strani
5. **NIKADA** ne kreirati frontend/mobile tip iz specifikacije — uvek čitaj backend DTO

Dodaj tabelu mapiranja tipova za svoj stack u `workflow.md`.

## Memorija — dva sistema

| | APD memorija (`.claude/memory/`) | Claude auto memorija (`~/.claude/projects/`) |
|---|---|---|
| **Šta čuva** | Projektno znanje — status, session log, naučene lekcije | Lične preference korisnika |
| **Ko koristi** | Svi na projektu (orkestrator + agenti) | Samo taj korisnik na toj mašini |
| **Gde živi** | U repozitorijumu — commituje se | Lokalno — NE commituje se |
| **Primer** | "Auth middleware mora koristiti Redis sessione" | "Korisnik preferira kratke odgovore" |

### Fajlovi

- `memory/MEMORY.md` — indeks projektne memorije (roadmap, naučene lekcije)
- `memory/session-log.md` — append-only log završenih taskova
- `memory/status.md` — trenutni status projekta (faza, fokus, blokeri)

## Rules vs Skills

| | Rules (`.claude/rules/`) | Skills (`.claude/skills/`) |
|---|---|---|
| **Učitavanje** | Uvek, automatski za sve agente | Eksplicitno, kad agent treba konvencije |
| **Sadržaj** | Globalna pravila i workflow | Convention snippet-ovi i procedure |
| **Primer** | `workflow.md` — APD pipeline definicija | Naming konvencije za API endpointe |

## settings.json — Hook konfiguracija

Definiše automatsko ponašanje Claude Code sesije:

Hook-ovi konfigurisani u `settings.json`:

| Hook | Skripta | Šta radi |
|------|---------|----------|
| `SessionStart` | `session-start.sh` | Učitava projektni kontekst (status, poslednja sesija) |
| `PreToolUse (Bash)` | `guard-git.sh` | Blokira neovlašćene git operacije |
| `Notification` | — | Desktop notifikacija kad Claude treba pažnju (macOS: `osascript`, Linux: `notify-send`) |

Ostala podešavanja:

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"` — omogućava agent teams
- `attribution.commit: ""` i `attribution.pr: ""` — prazno, nema AI potpisa u commitima

**Napomena:** `guard-scope.sh` hook se NE stavlja u `settings.json` (globalni) već samo u individualne agent `.md` fajlove — jer orkestrator mora imati pristup svim fajlovima.

## Struktura

```
.claude/
├── agents/                          # Builder agenti — jedan per domen
│   ├── TEMPLATE.md                  # Šablon za novog agenta
│   └── EXAMPLE-backend-builder.md   # Primer popunjenog agenta
├── rules/
│   ├── workflow.md                  # APD workflow definicija (UNIVERZALNO)
│   ├── principles.md               # Projektna pravila (PRILAGODITI)
│   └── conventions.md              # Coding konvencije (PRILAGODITI)
├── skills/                          # Convention snippet-ovi za agente
│   └── TEMPLATE.md                  # Šablon za novi skill
├── scripts/
│   ├── guard-git.sh                 # Git guardrail — blokira neovlašćene operacije (UNIVERZALNO)
│   ├── guard-scope.sh               # File scope guardrail — blokira agente van domena (UNIVERZALNO)
│   ├── verify-all.sh                # Build + test verifikacija (PRILAGODITI)
│   ├── setup.sh                     # Inicijalni setup — zamena placeholder-a
│   └── session-start.sh             # Učitava kontekst na početku sesije
└── memory/
    ├── MEMORY.md                    # Indeks memorije — akumulira se tokom rada
    ├── session-log.md               # Append-only log završenih taskova
    └── status.md                    # Trenutni status projekta

CLAUDE.md                            # Projektne instrukcije — uvek u kontekstu (PRILAGODITI)
docs/
├── adr/                             # Architecture Decision Records
│   ├── TEMPLATE.md                  # Šablon za ADR
│   └── README.md                    # Indeks svih ADR-ova
└── plans/                           # Implementacioni planovi
    └── TEMPLATE.md                  # Šablon za plan
```

## Šta prilagoditi

| Fajl | Šta | Prioritet |
|------|-----|-----------|
| `CLAUDE.md` | Stack, konvencije, struktura projekta, naziv | **Obavezno** |
| `verify-all.sh` | Build i test komande za svoj stack | **Obavezno** |
| `principles.md` | Jezik, error handling, arhitekturni pattern | **Obavezno** |
| `conventions.md` | Imenovanje, struktura fajlova, API stil | Preporučeno |
| `agents/TEMPLATE.md` | Kreirati konkretne agente za svoje domene | Preporučeno |
| `settings.json` | Automatski konfiguriše `setup.sh` | Automatski |
| `docs/adr/TEMPLATE.md` | Prilagoditi format ADR-a ako treba | Opciono |

### CLAUDE.md — šta popuniti

CLAUDE.md je najvažniji fajl — jedini koji je **uvek** u Claude Code kontekstu (nikad se ne kompresuje). Sadrži:

- **O projektu** — kratak opis, ciljna baza korisnika — **POPUNITI**
- **Tehnički stack** — backend, frontend, infrastruktura — **POPUNITI**
- **APD Hard Rules** — kritična pravila koja preživljavaju context kompresiju. **NE MENJATI** — ova sekcija je univerzalna i dolazi pre-popunjena (commit flag, pipeline redosled, agent scope, human gate, session memory). Duplirana je iz `workflow.md` upravo zato što CLAUDE.md nikad ne ispada iz konteksta.
- **Pravila** — jezik, git konvencije — **POPUNITI**
- **ADR** — pravila za arhitekturne odluke — pre-popunjeno
- **Plugini i alati** — lista preporučenih plugina po fazi (brainstorming, builder, reviewer, verifier, post-commit, Figma) — **PREGLEDATI I PRILAGODITI** za svoj projekat
- **Struktura projekta** — gde šta živi — **PRILAGODITI**

### Agenti — kako kreirati novog

1. Kopiraj `agents/TEMPLATE.md`
2. Popuni: naziv, opis, stack, arhitektura, workflow koraci
3. **Zameni `[DOZVOLJENE_PUTANJE]`** u guard-scope.sh hook argumentima sa putanjama koje agent sme menjati (npr. `src/ tests/`). Ovo se NE zamenjuje automatski od strane `setup.sh` — mora se ručno podesiti per agent.
4. Pokreni `setup.sh` ili ručno zameni `[APSOLUTNA_PUTANJA]`

Primer: `EXAMPLE-backend-builder.md` — backend agent sa scope-om `src/` i `tests/`.

**VAŽNO:** Ako ne zameniš `[DOZVOLJENE_PUTANJE]`, guard-scope.sh će blokirati SVE Write/Edit operacije tog agenta jer nijedna putanja ne počinje sa literalnim `[DOZVOLJENE_PUTANJE]`.

### verify-all.sh — kako konfigurisati

Dolazi zakomentarisan. Otkomentariši i podesi za svoj stack:

```bash
# Node.js:  npm test
# Python:   pytest tests/
# Go:       go build ./... && go test ./...
# .NET:     dotnet build && dotnet test
```

Skripta automatski detektuje koje fajlove commitujete i pokreće samo relevantne provere.

## Preporučeni plugini

APD template je dizajniran da radi sa [Superpowers](https://github.com/anthropics/claude-code-plugins) pluginom za Claude Code. Ovo je podskup — puna lista u `CLAUDE.md` sekciji "Plugini i alati":

| Faza | Plugin/Skill | Opis |
|------|-------------|------|
| Pre implementacije | `superpowers:brainstorming` | Istražuje nameru, zahteve, dizajn |
| Pre implementacije | `superpowers:writing-plans` | Kreira implementacioni plan iz spec-a |
| Builder | `superpowers:subagent-driven-development` | Paralelni agenti za nezavisne taskove |
| Builder | `superpowers:test-driven-development` | TDD workflow |
| Builder | `superpowers:systematic-debugging` | Sistematski debugging pre fix-a |
| Reviewer | `superpowers:requesting-code-review` | Review po završetku implementacije |
| Reviewer | `simplify` | Review za kvalitet i efikasnost |
| Verifier | `superpowers:verification-before-completion` | Verifikacija pre tvrdnje da je gotovo |
| Post-commit | `superpowers:finishing-a-development-branch` | Merge, PR, cleanup opcije |

## Principi

1. **Spec pre koda** — svaki task počinje mini-spec karticom koju korisnik odobri
2. **Tri role** — Builder (implementira) → Reviewer (nalazi bagove) → Verifier (potvrđuje)
3. **Mikro-zadaci** — max 3-4 edit operacije po agentu, jasno vlasništvo nad fajlovima
4. **Human gate** — čovek odobrava API promene, migracije, auth logiku, deploy
5. **Cross-layer verifikacija** — frontend/mobile tipovi moraju biti 1:1 sa backend DTO-ovima
6. **Greškom-vođeni guardrail-i** — svaka greška postaje novo pravilo u memoriji
7. **Session memory** — posle svakog taska: šta je urađeno, šta je pošlo po zlu, nova pravila
8. **ADR za arhitekturu** — arhitekturne odluke se dokumentuju sa kontekstom, alternativama i posledicama
