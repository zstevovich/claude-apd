# APD Template Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poboljšati APD template sa 6 konkretnih unapređenja: setup automatizacija, pametnije hookove, jači guardrail, skills template, robusniji guard i definisan session memory format.

**Architecture:** Task-ovi 1, 2, 5 i 6 su nezavisni. Task 3 zavisi od 1 i 2 (menja isti guard-git.sh). Task 4 zavisi od 3 (setup.sh mora znati finalni oblik fajlova).

**Tech Stack:** Bash (macOS/BSD kompatibilno), JSON, Markdown

---

## File Map

| Fajl | Akcija | Task-ovi |
|------|--------|----------|
| `.claude/scripts/guard-git.sh` | Modify | Task 1 (regex), Task 2 (token), Task 3 (verify) |
| `.claude/settings.json` | Modify | Task 3 (ukloni Stop hook) |
| `.claude/scripts/setup.sh` | Create | Task 4 |
| `.claude/agents/TEMPLATE.md` | Modify | Task 2 (token naziv) |
| `.claude/skills/TEMPLATE.md` | Create | Task 5 |
| `.claude/rules/workflow.md` | Modify | Task 6 (session memory format) |
| `.claude/memory/MEMORY.md` | Modify | Task 6 |
| `.claude/memory/session-log.md` | Create | Task 6 |
| `README.md` | Modify | Task 4 (setup korak) |

---

### Task 1: Robustniji guard-git.sh regex

**Files:**
- Modify: `.claude/scripts/guard-git.sh`

**Cilj:** Normalizovati komandu pre provere — kolapsirati razmake, stripovati env var prefix-e, hendlati git opcije pre subcommand-a, case-insensitive matching.

- [ ] **Step 1: Dodaj normalizaciju komande i env var stripping**

Posle linije `COMMAND=$(echo "$INPUT" | jq ...)`, dodati:

```bash
# Normalizuj: kolapsiraj razmake, skini vodeći whitespace
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')

# Stripuj env var prefix-e (VAR=value VAR2=value ... komanda)
STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')

# Normalizuj git opcije: ukloni -C path, --git-dir=path itd.
NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')
```

- [ ] **Step 2: Ažuriraj sve git provere da koriste NORMALIZED_GIT i COMMAND**

Pravilo: `COMMAND` se koristi za proveru auth prefix-a (`APD_ORCHESTRATOR_COMMIT=1`), `NORMALIZED_GIT` za proveru git subcommand-a.

Zameni sve `echo "$COMMAND" | grep -qE "git ..."` u sekcijama za commit, push, .claude, i destruktivne operacije sa `echo "$NORMALIZED_GIT" | grep -qiE "git ..."`.

Auth prefix provere (`^APD_ORCHESTRATOR_COMMIT=1`) ostaju na `$COMMAND`.

- [ ] **Step 3: Poboljšaj destruktivne operacije regex**

```bash
# Staro:
if echo "$COMMAND" | grep -qE "git (reset --hard|clean -f|checkout (--)? ?\.|restore|branch -[Dd]|stash drop)"; then

# Novo — macOS kompatibilno, case-insensitive, šire pokrivanje:
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+(--[[:space:]]+)?[.*]|restore[[:space:]]|branch[[:space:]]+-[Dd]|stash[[:space:]]+drop)"; then
```

- [ ] **Step 4: Testiraj guard-git.sh sa edge case-ovima**

```bash
cd /Users/zoranstevovic/Projects/apd-template

# Treba da prodje (exit 0):
echo '{"tool_input":{"command":"git status"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 0

# Treba da blokira (exit 2) — višestruki razmaci:
echo '{"tool_input":{"command":"git   reset  --hard"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 2

# Treba da blokira (exit 2) — git opcija pre subcommand-a:
echo '{"tool_input":{"command":"git -C /tmp reset --hard"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 2

# Treba da blokira (exit 2) — env var prefix:
echo '{"tool_input":{"command":"GIT_DIR=/tmp git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 2

# Treba da blokira (exit 2) — git add .claude:
echo '{"tool_input":{"command":"git add .claude/memory"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 2
```

---

### Task 2: Jači ALLOW_GIT guardrail

**Files:**
- Modify: `.claude/scripts/guard-git.sh`
- Modify: `.claude/agents/TEMPLATE.md`

**Cilj:** Promeniti `ALLOW_GIT=1` u `APD_ORCHESTRATOR_COMMIT=1` — duži, jedinstveniji token manje verovatan za hallucination.

- [ ] **Step 1: Zameni ALLOW_GIT=1 u oba commit i push bloka**

Commit blok:
```bash
# Staro:
if ! echo "$COMMAND" | grep -qE "^ALLOW_GIT=1 "; then
    echo "BLOKIRANO: git commit dozvoljen samo sa ALLOW_GIT=1 prefixom." >&2

# Novo:
if ! echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
```

Push blok:
```bash
# Staro:
if ! echo "$COMMAND" | grep -qE "^ALLOW_GIT=1 "; then
    echo "BLOKIRANO: git push dozvoljen samo sa ALLOW_GIT=1 prefixom." >&2

# Novo:
if ! echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
```

- [ ] **Step 2: Dodaj objašnjavajući komentar iznad commit/push blokova**

```bash
# APD_ORCHESTRATOR_COMMIT=1 je duži token koji je manje verovatan da ga
# subagent hallucinate. Samo orkestrator sme koristiti ovaj prefix.
# Ovo je "soft" guardrail — dovoljno robustan za praktičnu upotrebu.
```

- [ ] **Step 3: Ažuriraj TEMPLATE.md agent šablon**

Zameni liniju 38:
```markdown
# Staro:
- **NIKADA ne commituj izmene** — git add, git commit, git push su ZABRANJENI. Orkestrator kontroliše commitove.

# Novo:
- **NIKADA ne commituj izmene** — git add, git commit, git push su ZABRANJENI. Orkestrator kontroliše commitove korišćenjem `APD_ORCHESTRATOR_COMMIT=1` prefiksa.
```

---

### Task 3: Premesti verify iz Stop hook-a u pre-commit guard

**Files:**
- Modify: `.claude/settings.json`
- Modify: `.claude/scripts/guard-git.sh`

**Cilj:** Ukloniti verify-all.sh iz Stop hook-a (prešumno — pokreće se na svaki Stop event) i integrisati verifikaciju u guard-git.sh tako da se automatski pokrene kad orkestrator commituje.

**Zavisi od:** Task 1, Task 2 (guard-git.sh mora imati finalne regex-e i token)

- [ ] **Step 1: Ukloni Stop hook iz settings.json**

Obrisati ceo `"Stop": [...]` blok i trailing zarez iz hooks sekcije. Rezultat:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "bash [APSOLUTNA_PUTANJA]/.claude/scripts/session-start.sh",
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
            "command": "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-git.sh",
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
            "command": "osascript -e 'display notification \"Claude Code treba pažnju\" with title \"[PROJECT_NAME]\"' 2>/dev/null || true"
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

- [ ] **Step 2: Dodaj verify integraciju u guard-git.sh**

Dodati na početak commit bloka, **PRE** provere da li je commit blokiran. Ovo znači: kad detektujemo `git commit` u NORMALIZED_GIT, prvo proverimo da li ima auth token. Ako ima, pokreni verify pa pusti. Ako nema, blokiraj.

Finalna struktura commit bloka u guard-git.sh:

```bash
# --- git commit ---
if echo "$NORMALIZED_GIT" | grep -qiE "git commit"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    # Autorizovani commit — pokreni verifikaciju pre propuštanja
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
  else
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi
```

Ista logika za push blok (bez verify poziva):

```bash
# --- git push ---
if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi
```

- [ ] **Step 3: Testiraj integraciju**

```bash
cd /Users/zoranstevovic/Projects/apd-template

# Autorizovani commit — verify prolazi (sve zakomentarisano):
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 0

# Neautorizovani commit — blokiran:
echo '{"tool_input":{"command":"git commit -m test"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 2

# Autorizovani push:
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push origin main"}}' | bash .claude/scripts/guard-git.sh
echo $?  # Expected: 0
```

- [ ] **Step 4: Verifikuj finalni guard-git.sh sintaksu**

```bash
bash -n .claude/scripts/guard-git.sh
echo $?  # Expected: 0
```

---

### Task 4: Setup skripta

**Files:**
- Create: `.claude/scripts/setup.sh`
- Modify: `README.md`

**Zavisi od:** Task 3 (settings.json mora biti u finalnom obliku)

- [ ] **Step 1: Kreiraj setup.sh**

```bash
#!/bin/bash
# APD Setup — zamenjuje placeholder-e sa apsolutnom putanjom projekta

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$PROJECT_DIR/.claude"

echo "APD Setup"
echo "========="
echo "Projekat: $PROJECT_DIR"
echo ""

# Zameni [APSOLUTNA_PUTANJA] u settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if grep -q '\[APSOLUTNA_PUTANJA\]' "$CLAUDE_DIR/settings.json"; then
        sed -i '' "s|\[APSOLUTNA_PUTANJA\]|$PROJECT_DIR|g" "$CLAUDE_DIR/settings.json"
        echo "✓ settings.json — putanja konfigurisana"
    else
        echo "· settings.json — već konfigurisano"
    fi
fi

# Zameni [APSOLUTNA_PUTANJA] u agent fajlovima
for f in "$CLAUDE_DIR/agents/"*.md; do
    [ -f "$f" ] || continue
    if grep -q '\[APSOLUTNA_PUTANJA\]' "$f"; then
        sed -i '' "s|\[APSOLUTNA_PUTANJA\]|$PROJECT_DIR|g" "$f"
        echo "✓ $(basename "$f") — putanja konfigurisana"
    fi
done

# Zameni [PROJECT_NAME] ako korisnik želi
echo ""
read -p "Naziv projekta (ili Enter za preskakanje): " PROJECT_NAME
if [ -n "$PROJECT_NAME" ]; then
    # Svi fajlovi koji sadrže [PROJECT_NAME]
    TARGET_FILES=(
        "$CLAUDE_DIR/settings.json"
        "$CLAUDE_DIR/scripts/session-start.sh"
        "$CLAUDE_DIR/memory/MEMORY.md"
        "$CLAUDE_DIR/agents/"*.md
        "$PROJECT_DIR/CLAUDE.md"
    )
    for f in "${TARGET_FILES[@]}"; do
        [ -f "$f" ] || continue
        if grep -q '\[PROJECT_NAME\]' "$f"; then
            sed -i '' "s|\[PROJECT_NAME\]|$PROJECT_NAME|g" "$f"
            echo "✓ $(basename "$f") — naziv projekta setovan"
        fi
    done
fi

echo ""
echo "Setup završen."
echo "Sledeći koraci:"
echo "  1. Prilagodi CLAUDE.md za svoj projekat"
echo "  2. Prilagodi verify-all.sh za svoj build/test sistem"
echo "  3. Kreiraj agente u .claude/agents/ po potrebi"
```

- [ ] **Step 2: Postavi executable permisiju**

```bash
chmod +x .claude/scripts/setup.sh
```

- [ ] **Step 3: Ažuriraj README.md — dodaj setup korak**

Zameni sekciju "Kako koristiti" (linije 19-24):

```markdown
## Kako koristiti

1. Kopiraj `.claude/` direktorijum i `CLAUDE.md` u svoj projekat
2. Pokreni setup: `bash .claude/scripts/setup.sh`
3. Prilagodi `CLAUDE.md` za svoj projekat (stack, konvencije, struktura)
4. Prilagodi agente u `.claude/agents/` za svoje domene
5. Prilagodi `verify-all.sh` za svoj build/test sistem
6. Dodaj `.claude/` u `.gitignore`
```

- [ ] **Step 4: Ažuriraj README strukturu — dodaj setup.sh**

U sekciji "Struktura" dodaj `setup.sh` u listu skripti:

```markdown
├── scripts/
│   ├── guard-git.sh     # Blokira neovlašćene git operacije (UNIVERZALNO)
│   ├── verify-all.sh    # Build + test verifikacija (PRILAGODITI)
│   ├── setup.sh         # Inicijalni setup — zamena placeholder-a
│   └── session-start.sh # Učitava kontekst na početku sesije
```

---

### Task 5: Skills direktorijum sa TEMPLATE

**Files:**
- Create: `.claude/skills/TEMPLATE.md`

**Nezavisan** — može se raditi paralelno sa ostalim task-ovima.

- [ ] **Step 1: Kreiraj `.claude/skills/TEMPLATE.md`**

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

### [Kategorija 2]
- [Pravilo/pattern]
- [Primer]

## Primeri

### Dobro
```
[Primer koda koji poštuje konvenciju]
```

### Loše
```
[Primer koda koji krši konvenciju]
```
```

---

### Task 6: Session memory format

**Files:**
- Modify: `.claude/rules/workflow.md`
- Modify: `.claude/memory/MEMORY.md`
- Create: `.claude/memory/session-log.md`

**Nezavisan** — može se raditi paralelno sa ostalim task-ovima.

- [ ] **Step 1: Zameni sekciju 6 u workflow.md**

Zameni linije 84-90 (sekcija "6. Session memory update") sa:

```markdown
## 6. Session memory update

Posle SVAKOG završenog taska, orkestrator upisuje zapis u `.claude/memory/session-log.md`.

### Format zapisa

```markdown
## [YYYY-MM-DD] [Naziv taska]
**Status:** Završen | Delimičan | Blokiran
**Šta je urađeno:** [1-2 rečenice — konkretan rezultat]
**Problemi:** [Šta je pošlo po zlu, ili "Bez problema"]
**Guardrail koji je pomogao:** [Koji mehanizam je uhvatio problem, ili "N/A"]
**Novo pravilo:** [Šta dodajemo u workflow, ili "Nema"]
```

### Pravila
- Svaki zapis je **append** na kraj fajla — nikada ne brisati stare zapise
- Maksimum 3 rečenice po polju — kratkost je ključna
- Ako je novo pravilo identifikovano, orkestrator ga ODMAH dodaje u relevantni rules fajl
- Session log se čita na početku sesije (session-start.sh prikazuje poslednjih 20 linija)
```

- [ ] **Step 2: Ažuriraj MEMORY.md — dodaj referencu na session-log.md**

Zameni liniju 13 (`- (Akumulira se tokom rada)`) sa:

```markdown
- (Akumulira se tokom rada — pogledaj session-log.md za detalje)
```

- [ ] **Step 3: Kreiraj `.claude/memory/session-log.md`**

```markdown
# Session Log

<!-- Svaki završen task dobija zapis ispod. Format: pogledaj .claude/rules/workflow.md sekcija 6. -->
```

---

## Redosled izvršavanja

```
Task 1 (guard regex)  ─┐
                       ├─→ Task 3 (verify integracija) ─→ Task 4 (setup.sh)
Task 2 (jači token)   ─┘
Task 5 (skills)       ─── nezavisno
Task 6 (session mem)  ─── nezavisno
```

Task 1, 2, 5 i 6 su međusobno nezavisni i mogu se raditi paralelno.
Task 3 zavisi od Task 1 i 2 (jer menja isti fajl guard-git.sh).
Task 4 zavisi od Task 3 (setup.sh mora znati finalni oblik fajlova).

## Finalna verifikacija

Posle svih task-ova:
```bash
# Sintaksna provera svih skripti
bash -n .claude/scripts/guard-git.sh && echo "guard-git.sh OK"
bash -n .claude/scripts/verify-all.sh && echo "verify-all.sh OK"
bash -n .claude/scripts/setup.sh && echo "setup.sh OK"
bash -n .claude/scripts/session-start.sh && echo "session-start.sh OK"

# JSON validacija
python3 -c "import json; json.load(open('.claude/settings.json'))" && echo "settings.json OK"
```
