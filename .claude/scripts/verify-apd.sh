#!/bin/bash
# APD Verify — kompletna funkcionalna verifikacija APD instalacije
# Pokreni posle /apd-init ili ručnog setup-a da potvrdiš da SVE radi
#
# Razlika od test-hooks.sh:
#   test-hooks.sh  → statička provera (fajlovi, JSON, placeholder-i)
#   verify-apd.sh  → funkcionalni testovi (guard-ovi blokiraju, pipeline radi end-to-end)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$PROJECT_DIR/.claude"

PASS=0
FAIL=0
WARN=0
SECTION=""

# Summary podaci — prikupljaju se tokom provera
SUM_PROJECT=""
SUM_AGENTS=""
SUM_AGENT_NAMES=""
SUM_SCRIPTS_OK=0
SUM_SCRIPTS_TOTAL=0
SUM_GUARDS=""
SUM_PIPELINE="nepoznat"
SUM_VERIFY_ALL="nije konfigurisan"
SUM_MEMORY=0
SUM_GITIGNORE=""
SUM_ATTRIBUTION=""

pass() { echo "  ✓ $1"; ((PASS++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }
warn() { echo "  ! $1"; ((WARN++)); }
section() { echo ""; echo "[$1]"; SECTION="$1"; }

echo "╔══════════════════════════════════════╗"
echo "║   APD — Kompletna verifikacija       ║"
echo "╚══════════════════════════════════════╝"

# ============================================================
# 1. PREDUSLOV — statička provera
# ============================================================
section "1. Preduslovi"

# jq
if command -v jq &>/dev/null; then
    pass "jq instaliran"
else
    fail "jq NIJE instaliran — guard skripte neće raditi"
    echo ""
    echo "  Instaliraj: brew install jq (macOS) / apt install jq (Linux)"
    echo "  Prekidam — bez jq nema smisla nastaviti."
    exit 1
fi

# git
if command -v git &>/dev/null; then
    pass "git instaliran"
else
    fail "git NIJE instaliran"
    exit 1
fi

# git repo
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    pass "Git repozitorijum inicijalizovan"
else
    fail "Direktorijum nije git repo — inicijalizuj sa: git init"
fi

# ============================================================
# 2. STRUKTURA — fajlovi i direktorijumi
# ============================================================
section "2. Struktura"

for dir in scripts rules memory agents; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
        pass ".claude/$dir/"
    else
        fail ".claude/$dir/ NE POSTOJI"
    fi
done

# CLAUDE.md
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    pass "CLAUDE.md postoji"
    # Izvuci ime projekta (prvi heading)
    SUM_PROJECT=$(head -5 "$PROJECT_DIR/CLAUDE.md" | grep '^# ' | head -1 | sed 's/^# //')
    [ -z "$SUM_PROJECT" ] && SUM_PROJECT="(nepoznat)"
else
    fail "CLAUDE.md NE POSTOJI — kreiran je pri /apd-init"
    SUM_PROJECT="(nema CLAUDE.md)"
fi

# Skripte — postoje i executable
REQUIRED_SCRIPTS=(
    guard-git.sh guard-scope.sh guard-bash-scope.sh
    guard-secrets.sh guard-lockfile.sh
    pipeline-advance.sh pipeline-gate.sh
    rotate-session-log.sh session-start.sh verify-all.sh
)

SCRIPTS_OK=true
SUM_SCRIPTS_TOTAL=${#REQUIRED_SCRIPTS[@]}
SUM_SCRIPTS_OK=0
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [ ! -f "$CLAUDE_DIR/scripts/$script" ]; then
        fail "$script NE POSTOJI"
        SCRIPTS_OK=false
    elif [ ! -x "$CLAUDE_DIR/scripts/$script" ]; then
        fail "$script NIJE executable — pokreni: chmod +x .claude/scripts/*.sh"
        SCRIPTS_OK=false
    else
        ((SUM_SCRIPTS_OK++))
    fi
done
if [ "$SCRIPTS_OK" = true ]; then
    pass "Svih ${#REQUIRED_SCRIPTS[@]} skripti postoji i executable"
fi

# Memory fajlovi
for file in MEMORY.md status.md session-log.md pipeline-skip-log.md; do
    if [ -f "$CLAUDE_DIR/memory/$file" ]; then
        pass "memory/$file"
        ((SUM_MEMORY++))
    else
        fail "memory/$file NE POSTOJI"
    fi
done

# ============================================================
# 3. SETTINGS.JSON — hook konfiguracija
# ============================================================
section "3. Settings"

SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
    fail "settings.json NE POSTOJI"
else
    if ! jq empty "$SETTINGS" 2>/dev/null; then
        fail "settings.json NIJE validan JSON"
    else
        pass "settings.json validan JSON"

        # SessionStart hook
        if jq -e '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS" &>/dev/null; then
            CMD=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS")
            if echo "$CMD" | grep -q 'session-start.sh'; then
                pass "SessionStart → session-start.sh"
            else
                warn "SessionStart hook postoji ali ne poziva session-start.sh"
            fi
        else
            warn "SessionStart hook nije konfigurisan"
        fi

        # PreToolUse Bash → guard-git
        if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$SETTINGS" 2>/dev/null | grep -q 'guard-git'; then
            pass "PreToolUse(Bash) → guard-git.sh"
        else
            fail "guard-git.sh NIJE registrovan kao PreToolUse hook za Bash"
        fi

        # PreToolUse Write|Edit → guard-lockfile
        if jq -e '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[].command' "$SETTINGS" 2>/dev/null | grep -q 'guard-lockfile'; then
            pass "PreToolUse(Write|Edit) → guard-lockfile.sh"
        else
            warn "guard-lockfile.sh nije registrovan kao PreToolUse hook za Write|Edit"
        fi

        # Attribution prazna
        COMMIT_ATTR=$(jq -r '.attribution.commit // "N/A"' "$SETTINGS" 2>/dev/null)
        PR_ATTR=$(jq -r '.attribution.pr // "N/A"' "$SETTINGS" 2>/dev/null)
        if [ "$COMMIT_ATTR" = "" ] && [ "$PR_ATTR" = "" ]; then
            pass "Attribution prazna (bez AI potpisa)"
            SUM_ATTRIBUTION="prazna (OK)"
        elif [ "$COMMIT_ATTR" = "N/A" ]; then
            warn "Attribution sekcija ne postoji u settings.json"
            SUM_ATTRIBUTION="nije definisana"
        else
            warn "Attribution nije prazna — AI potpis može završiti u commitima"
            SUM_ATTRIBUTION="AKTIVNA (proveri!)"
        fi
    fi
fi

# ============================================================
# 4. PLACEHOLDER PROVERA — ništa ne sme ostati {{...}}
# ============================================================
section "4. Placeholder-i"

PLACEHOLDER_FILES=(
    "$PROJECT_DIR/CLAUDE.md"
    "$CLAUDE_DIR/memory/MEMORY.md"
    "$CLAUDE_DIR/memory/status.md"
    "$CLAUDE_DIR/scripts/session-start.sh"
    "$SETTINGS"
)

ALL_CLEAN=true
for file in "${PLACEHOLDER_FILES[@]}"; do
    if [ -f "$file" ] && grep -q '{{[A-Z_]*}}' "$file" 2>/dev/null; then
        BASENAME=$(basename "$file")
        PLACEHOLDERS=$(grep -oE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null | sort -u | tr '\n' ' ')
        fail "$BASENAME → $PLACEHOLDERS"
        ALL_CLEAN=false
    fi
done

if [ "$ALL_CLEAN" = true ]; then
    pass "Svi placeholder-i zamenjeni"
fi

# ============================================================
# 5. CLAUDE.md — obavezne sekcije
# ============================================================
section "5. CLAUDE.md sadržaj"

if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    REQUIRED_SECTIONS=("## Stack" "## APD" "### Pipeline" "### Guardrail" "### Human gate" "### Session memory" "## Anti-patterns")
    for sec in "${REQUIRED_SECTIONS[@]}"; do
        if grep -q "$sec" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
            pass "Sekcija: $sec"
        else
            fail "Nedostaje sekcija: $sec"
        fi
    done

    # Memorija reference
    if grep -q '@.claude/memory/' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
        pass "Memory reference (@.claude/memory/)"
    else
        warn "CLAUDE.md ne referencira memory fajlove"
    fi
fi

# ============================================================
# 6. AGENTI — frontmatter validacija
# ============================================================
section "6. Agenti"

AGENT_COUNT=0
for agent_file in "$CLAUDE_DIR/agents"/*.md; do
    [ "$(basename "$agent_file")" = "TEMPLATE.md" ] && continue
    [ ! -f "$agent_file" ] && continue
    AGENT_NAME=$(basename "$agent_file" .md)
    ((AGENT_COUNT++))

    # Placeholder check
    if grep -q '{{' "$agent_file" 2>/dev/null; then
        fail "Agent $AGENT_NAME — nezamenjeni placeholder-i"
        continue
    fi

    # Frontmatter postoji
    if ! head -1 "$agent_file" | grep -q '^---'; then
        fail "Agent $AGENT_NAME — nema frontmatter (---)"
        continue
    fi

    # model definisan
    if grep -q '^model:' "$agent_file" 2>/dev/null; then
        MODEL=$(grep '^model:' "$agent_file" | head -1 | awk '{print $2}')
        pass "Agent $AGENT_NAME — model: $MODEL"
    else
        fail "Agent $AGENT_NAME — model NIJE definisan"
    fi

    # guard-scope hook
    if grep -q 'guard-scope.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-scope.sh registrovan"
    else
        warn "Agent $AGENT_NAME — guard-scope.sh NIJE registrovan (agent nema file scope zaštitu)"
    fi

    # guard-git hook
    if grep -q 'guard-git.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-git.sh registrovan"
    else
        fail "Agent $AGENT_NAME — guard-git.sh NIJE registrovan (agent može commitovati!)"
    fi

    # guard-secrets hook
    if grep -q 'guard-secrets.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-secrets.sh registrovan"
    else
        warn "Agent $AGENT_NAME — guard-secrets.sh NIJE registrovan"
    fi

    # ZABRANJENO sekcija
    if grep -qi 'ZABRANJENO\|NIKADA.*commit' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — commit zabrana dokumentovana"
    else
        warn "Agent $AGENT_NAME — nema eksplicitnu zabranu commitovanja"
    fi
done

if [ "$AGENT_COUNT" -eq 0 ]; then
    warn "Nema definisanih agenata (samo TEMPLATE.md)"
    SUM_AGENTS="0"
    SUM_AGENT_NAMES="nema"
else
    pass "$AGENT_COUNT agent(a) ukupno"
    SUM_AGENTS="$AGENT_COUNT"
    SUM_AGENT_NAMES=$(find "$CLAUDE_DIR/agents" -name "*.md" ! -name "TEMPLATE.md" -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
fi

# ============================================================
# 7. GUARD FUNKCIONALNI TESTOVI
# ============================================================
section "7. Guard testovi (funkcionalni)"

# Prikupljaj guard summary
GUARD_LIST=()

# guard-git: blokira git commit bez prefiksa
RESULT=$(echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blokira: git commit bez APD_ORCHESTRATOR_COMMIT=1"
    GUARD_LIST+=("git")
else
    fail "guard-git NE BLOKIRA git commit bez prefiksa (exit: $EXIT_CODE)"
fi

# guard-git: dozvoljava sa prefiksom (ali pipeline gate blokira — to je OK)
RESULT=$(echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m test"}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
# exit 0 = dozvoljen, exit 2 = pipeline gate blokirao (oba su validni odgovori)
if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git prepoznaje APD_ORCHESTRATOR_COMMIT=1 prefiks"
else
    fail "guard-git ne prepoznaje APD_ORCHESTRATOR_COMMIT=1 prefiks (exit: $EXIT_CODE)"
fi

# guard-git: blokira git add .
RESULT=$(echo '{"tool_input":{"command":"git add ."}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blokira: git add ."
else
    fail "guard-git NE BLOKIRA git add . (exit: $EXIT_CODE)"
fi

# guard-git: blokira --no-verify
RESULT=$(echo '{"tool_input":{"command":"git commit --no-verify -m test"}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blokira: --no-verify"
else
    fail "guard-git NE BLOKIRA --no-verify (exit: $EXIT_CODE)"
fi

# guard-git: blokira force push
RESULT=$(echo '{"tool_input":{"command":"git push --force"}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blokira: git push --force"
else
    fail "guard-git NE BLOKIRA git push --force (exit: $EXIT_CODE)"
fi

# guard-git: blokira destructive ops
RESULT=$(echo '{"tool_input":{"command":"git reset --hard HEAD"}}' | bash "$CLAUDE_DIR/scripts/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blokira: git reset --hard"
else
    fail "guard-git NE BLOKIRA git reset --hard (exit: $EXIT_CODE)"
fi

# guard-scope: blokira van scope-a
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/outside/file.ts\"}}" | bash "$CLAUDE_DIR/scripts/guard-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-scope blokira: fajl van dozvoljenog scope-a"
    GUARD_LIST+=("scope")
else
    fail "guard-scope NE BLOKIRA fajl van scope-a (exit: $EXIT_CODE)"
fi

# guard-scope: dozvoljava unutar scope-a
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/test.ts\"}}" | bash "$CLAUDE_DIR/scripts/guard-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    pass "guard-scope dozvoljava: fajl unutar scope-a"
else
    fail "guard-scope BLOKIRA fajl koji JE unutar scope-a (exit: $EXIT_CODE)"
fi

# guard-bash-scope: blokira write van scope-a
RESULT=$(echo '{"tool_input":{"command":"echo test > /tmp/outside.txt"}}' | bash "$CLAUDE_DIR/scripts/guard-bash-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-bash-scope blokira: bash write van scope-a"
    GUARD_LIST+=("bash-scope")
else
    fail "guard-bash-scope NE BLOKIRA bash write van scope-a (exit: $EXIT_CODE)"
fi

# guard-bash-scope: blokira runtime write (node -e writeFileSync)
RESULT=$(echo '{"tool_input":{"command":"node -e \"require('"'"'fs'"'"').writeFileSync('"'"'/tmp/x.js'"'"', '"'"'data'"'"')\""}}' | bash "$CLAUDE_DIR/scripts/guard-bash-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-bash-scope blokira: runtime write (node)"
else
    fail "guard-bash-scope NE BLOKIRA runtime write node -e (exit: $EXIT_CODE)"
fi

# guard-lockfile: blokira lock fajl
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/package-lock.json\"}}" | bash "$CLAUDE_DIR/scripts/guard-lockfile.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-lockfile blokira: package-lock.json"
    GUARD_LIST+=("lockfile")
else
    fail "guard-lockfile NE BLOKIRA package-lock.json (exit: $EXIT_CODE)"
fi

# guard-secrets: blokira osetljiv fajl
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/.env.production\"}}" | bash "$CLAUDE_DIR/scripts/guard-secrets.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-secrets blokira: .env.production"
    GUARD_LIST+=("secrets")
else
    fail "guard-secrets NE BLOKIRA .env.production (exit: $EXIT_CODE)"
fi

SUM_GUARDS=$(printf '%s, ' "${GUARD_LIST[@]}" | sed 's/, $//')

# ============================================================
# 8. PIPELINE END-TO-END TEST
# ============================================================
section "8. Pipeline end-to-end test"

# Sačuvaj trenutno stanje pipeline-a
PIPELINE_DIR="$CLAUDE_DIR/.pipeline"
HAD_EXISTING_PIPELINE=false
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    HAD_EXISTING_PIPELINE=true
    mkdir -p /tmp/apd-verify-backup
    cp "$PIPELINE_DIR"/*.done /tmp/apd-verify-backup/ 2>/dev/null
fi

# Čist start
bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" reset >/dev/null 2>&1

# pipeline-gate: mora blokirati kad nema koraka
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blokira: prazan pipeline"
else
    fail "pipeline-gate NE BLOKIRA prazan pipeline (exit: $EXIT_CODE)"
fi

# Spec
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" spec "APD-VERIFY-TEST" 2>&1)
if echo "$RESULT" | grep -q "Pipeline započet"; then
    pass "pipeline-advance: spec"
else
    fail "pipeline-advance spec GREŠKA: $RESULT"
fi

# Builder pre spec-a (treba proći jer spec postoji)
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" builder 2>&1)
if echo "$RESULT" | grep -q "builder završen"; then
    pass "pipeline-advance: builder"
else
    fail "pipeline-advance builder GREŠKA: $RESULT"
fi

# pipeline-gate: mora blokirati (fale reviewer + verifier)
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blokira: fale reviewer + verifier"
else
    fail "pipeline-gate NE BLOKIRA kad fale koraci (exit: $EXIT_CODE)"
fi

# Reviewer
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" reviewer 2>&1)
if echo "$RESULT" | grep -q "reviewer završen"; then
    pass "pipeline-advance: reviewer"
else
    fail "pipeline-advance reviewer GREŠKA: $RESULT"
fi

# Verifier
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" verifier 2>&1)
if echo "$RESULT" | grep -q "COMMIT DOZVOLJEN"; then
    pass "pipeline-advance: verifier → COMMIT DOZVOLJEN"
else
    fail "pipeline-advance verifier GREŠKA: $RESULT"
fi

# pipeline-gate: mora propustiti (sva 4 koraka završena)
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    pass "pipeline-gate propušta: sva 4 koraka završena"
else
    fail "pipeline-gate NE PROPUŠTA kad su svi koraci gotovi (exit: $EXIT_CODE)"
fi

# Rollback test
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" rollback 2>&1)
if echo "$RESULT" | grep -q "Rollback: verifier uklonjen"; then
    pass "pipeline-advance: rollback (verifier → reviewer)"
else
    fail "pipeline-advance rollback GREŠKA: $RESULT"
fi

# pipeline-gate: mora blokirati posle rollback-a
RESULT=$(bash "$CLAUDE_DIR/scripts/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blokira posle rollback-a"
    SUM_PIPELINE="funkcionalan (E2E + rollback)"
else
    fail "pipeline-gate NE BLOKIRA posle rollback-a (exit: $EXIT_CODE)"
    SUM_PIPELINE="ima grešaka"
fi

# Čišćenje
bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" reset >/dev/null 2>&1

# Ukloni test entry iz session-log-a
if [ -f "$CLAUDE_DIR/memory/session-log.md" ]; then
    # Ukloni poslednji entry ako je APD-VERIFY-TEST
    if grep -q "APD-VERIFY-TEST" "$CLAUDE_DIR/memory/session-log.md" 2>/dev/null; then
        # Nađi liniju gde počinje test entry i obriši do kraja
        FIRST_TEST_LINE=$(grep -n "APD-VERIFY-TEST" "$CLAUDE_DIR/memory/session-log.md" | head -1 | cut -d: -f1)
        if [ -n "$FIRST_TEST_LINE" ]; then
            # Entry počinje 1 liniju pre (## [datum]) i dodajemo 1 za prazan red iznad
            START=$((FIRST_TEST_LINE - 2))
            [ "$START" -lt 1 ] && START=1
            head -n "$START" "$CLAUDE_DIR/memory/session-log.md" > "$CLAUDE_DIR/memory/session-log.md.tmp"
            mv "$CLAUDE_DIR/memory/session-log.md.tmp" "$CLAUDE_DIR/memory/session-log.md"
        fi
    fi
fi

# Vrati prethodno stanje pipeline-a
if [ "$HAD_EXISTING_PIPELINE" = true ]; then
    mkdir -p "$PIPELINE_DIR"
    cp /tmp/apd-verify-backup/*.done "$PIPELINE_DIR/" 2>/dev/null
    rm -rf /tmp/apd-verify-backup
fi

# ============================================================
# 9. VERIFY-ALL.SH — konfigurisan ili ne
# ============================================================
section "9. verify-all.sh konfiguracija"

if [ -f "$CLAUDE_DIR/scripts/verify-all.sh" ]; then
    # Proveri da li je bar jedna sekcija otkomentarisana
    UNCOMMENTED_CHECKS=$(grep -cE '^\s*(if.*CHANGED_FILES|dotnet |npm |python |go |php )' "$CLAUDE_DIR/scripts/verify-all.sh" 2>/dev/null || echo 0)
    if [ "$UNCOMMENTED_CHECKS" -gt 0 ]; then
        pass "verify-all.sh ima aktivne build/test provere ($UNCOMMENTED_CHECKS)"
        SUM_VERIFY_ALL="aktivan ($UNCOMMENTED_CHECKS provera)"
    else
        warn "verify-all.sh je potpuno zakomentarisan — verifikacija nije aktivna"
        echo "       Otkomentiraj relevantne sekcije za svoj stack."
        SUM_VERIFY_ALL="zakomentarisan"
    fi
fi

# ============================================================
# 10. .GITIGNORE — zaštita
# ============================================================
section "10. Gitignore"

GIT_IGNORE_ITEMS=()
if [ -f "$PROJECT_DIR/.gitignore" ]; then
    if grep -q '\.claude/settings\.local\.json' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        pass ".gitignore: settings.local.json"
        GIT_IGNORE_ITEMS+=("local.json")
    else
        warn ".gitignore ne sadrži .claude/settings.local.json"
    fi

    if grep -q '\.claude/\.pipeline' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        pass ".gitignore: .claude/.pipeline/"
        GIT_IGNORE_ITEMS+=(".pipeline/")
    else
        fail ".gitignore ne sadrži .claude/.pipeline/ — pipeline flags mogu završiti u repo-u"
    fi
else
    fail ".gitignore NE POSTOJI"
fi
SUM_GITIGNORE=$(printf '%s, ' "${GIT_IGNORE_ITEMS[@]}" | sed 's/, $//')
[ -z "$SUM_GITIGNORE" ] && SUM_GITIGNORE="nepotpun"

# ============================================================
# SUMMARY TABELA
# ============================================================

# Skrati agent imena ako je lista predugačka
AGENT_DISPLAY="$SUM_AGENT_NAMES"
if [ ${#AGENT_DISPLAY} -gt 40 ]; then
    AGENT_DISPLAY="${AGENT_DISPLAY:0:37}..."
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║              APD — Setup Summary                     ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  %-15s │ %-36s ║\n" "Projekat"       "$SUM_PROJECT"
printf "║  %-15s │ %-36s ║\n" "Agenti"         "$SUM_AGENTS ($AGENT_DISPLAY)"
printf "║  %-15s │ %-36s ║\n" "Skripte"        "$SUM_SCRIPTS_OK/$SUM_SCRIPTS_TOTAL"
printf "║  %-15s │ %-36s ║\n" "Guard-ovi"      "$SUM_GUARDS"
printf "║  %-15s │ %-36s ║\n" "Pipeline"       "$SUM_PIPELINE"
printf "║  %-15s │ %-36s ║\n" "verify-all.sh"  "$SUM_VERIFY_ALL"
printf "║  %-15s │ %-36s ║\n" "Memory fajlovi" "$SUM_MEMORY/4"
printf "║  %-15s │ %-36s ║\n" "Gitignore"      "$SUM_GITIGNORE"
printf "║  %-15s │ %-36s ║\n" "Attribution"    "$SUM_ATTRIBUTION"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  PASS: %-3s │ FAIL: %-3s │ WARN: %-3s               ║\n" "$PASS" "$FAIL" "$WARN"
echo "╚══════════════════════════════════════════════════════╝"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "APD NIJE SPREMAN — popravi FAIL stavke."
    echo ""
    echo "Čest uzrok: placeholder-i nisu zamenjeni."
    echo "Pokreni /apd-init ili ručno zameni {{...}} vrednosti."
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo ""
    echo "APD JE FUNKCIONALAN — WARN stavke su preporuke za poboljšanje."
fi

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo ""
    echo "APD JE POTPUNO KONFIGURISAN. Spreman za rad."
fi

exit 0
