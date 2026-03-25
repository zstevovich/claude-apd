# APD Audit Fix-ovi — Implementacioni Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zatvoriti sve KRITIČNE i VISOKE propuste otkrivene deep auditom APD template-a.

**Architecture:** Fix-ovi su podeljeni u 7 taskova po fajlu. Taskovi 1-3 su nezavisni (paralelni). Taskovi 4-5 su nezavisni (paralelni). Task 6 zavisi od 4 i 5. Task 7 je finalna verifikacija svih fix-ova.

**Tech Stack:** Bash (guard skripte), JSON (settings), Markdown (agent template)

**Spec:** `docs/superpowers/specs/2026-03-25-apd-deep-audit-design.md`

---

## File Map

| Akcija | Fajl | Opis |
|--------|------|------|
| Modify | `.claude/scripts/guard-git.sh` | K3, V1, V2, V3, K4 — force push, regex fix-ovi, reviewer podsetnik |
| Modify | `.claude/scripts/verify-all.sh` | K2 — failsafe upozorenje |
| Modify | `.claude/scripts/session-start.sh` | V4 — placeholder detekcija |
| Create | `.claude/scripts/guard-bash-scope.sh` | K1 — Bash file-write scope guard |
| Create | `.claude/scripts/guard-secrets.sh` | V5 — zaštita od čitanja osetljivih fajlova |
| Modify | `.claude/agents/TEMPLATE.md` | Registracija novih hook-ova |
| Modify | `.claude/agents/EXAMPLE-backend-builder.md` | Registracija novih hook-ova |

## Redosled izvršavanja

```
Task 1 (guard-git.sh)  ─┐
Task 2 (verify-all.sh)  ├── paralelno ──► Task 6 (TEMPLATE.md) ──► Task 7 (verifikacija)
Task 3 (session-start)  ─┤                      ▲
Task 4 (bash-scope)     ─┤                      │
Task 5 (secrets)        ─┘──────────────────────┘
```

---

### Task 1: guard-git.sh — Force push, regex fix-ovi, reviewer podsetnik

**Files:**
- Modify: `.claude/scripts/guard-git.sh:78-87` (force push blokada)
- Modify: `.claude/scripts/guard-git.sh:106` (destruktivni regex)
- Modify: `.claude/scripts/guard-git.sh:59-70` (reviewer podsetnik)

**Pokriva:** K3, V1, V2, V3, K4

- [ ] **Step 1: Potvrditi bug — force push prolazi**

```bash
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push --force origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
```

Očekivano: EXIT 0 (bug — prolazi)

- [ ] **Step 2: Potvrditi bug — branch -d lažni pozitiv**

```bash
echo '{"tool_input":{"command":"git branch -d feature/test"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
```

Očekivano: EXIT 2 + BLOKIRANO (bug — blokira safe delete)

- [ ] **Step 3: Potvrditi bug — checkout -- file prolazi**

```bash
echo '{"tool_input":{"command":"git checkout -- src/index.ts"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
```

Očekivano: EXIT 0 (bug — prolazi)

- [ ] **Step 4: Potvrditi bug — tag -d prolazi**

```bash
echo '{"tool_input":{"command":"git tag -d v1.0"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
```

Očekivano: EXIT 0 (bug — prolazi)

- [ ] **Step 5: Fix K3 — Dodati force push blokadu**

U `.claude/scripts/guard-git.sh`, **pre** postojeće git push sekcije (linija 78), dodati blokadu za force push. Celokupna push sekcija treba da izgleda:

```bash
# --- git push ---
if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
  # Blokiraj force push — čak i sa prefiksom
  if echo "$NORMALIZED_GIT" | grep -qE "git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))"; then
    echo "BLOKIRANO: git push --force nije dozvoljen. Koristi regularni push." >&2
    echo "Ako zaista treba force push, uradi to ručno van Claude-a." >&2
    exit 2
  fi
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    echo "Koristi: APD_ORCHESTRATOR_COMMIT=1 git push origin <branch>" >&2
    exit 2
  fi
fi
```

- [ ] **Step 6: Fix V1, V2, V3 — Popraviti destruktivni regex na liniji 106**

**VAŽNO:** Postojeći regex koristi `grep -qiE` (case-insensitive). Zato se `branch -D` ne može razlikovati od `branch -d` u istom regex-u. Rešenje: razbiti na dva grep poziva — jedan case-insensitive za većinu, jedan case-sensitive za branch.

Zameniti linije 105-108:

Staro:
```bash
# Blokiraj destruktivne git operacije
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+(--[[:space:]]+)?[.*]|restore[[:space:]]|branch[[:space:]]+-[Dd]|stash[[:space:]]+drop)"; then
  echo "BLOKIRANO: Destruktivna git operacija nije dozvoljena." >&2
  exit 2
fi
```

Novo:
```bash
# Blokiraj destruktivne git operacije (case-insensitive za većinu)
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+--[[:space:]]|restore[[:space:]]|stash[[:space:]]+drop|tag[[:space:]]+-d([[:space:]]|$))"; then
  echo "BLOKIRANO: Destruktivna git operacija nije dozvoljena." >&2
  exit 2
fi

# branch -D (force delete) — MORA biti case-sensitive jer -d (safe) treba da prođe
if echo "$NORMALIZED_GIT" | grep -qE "git branch[[:space:]]+-D([[:space:]]|$)"; then
  echo "BLOKIRANO: git branch -D (force delete) nije dozvoljen. Koristi -d za safe delete." >&2
  exit 2
fi
```

Promene:
- `checkout[[:space:]]+(--[[:space:]]+)?[.*]` → `checkout[[:space:]]+--[[:space:]]` — hvata `git checkout -- <bilo šta>` (discard), ali NE hvata `git checkout branch-name` (switch)
- `branch -D` izvučen u **zasebni case-sensitive grep** (`grep -qE` bez `-i`) — samo force delete (-D), dozvoljava safe delete (-d)
- Dodato: `tag[[:space:]]+-d([[:space:]]|$)` — brisanje tagova

- [ ] **Step 7: Fix K4 — Dodati reviewer podsetnik pre commit-a**

U `.claude/scripts/guard-git.sh`, u sekciji autorizovanog commita (posle verify-all.sh poziva, pre `exit 0` na liniji 70), dodati:

```bash
    # Podsetnik za pipeline disciplinu
    echo "⚠ PODSETNIK: Da li je Reviewer korak završen pre commit-a?" >&2
    echo "  Pipeline: Spec → Builder → Reviewer → Verifier → Commit" >&2
```

- [ ] **Step 8: Verifikovati sve fix-ove**

```bash
# K3: force push — sada treba da blokira
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push --force origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

# K3: --force-with-lease — sada treba da blokira
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push --force-with-lease origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

# K3: normalan push — i dalje treba da prođe
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0

# V1: branch -d (safe) — sada treba da prođe
echo '{"tool_input":{"command":"git branch -d feature/test"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0

# V1: branch -D (force) — i dalje treba da blokira
echo '{"tool_input":{"command":"git branch -D feature/test"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

# V2: checkout -- file — sada treba da blokira
echo '{"tool_input":{"command":"git checkout -- src/index.ts"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

# V2: checkout branch — i dalje treba da prođe
echo '{"tool_input":{"command":"git checkout feature/new"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0

# V3: tag -d — sada treba da blokira
echo '{"tool_input":{"command":"git tag -d v1.0"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

# V3: tag create — i dalje treba da prođe
echo '{"tool_input":{"command":"git tag v2.0"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0

# K4: autorizovani commit — treba da pokaže reviewer podsetnik
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m \"test\""}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0 + "PODSETNIK: Da li je Reviewer korak završen"

# Regresija: commit bez prefiksa — i dalje blokiran
echo '{"tool_input":{"command":"git commit -m \"test\""}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO
```

- [ ] **Step 9: Commit**

```bash
git add .claude/scripts/guard-git.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "fix: ojačaj guard-git — blokada force push, fix regex (branch -d, checkout --, tag -d), reviewer podsetnik"
```

---

### Task 2: verify-all.sh — Failsafe upozorenje

**Files:**
- Modify: `.claude/scripts/verify-all.sh`

**Pokriva:** K2

- [ ] **Step 1: Potvrditi bug — verify-all tiho prolazi bez provera**

```bash
bash .claude/scripts/verify-all.sh 2>&1; echo "EXIT: $?"
```

Očekivano: "Verifikacija prošla" + EXIT 0 (bug — nema upozorenja)

- [ ] **Step 2: Implementirati failsafe mehanizam**

Dodati `CHECKS_RAN=0` posle `ERRORS=()` deklaracije (linija 11).

U svakoj sekciji gde se otkomentarišu komande, dodati `CHECKS_RAN=1` pre if bloka (ovo su markeri za korisnike da znaju gde dodati flag).

Na kraj, pre finalnog echo-a, dodati failsafe proveru.

Celokupni fajl posle fix-a:

```bash
#!/bin/bash
# APD Verifier — pokreće se automatski pre svakog commit-a (poziva ga guard-git.sh)
#
# PRILAGODITI: Otkomentariši i podesi build/test komande za svoj projekat.
# Dok je sve zakomentarisano, verifikacija uvek prolazi — ovo je NAMERNO
# za nov projekat, ali MORA se konfigurisati pre produkcijskog rada.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

ERRORS=()
CHECKS_RAN=0

# Detektuj promenjene fajlove (staged za commit, ili sve ako nema prethodnog commit-a)
if git rev-parse HEAD &>/dev/null; then
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null)
else
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
fi

# ====================
# BACKEND VERIFIKACIJA
# ====================
# PRILAGODITI: putanje i komande za svoj backend
if echo "$CHANGED_FILES" | grep -qE '^src/|^tests/'; then
    echo "→ Backend promene detektovane..."
    # PRIMER (Node.js):  npm test
    # PRIMER (Python):   pytest tests/
    # PRIMER (Go):       go build ./... && go test ./...
    # PRIMER (.NET):     dotnet build && dotnet test
    #
    # CHECKS_RAN=1
    # if ! YOUR_BUILD_COMMAND 2>&1; then
    #     ERRORS+=("Backend build FAILED")
    # fi
    # if ! YOUR_TEST_COMMAND 2>&1; then
    #     ERRORS+=("Backend testovi FAILED")
    # fi
    echo "  (KONFIGURIŠI build/test komande u verify-all.sh)"
fi

# ====================
# FRONTEND VERIFIKACIJA
# ====================
# PRILAGODITI: putanje i komande za svoj frontend
if echo "$CHANGED_FILES" | grep -qE '^apps/|^frontend/|^web/'; then
    echo "→ Frontend promene detektovane..."
    # PRIMER (React/TS): cd apps/frontend && npx tsc --noEmit && npm test
    # PRIMER (Vue):      cd apps/frontend && npm run type-check && npm test
    #
    # CHECKS_RAN=1
    # if ! YOUR_TYPECHECK_COMMAND 2>&1; then
    #     ERRORS+=("Frontend type check FAILED")
    # fi
    echo "  (KONFIGURIŠI frontend check u verify-all.sh)"
fi

# ====================
# REZULTAT
# ====================
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "VERIFIKACIJA NIJE PROŠLA:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

# Failsafe: upozori ako nijedna provera nije konfigurisana
if [ "$CHECKS_RAN" -eq 0 ]; then
    echo "UPOZORENJE: verify-all.sh nema konfigurisanih provera!" >&2
    echo "  Verifier faza ne testira ništa — konfiguriši build/test komande." >&2
    echo "  Fajl: .claude/scripts/verify-all.sh" >&2
fi

echo "Verifikacija prošla"
exit 0
```

- [ ] **Step 3: Verifikovati failsafe**

```bash
bash .claude/scripts/verify-all.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0 + "UPOZORENJE: verify-all.sh nema konfigurisanih provera!"
```

- [ ] **Step 4: Commit**

```bash
git add .claude/scripts/verify-all.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "fix: verify-all.sh failsafe — upozorenje kad nema konfigurisanih provera"
```

---

### Task 3: session-start.sh — Placeholder detekcija

**Files:**
- Modify: `.claude/scripts/session-start.sh`

**Pokriva:** V4

- [ ] **Step 1: Implementirati placeholder detekciju**

Dodati proveru na početak session-start.sh, odmah posle `cd` komande (posle linije 6):

```bash
# Proveri da li su placeholder-i razrešeni u settings.json
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && grep -q '\[APSOLUTNA_PUTANJA\]' "$SETTINGS_FILE"; then
    echo ""
    echo "KRITIČNO: settings.json sadrži nerazrešene placeholder-e!" >&2
    echo "  Hook-ovi (guard-git, guard-scope, session-start) NE RADE." >&2
    echo "  Pokreni: bash .claude/scripts/setup.sh" >&2
    echo ""
fi
```

- [ ] **Step 2: Verifikovati detekciju**

```bash
# Trebalo bi da detektuje placeholder-e jer je ovo template repo
bash .claude/scripts/session-start.sh 2>&1 | head -10
# Očekivano: KRITIČNO: settings.json sadrži nerazrešene placeholder-e!
```

- [ ] **Step 3: Commit**

```bash
git add .claude/scripts/session-start.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "fix: session-start detektuje nerazrešene placeholder-e i upozorava"
```

---

### Task 4: guard-bash-scope.sh — Bash file-write scope guard

**Files:**
- Create: `.claude/scripts/guard-bash-scope.sh`

**Pokriva:** K1

**Prihvaćeni rizik (iz spec review-a):** Bash parsing za redirekcije je inherentno fragilno. Ovaj guard pokriva najčešće slučajeve (`>`, `>>`, `tee`), ali NE MOŽE pokriti: `eval`, `bash -c`, heredoc sa varijablama, `python -c "open()"`. Ovi vektori ostaju prihvaćeni rizik — kognitivni sloj (agent instrukcije) je primarna zaštita, ovaj guard je dodatni sloj.

- [ ] **Step 1: Kreirati guard-bash-scope.sh**

```bash
#!/bin/bash
# APD Bash Scope Guard — detektuje file-write operacije van dozvoljenog scope-a
# Korišćenje: bash guard-bash-scope.sh <dozvoljena_putanja_1> <dozvoljena_putanja_2> ...
# Primer:    bash guard-bash-scope.sh src/ tests/
#
# OGRANIČENJA: Hvata >, >>, tee redirekcije i cp/mv komande.
# NE HVATA: eval, bash -c, python -c, heredoc sa varijablama, &> (combined redirect).
# Ovi slučajevi ostaju pokriveni kognitivnim slojem (agent instrukcije).

ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-bash-scope.sh." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Funkcija: proveri da li je putanja u dozvoljenom scope-u
check_path() {
  local target="$1"

  # Ignoriši prazne putanje
  [ -z "$target" ] && return 0

  # Skini vodeći whitespace i navodnike
  target=$(echo "$target" | sed -E "s/^[[:space:]]*['\"]?//;s/['\"]?[[:space:]]*$//")

  # Konvertuj apsolutnu u relativnu
  if [[ "$target" == /* ]]; then
    local rel="${target#$PROJECT_DIR/}"
    # Ako je i dalje apsolutna — van projekta
    if [[ "$rel" == /* ]]; then
      echo "BLOKIRANO: Bash write operacija na $target — van projektnog direktorijuma." >&2
      echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
      exit 2
    fi
    target="$rel"
  fi

  # Proveri scope
  for allowed in "${ALLOWED_PATHS[@]}"; do
    allowed="${allowed%/}/"
    if [[ "$target" == "$allowed"* ]]; then
      return 0
    fi
  done

  echo "BLOKIRANO: Bash write operacija na $target — van dozvoljenog scope-a." >&2
  echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
  exit 2
}

# Detektuj redirekcije: > i >> (ali ne 2> ili &> koji su stderr/combined)
# Izvuci target fajl posle > ili >>
REDIRECT_TARGETS=$(echo "$COMMAND" | grep -oE '([^2&]|^)(>>?)[[:space:]]*[^ ;|&]+' | sed -E 's/^.*(>>?)[[:space:]]*//')

for target in $REDIRECT_TARGETS; do
  check_path "$target"
done

# Detektuj tee komande: tee [-a] <fajl>
TEE_TARGETS=$(echo "$COMMAND" | grep -oE 'tee[[:space:]]+(-a[[:space:]]+)?[^ ;|&]+' | sed -E 's/tee[[:space:]]+(-a[[:space:]]+)?//')

for target in $TEE_TARGETS; do
  check_path "$target"
done

# Detektuj cp/mv sa destinacijom
# cp source dest — destinacija je poslednji argument
# Ovo je pojednostavljeno — ne pokriva sve cp/mv varijante
CP_MV_MATCH=$(echo "$COMMAND" | grep -oE '(cp|mv)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^ ;|&]+[[:space:]]+[^ ;|&]+' | tail -1)
if [ -n "$CP_MV_MATCH" ]; then
  CP_MV_DEST=$(echo "$CP_MV_MATCH" | awk '{print $NF}')
  check_path "$CP_MV_DEST"
fi

exit 0
```

- [ ] **Step 2: Učiniti skriptu executable**

```bash
chmod +x .claude/scripts/guard-bash-scope.sh
```

- [ ] **Step 3: Verifikovati — echo redirect van scope-a**

```bash
echo '{"tool_input":{"command":"echo test > apps/web/hack.ts"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"echo test > src/index.ts"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0

echo '{"tool_input":{"command":"cat data | tee apps/output.log"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"echo test >> /etc/passwd"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO (van projekta)

echo '{"tool_input":{"command":"ls -la"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0 (nema redirekcije)
```

- [ ] **Step 4: Commit**

```bash
git add .claude/scripts/guard-bash-scope.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: guard-bash-scope — detektuje Bash file-write operacije van agent scope-a"
```

---

### Task 5: guard-secrets.sh — Zaštita od čitanja osetljivih fajlova

**Files:**
- Create: `.claude/scripts/guard-secrets.sh`

**Pokriva:** V5

- [ ] **Step 1: Kreirati guard-secrets.sh**

```bash
#!/bin/bash
# APD Secrets Guard — blokira čitanje osetljivih fajlova iz Bash komandi
# Registruje se na Bash matcher SAMO za agente (ne za orkestratora)

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-secrets.sh." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Osetljivi pattern-i — fajlovi koji ne smeju biti čitani od strane agenata
# Dodaj pattern-e specifične za svoj projekat po potrebi
SENSITIVE_PATTERNS='(\.(env|pem|key|p12|pfx|keystore|jks)(\..*)?$|/\.ssh/|credential|secret[s]?\.)'

# Detektuj read komande sa osetljivim fajlovima
# Pokriveno: cat, head, tail, less, more, bat, grep na osetljivim fajlovima
READ_COMMANDS='(cat|head|tail|less|more|bat|strings|xxd|hexdump|od)'

# Izvuci sve argumente iz read komandi
if echo "$COMMAND" | grep -qE "$READ_COMMANDS"; then
  # Proveri svaki argument read komande
  ARGS=$(echo "$COMMAND" | grep -oE "$READ_COMMANDS[[:space:]]+[^;|&]+" | sed -E "s/$READ_COMMANDS[[:space:]]+//" | tr ' ' '\n')
  for arg in $ARGS; do
    # Preskoči flag-ove (počinju sa -)
    [[ "$arg" == -* ]] && continue
    # Proveri da li matchuje osetljiv pattern
    if echo "$arg" | grep -qiE "$SENSITIVE_PATTERNS"; then
      echo "BLOKIRANO: Čitanje osetljivog fajla '$arg' nije dozvoljeno." >&2
      echo "  Agenti ne smeju pristupati credential/secret/key fajlovima." >&2
      echo "  Ako je ovo potrebno, zatraži od orkestratora." >&2
      exit 2
    fi
  done
fi

# Proveri i source/. komande (sa razmakom iza da ne hvata svaki '.' u komandi)
if echo "$COMMAND" | grep -qE '(source[[:space:]]|\.[[:space:]])' ; then
  SOURCE_FILES=$(echo "$COMMAND" | grep -oE '(source|\.)[[:space:]]+[^ ;|&]+' | awk '{print $NF}')
  for sf in $SOURCE_FILES; do
    if echo "$sf" | grep -qiE "$SENSITIVE_PATTERNS"; then
      echo "BLOKIRANO: Source-ovanje osetljivog fajla '$sf' nije dozvoljeno." >&2
      exit 2
    fi
  done
fi

exit 0
```

- [ ] **Step 2: Učiniti skriptu executable**

```bash
chmod +x .claude/scripts/guard-secrets.sh
```

- [ ] **Step 3: Verifikovati**

```bash
echo '{"tool_input":{"command":"cat .env"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"cat .env.production"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"head -5 credentials.json"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"cat ~/.ssh/id_rsa"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"cat server.key"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"cat src/index.ts"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0 (normalan fajl)

echo '{"tool_input":{"command":"source .env"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 2 + BLOKIRANO

echo '{"tool_input":{"command":"npm test"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
# Očekivano: EXIT 0 (nema read komande)
```

- [ ] **Step 4: Commit**

```bash
git add .claude/scripts/guard-secrets.sh
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: guard-secrets — blokira agente od čitanja osetljivih fajlova"
```

---

### Task 6: Agent TEMPLATE.md i EXAMPLE — Registracija novih hook-ova

**Files:**
- Modify: `.claude/agents/TEMPLATE.md:21-32`
- Modify: `.claude/agents/EXAMPLE-backend-builder.md:8-19`

**Pokriva:** K1, V5 integracija

**Zavisi od:** Task 4, Task 5

- [ ] **Step 1: Ažurirati TEMPLATE.md — dodati Bash hook-ove**

U `.claude/agents/TEMPLATE.md`, proširiti hooks sekciju. Trenutni Bash matcher ima samo guard-git. Dodati guard-bash-scope i guard-secrets.

Nova hooks sekcija (zamenjuje linije 21-32 u frontmatter-u):

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
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-bash-scope.sh [DOZVOLJENE_PUTANJE]"
          timeout: 5
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-secrets.sh"
          timeout: 5
```

- [ ] **Step 2: Ažurirati EXAMPLE-backend-builder.md**

U `.claude/agents/EXAMPLE-backend-builder.md`, dodati iste Bash hook-ove. Nova hooks sekcija:

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
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-bash-scope.sh src/ tests/"
          timeout: 5
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-secrets.sh"
          timeout: 5
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/TEMPLATE.md .claude/agents/EXAMPLE-backend-builder.md
APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: registruj guard-bash-scope i guard-secrets hook-ove u agent template"
```

---

### Task 7: Finalna adversarial verifikacija

**Files:** Nema — samo testovi

**Zavisi od:** Task 1-6

- [ ] **Step 1: Pokrenuti kompletnu test suitu — guard-git.sh**

```bash
echo "=== guard-git.sh — kompletna verifikacija ==="

echo "--- Commit bez prefiksa (BLOK) ---"
echo '{"tool_input":{"command":"git commit -m \"test\""}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- Commit sa prefiksom (OK + reviewer podsetnik) ---"
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m \"test\""}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- Push bez prefiksa (BLOK) ---"
echo '{"tool_input":{"command":"git push origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- Force push SA prefiksom (BLOK) ---"
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push --force origin main"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- git add . (BLOK) ---"
echo '{"tool_input":{"command":"git add ."}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- --no-verify (BLOK) ---"
echo '{"tool_input":{"command":"git commit --no-verify -m \"test\""}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- reset --hard (BLOK) ---"
echo '{"tool_input":{"command":"git reset --hard HEAD"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- branch -d safe delete (OK) ---"
echo '{"tool_input":{"command":"git branch -d feature/test"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- branch -D force delete (BLOK) ---"
echo '{"tool_input":{"command":"git branch -D feature/test"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- checkout -- file (BLOK) ---"
echo '{"tool_input":{"command":"git checkout -- src/index.ts"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- checkout branch (OK) ---"
echo '{"tool_input":{"command":"git checkout feature/new"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- tag -d (BLOK) ---"
echo '{"tool_input":{"command":"git tag -d v1.0"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"

echo "--- tag create (OK) ---"
echo '{"tool_input":{"command":"git tag v2.0"}}' | bash .claude/scripts/guard-git.sh 2>&1; echo "EXIT: $?"
```

- [ ] **Step 2: Pokrenuti test suitu — guard-bash-scope.sh**

```bash
echo "=== guard-bash-scope.sh — verifikacija ==="

echo "--- echo > van scope-a (BLOK) ---"
echo '{"tool_input":{"command":"echo test > apps/web/hack.ts"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"

echo "--- echo > u scope-u (OK) ---"
echo '{"tool_input":{"command":"echo test > src/index.ts"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"

echo "--- tee van scope-a (BLOK) ---"
echo '{"tool_input":{"command":"cat data | tee apps/output.log"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"

echo "--- ls -la bez redirekcije (OK) ---"
echo '{"tool_input":{"command":"ls -la"}}' | bash .claude/scripts/guard-bash-scope.sh src/ tests/ 2>&1; echo "EXIT: $?"
```

- [ ] **Step 3: Pokrenuti test suitu — guard-secrets.sh**

```bash
echo "=== guard-secrets.sh — verifikacija ==="

echo "--- cat .env (BLOK) ---"
echo '{"tool_input":{"command":"cat .env"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"

echo "--- cat credentials.json (BLOK) ---"
echo '{"tool_input":{"command":"head -5 credentials.json"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"

echo "--- cat src/index.ts (OK) ---"
echo '{"tool_input":{"command":"cat src/index.ts"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"

echo "--- npm test (OK) ---"
echo '{"tool_input":{"command":"npm test"}}' | bash .claude/scripts/guard-secrets.sh 2>&1; echo "EXIT: $?"
```

- [ ] **Step 4: Pokrenuti test suitu — verify-all.sh failsafe**

```bash
echo "=== verify-all.sh — failsafe verifikacija ==="
bash .claude/scripts/verify-all.sh 2>&1
echo "EXIT: $?"
# Očekivano: UPOZORENJE + EXIT 0
```

- [ ] **Step 5: Pokrenuti test suitu — session-start.sh placeholder detekcija**

```bash
echo "=== session-start.sh — placeholder detekcija ==="
bash .claude/scripts/session-start.sh 2>&1 | head -10
# Očekivano: KRITIČNO: settings.json sadrži nerazrešene placeholder-e!
```

- [ ] **Step 6: Zapisati rezultate verifikacije**

Ako svi testovi prolaze, zadatak je kompletiran. Ako neki test pada, vratiti se na odgovarajući Task i fixovati.

---

## Finalna verifikacija pre merge-a

```bash
# Svi guard-ovi rade
bash .claude/scripts/guard-git.sh < /dev/null 2>&1  # EXIT 0 (prazan input)
bash .claude/scripts/guard-scope.sh src/ < /dev/null 2>&1  # EXIT 0
bash .claude/scripts/guard-bash-scope.sh src/ < /dev/null 2>&1  # EXIT 0
bash .claude/scripts/guard-secrets.sh < /dev/null 2>&1  # EXIT 0

# Verify-all failsafe
bash .claude/scripts/verify-all.sh 2>&1 | grep -c "UPOZORENJE"  # 1

# Session-start placeholder detekcija
bash .claude/scripts/session-start.sh 2>&1 | grep -c "KRITIČNO"  # 1
```
