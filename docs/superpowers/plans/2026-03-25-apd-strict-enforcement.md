# APD Strict Enforcement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Obezbediti striktno poštovanje APD workflow-a — orkestrator ne zaboravlja pravila tokom dugih sesija, agenti ne mogu izaći iz svog scope-a.

**Architecture:** Hibridni pristup: (1) CLAUDE.md Hard Rules sekcija koja preživljava context kompresiju, (2) ojačan guard-git.sh sa boljim porukama i zatvorenim rupama, (3) novi guard-scope.sh koji mehanički blokira agente van njihovog domena. Hook-ovi se oslanjaju na Claude Code PreToolUse hook sistem koji prima tool input JSON na stdin.

**Tech Stack:** Bash (hook skripte), jq (JSON parsing), Markdown (CLAUDE.md, agent definicije)

**Spec:** `docs/superpowers/specs/2026-03-25-apd-strict-enforcement-design.md`

---

## File Map

| Fajl | Akcija | Task |
|------|--------|------|
| `CLAUDE.md` | Modify | Task 1 |
| `.claude/scripts/guard-git.sh` | Modify | Task 2 |
| `.claude/scripts/guard-scope.sh` | Create | Task 3 |
| `.claude/agents/TEMPLATE.md` | Modify | Task 4 |
| `.claude/agents/EXAMPLE-backend-builder.md` | Modify | Task 4 |
| `.claude/scripts/setup.sh` | Modify | Task 4 |

---

### Task 1: CLAUDE.md Hard Rules sekcija

**Files:**
- Modify: `CLAUDE.md`

**Cilj:** Dodati kompresija-otpornu sekciju sa kritičnim APD pravilima koja orkestrator nikad ne gubi iz konteksta.

- [ ] **Step 1: Pročitaj trenutni CLAUDE.md**

Pročitaj ceo fajl da razumeš strukturu i nađeš pravo mesto za novu sekciju.

- [ ] **Step 2: Dodaj APD Hard Rules sekciju**

Dodaj kao novu `## APD Hard Rules` sekciju — **odmah pre** postojećeg `## Pravila`. Koristi `##` nivo (ne `###`) jer viši heading nivo bolje preživljava context kompresiju, što je ceo smisao ove sekcije:

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

- [ ] **Step 3: Verifikuj strukturu**

Proveri da CLAUDE.md ima ispravnu markdown strukturu — `## APD Hard Rules` je peer sa `## Pravila`, oba su pod `# [PROJECT_NAME]`.

- [ ] **Step 4: Commit**

```bash
APD_ORCHESTRATOR_COMMIT=1 git add CLAUDE.md
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: dodaj APD Hard Rules sekciju u CLAUDE.md za otpornost na kompresiju"
```

---

### Task 2: Ojačan guard-git.sh

**Files:**
- Modify: `.claude/scripts/guard-git.sh`

**Cilj:** Poboljšati poruke greške (tačna sintaksa za commit), blokirati `git add .`/`-A`/`--all`/`-u`/`*`, blokirati `git commit -a`, blokirati `--no-verify`.

- [ ] **Step 1: Pročitaj trenutni guard-git.sh**

Pročitaj ceo fajl da razumeš postojeću logiku i nađeš mesta za izmene.

- [ ] **Step 2: Dodaj blokadu `--no-verify`**

Dodaj odmah posle `INPUT=$(cat)` i `COMMAND` parsiranja (posle linije normalizacije), pre bilo kog drugog check-a:

```bash
# Blokiraj --no-verify kao standalone flag (ne u commit poruci)
# Matchuje --no-verify okružen razmakom ili na kraju stringa
if echo "$COMMAND" | grep -qE '(^| )--no-verify( |$)'; then
  echo "BLOKIRANO: --no-verify nije dozvoljen. Hook-ovi moraju proći." >&2
  exit 2
fi
```

Ovo mora biti na raw `$COMMAND` stringu, pre normalizacije, da uhvati sve varijante.

- [ ] **Step 3: Dodaj blokadu masovnog staging-a**

Dodaj posle `--no-verify` check-a, pre `git commit` check-a:

```bash
# Blokiraj masovni staging — forsira eksplicitno dodavanje fajlova po imenu
# Regex koristi word boundary (razmak ili kraj stringa) da ne blokira fajlove kao .gitignore
if echo "$NORMALIZED_GIT" | grep -qE "git add[[:space:]]+(\.([[:space:]]|$)|-[AuU]([[:space:]]|$)|--all([[:space:]]|$)|\*)"; then
  echo "BLOKIRANO: git add . / git add -A / git add --all / git add -u / git add * nije dozvoljen." >&2
  echo "Koristi: git add <fajl1> <fajl2> ..." >&2
  exit 2
fi
```

- [ ] **Step 4: Poboljšaj poruku pri blokadi commit-a**

U postojećem `git commit` bloku, izmeni `else` granu da ispiše tačnu sintaksu:

```bash
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    echo "Koristi: APD_ORCHESTRATOR_COMMIT=1 git commit -m \"opis promene\"" >&2
    exit 2
```

- [ ] **Step 5: Dodaj blokadu `git commit -a` / `git commit --all`**

U postojećem `git commit` bloku, unutar autorizovane grane (kad ima APD prefix), dodaj proveru za `-a`/`--all`:

```bash
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    # Blokiraj commit -a čak i sa prefixom — forsira eksplicitno staging
    # Napomena: ovo je strožije od spec-a (koji traži blokadu samo bez prefiksa),
    # ali je ispravno ponašanje — staging mora uvek biti eksplicitan
    if echo "$NORMALIZED_GIT" | grep -qE "git commit[[:space:]]+.*(-a([[:space:]]|$)|--all([[:space:]]|$))"; then
      echo "BLOKIRANO: git commit -a / --all nije dozvoljen. Stage-uj fajlove eksplicitno pre commit-a." >&2
      exit 2
    fi
    # Autorizovani commit — pokreni verifikaciju pre propuštanja
    # VAŽNO: zadrži CELU postojeću logiku ispod (verify-all.sh poziv itd.)
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -x "$SCRIPT_DIR/verify-all.sh" ]; then
      echo "→ Pokretanje verifikacije pre commit-a..." >&2
      if ! bash "$SCRIPT_DIR/verify-all.sh" >&2; then
        echo "BLOKIRANO: Verifikacija nije prošla. Commit odbijen." >&2
        exit 2
      fi
    fi
    # Verifikacija prošla — dozvoli commit
    exit 0
```

- [ ] **Step 6: Poboljšaj poruku pri blokadi push-a**

U postojećem `git push` bloku, izmeni `else` granu:

```bash
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    echo "Koristi: APD_ORCHESTRATOR_COMMIT=1 git push origin <branch>" >&2
    exit 2
```

- [ ] **Step 7: Testiraj guard-git.sh**

Pokreni ove komande i proveri da svaka daje BLOKIRANO:

```bash
echo '{"tool_input":{"command":"git add ."}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add -A"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add --all"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add -u"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit --no-verify -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit -a -m test"}}' | bash .claude/scripts/guard-git.sh
```

Proveri da ove komande PROLAZE (ne smeju biti blokirane):

```bash
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add src/main.ts tests/main.test.ts"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add .gitignore"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add .env.example"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git status"}}' | bash .claude/scripts/guard-git.sh
```

- [ ] **Step 8: Commit**

```bash
APD_ORCHESTRATOR_COMMIT=1 git add .claude/scripts/guard-git.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: ojačaj guard-git — bolje poruke, blokada add ./--no-verify/commit -a"
```

---

### Task 3: Kreiranje guard-scope.sh

**Files:**
- Create: `.claude/scripts/guard-scope.sh`

**Cilj:** Novi hook skript koji blokira Write/Edit operacije na fajlovima van dozvoljenog scope-a. Dozvoljene putanje se primaju kao argumenti skripte.

- [ ] **Step 1: Kreiraj guard-scope.sh**

```bash
#!/bin/bash
# APD Scope Guard — blokira Write/Edit operacije van dozvoljenog scope-a
# Korišćenje: bash guard-scope.sh <dozvoljena_putanja_1> <dozvoljena_putanja_2> ...
# Primer:    bash guard-scope.sh src/ tests/

# Dozvoljene putanje iz argumenata
ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  # Nema ograničenja — dozvoli sve
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-scope.sh." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  # Nema file_path u tool input-u — nije Write/Edit poziv, dozvoli
  exit 0
fi

# Konvertuj apsolutnu putanju u relativnu
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REL_PATH="${FILE_PATH#$PROJECT_DIR/}"

# Ako je putanja i dalje apsolutna (nije u projektu), blokiraj
if [[ "$REL_PATH" == /* ]]; then
  echo "BLOKIRANO: Fajl $FILE_PATH je van projektnog direktorijuma." >&2
  echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
  exit 2
fi

# Proveri da li relativna putanja počinje sa jednom od dozvoljenih
# Normalizuj: osiguraj trailing slash da izbegneš prefix kolizije (src vs src-legacy)
for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if [[ "$REL_PATH" == "$allowed"* ]]; then
    exit 0
  fi
done

# Nijedna dozvoljena putanja ne odgovara — blokiraj
echo "BLOKIRANO: Fajl $REL_PATH je van dozvoljenog scope-a." >&2
echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
exit 2
```

- [ ] **Step 2: Postavi execute permisije**

```bash
chmod +x .claude/scripts/guard-scope.sh
```

- [ ] **Step 3: Testiraj guard-scope.sh**

Pokreni iz root-a projekta. Blokirane operacije:

```bash
echo '{"tool_input":{"file_path":"'$(pwd)'/apps/frontend/App.tsx"}}' | bash .claude/scripts/guard-scope.sh src/ tests/
echo '{"tool_input":{"file_path":"'$(pwd)'/CLAUDE.md"}}' | bash .claude/scripts/guard-scope.sh src/ tests/
```

Dozvoljene operacije:

```bash
echo '{"tool_input":{"file_path":"'$(pwd)'/src/main.ts"}}' | bash .claude/scripts/guard-scope.sh src/ tests/
echo '{"tool_input":{"file_path":"'$(pwd)'/tests/main.test.ts"}}' | bash .claude/scripts/guard-scope.sh src/ tests/
```

Bez argumenata (sve dozvoljeno):

```bash
echo '{"tool_input":{"file_path":"'$(pwd)'/anything.txt"}}' | bash .claude/scripts/guard-scope.sh
```

- [ ] **Step 4: Commit**

```bash
APD_ORCHESTRATOR_COMMIT=1 git add .claude/scripts/guard-scope.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: dodaj guard-scope.sh — file-scope guard za agente"
```

---

### Task 4: Integracione izmene (agent template, example, setup)

**Files:**
- Modify: `.claude/agents/TEMPLATE.md`
- Modify: `.claude/agents/EXAMPLE-backend-builder.md`
- Modify: `.claude/scripts/setup.sh`

**Cilj:** Integrisati guard-scope.sh u agent template i primer, ažurirati setup.sh.

- [ ] **Step 1: Pročitaj trenutne fajlove**

Pročitaj sva tri fajla da razumeš trenutnu strukturu.

- [ ] **Step 2: Ažuriraj TEMPLATE.md — dodaj Write|Edit hook**

U `hooks` sekciji frontmatter-a, dodaj novi matcher pre postojećeg Bash matcher-a:

```yaml
hooks:
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-scope.sh [DOZVOLJENE_PUTANJE]"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-git.sh"
          timeout: 5
```

Dodaj komentar iznad hooks sekcije:

```yaml
# [DOZVOLJENE_PUTANJE] — zameni sa putanjama koje agent sme menjati, razdvojene razmakom
# Primer: src/ tests/
# guard-scope.sh blokira Write/Edit operacije van ovih putanja
```

- [ ] **Step 3: Ažuriraj EXAMPLE-backend-builder.md — konkretan scope**

Zameni hooks sekciju sa konkretnim putanjama:

```yaml
hooks:
  PreToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-scope.sh src/ tests/"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-git.sh"
          timeout: 5
```

- [ ] **Step 4: Ažuriraj setup.sh — podrška za guard-scope.sh putanje**

Postojeća logika u setup.sh već zamenjuje `[APSOLUTNA_PUTANJA]` u svim agent fajlovima (`for f in "$CLAUDE_DIR/agents/"*.md`). Ovo automatski pokriva i nove guard-scope.sh reference.

Proveri da logika zaista radi — pročitaj setup.sh i potvrdi da `sed` zamena pokriva agent fajlove. Ako je potrebno, dodaj zamenu i u scripts direktorijumu (ali guard-scope.sh sam koristi `$(dirname "$0")` pa ne treba apsolutnu putanju u sebi).

Jedina izmena: u "Sledeći koraci" sekciji na kraju, dodaj:

```bash
echo "  4. Postavi dozvoljene putanje u agent hooks (zameni [DOZVOLJENE_PUTANJE])"
```

- [ ] **Step 5: Verifikuj integaciju**

Proveri da:
1. TEMPLATE.md ima oba hook matcher-a (Write|Edit i Bash)
2. EXAMPLE-backend-builder.md ima konkretne putanje (src/, tests/)
3. setup.sh zamenjuje `[APSOLUTNA_PUTANJA]` u agent fajlovima

- [ ] **Step 6: Commit**

```bash
APD_ORCHESTRATOR_COMMIT=1 git add .claude/agents/TEMPLATE.md .claude/agents/EXAMPLE-backend-builder.md .claude/scripts/setup.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: integriši guard-scope u agent template i setup"
```

---

## Redosled izvršavanja

```
Task 1 (CLAUDE.md) ─── nezavisno
Task 2 (guard-git.sh) ─── nezavisno
Task 3 (guard-scope.sh) ──→ Task 4 (integracija zavisi od guard-scope.sh)
```

Task 1, 2, i 3 mogu paralelno. Task 4 zavisi od Task 3 (guard-scope.sh mora postojati pre integracije).

## Finalna verifikacija

```bash
# Guard-git: ove komande MORAJU biti BLOKIRANE
echo '{"tool_input":{"command":"git add ."}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add -A"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit --no-verify -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git commit -a -m test"}}' | bash .claude/scripts/guard-git.sh

# Guard-git: ove komande MORAJU PROĆI
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add src/main.ts"}}' | bash .claude/scripts/guard-git.sh
echo '{"tool_input":{"command":"git add .gitignore"}}' | bash .claude/scripts/guard-git.sh

# Guard-scope: BLOKIRANO (van scope-a)
echo '{"tool_input":{"file_path":"'$(pwd)'/apps/frontend/App.tsx"}}' | bash .claude/scripts/guard-scope.sh src/ tests/

# Guard-scope: PROLAZI (u scope-u)
echo '{"tool_input":{"file_path":"'$(pwd)'/src/main.ts"}}' | bash .claude/scripts/guard-scope.sh src/ tests/

# CLAUDE.md: Hard Rules sekcija postoji
grep -c "APD Hard Rules" CLAUDE.md
# → 1
```
