#!/bin/bash
# APD Test Hooks — verifikuje da su hook-ovi i skripte ispravno konfigurisani
# Pokreni posle /apd-init ili ručnog setup-a

source "$(dirname "$0")/lib/resolve-project.sh"

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
warn() { echo "  [WARN] $1"; ((WARN++)); }

echo "=== APD Hook Verifikacija ==="
echo ""

# --- 1. Zavisnosti ---
echo "--- Zavisnosti ---"

if command -v jq &>/dev/null; then
    pass "jq je instaliran ($(jq --version 2>&1))"
else
    fail "jq NIJE instaliran — guard-git, guard-scope, guard-secrets neće raditi"
fi

if command -v git &>/dev/null; then
    pass "git je instaliran"
else
    fail "git NIJE instaliran"
fi

# --- 2. Direktorijumi ---
echo ""
echo "--- Struktura ---"

if [ -d "$CLAUDE_DIR" ]; then
    pass ".claude/ direktorijum postoji"
else
    fail ".claude/ direktorijum NE POSTOJI"
fi

for dir in scripts rules memory agents; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
        pass ".claude/$dir/ postoji"
    else
        fail ".claude/$dir/ NE POSTOJI"
    fi
done

# --- 3. Skripte ---
echo ""
echo "--- Skripte ---"

REQUIRED_SCRIPTS=(
    guard-git.sh
    guard-scope.sh
    guard-bash-scope.sh
    guard-secrets.sh
    guard-lockfile.sh
    pipeline-advance.sh
    pipeline-gate.sh
    rotate-session-log.sh
    session-start.sh
    verify-all.sh
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    SCRIPT_PATH="$CLAUDE_DIR/scripts/$script"
    if [ ! -f "$SCRIPT_PATH" ]; then
        fail "$script NE POSTOJI"
    elif [ ! -x "$SCRIPT_PATH" ]; then
        warn "$script postoji ali NIJE executable (chmod +x)"
    else
        pass "$script OK"
    fi
done

# --- 4. Settings.json ---
echo ""
echo "--- Settings ---"

SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
    fail "settings.json NE POSTOJI"
else
    if ! jq empty "$SETTINGS" 2>/dev/null; then
        fail "settings.json NIJE validan JSON"
    else
        pass "settings.json je validan JSON"

        # Proveri da li postoje hook-ovi
        HOOK_COUNT=$(jq '[.hooks.PreToolUse[]?.hooks[]? // empty] | length' "$SETTINGS" 2>/dev/null || echo 0)
        if [ "$HOOK_COUNT" -gt 0 ]; then
            pass "PreToolUse hook-ovi konfigurisani ($HOOK_COUNT)"
        else
            warn "Nema PreToolUse hook-ova u settings.json"
        fi

        SESSION_HOOK=$(jq '.hooks.SessionStart // empty' "$SETTINGS" 2>/dev/null)
        if [ -n "$SESSION_HOOK" ] && [ "$SESSION_HOOK" != "null" ]; then
            pass "SessionStart hook konfigurisan"
        else
            warn "SessionStart hook nije konfigurisan"
        fi

        POST_HOOK=$(jq '.hooks.PostToolUse // empty' "$SETTINGS" 2>/dev/null)
        if [ -n "$POST_HOOK" ] && [ "$POST_HOOK" != "null" ]; then
            pass "PostToolUse hook konfigurisan"
        else
            warn "PostToolUse hook nije konfigurisan — pipeline neće resetovati posle commita"
        fi
    fi
fi

# --- 5. Placeholder provera ---
echo ""
echo "--- Placeholder-i ---"

PLACEHOLDER_FILES=(
    "$PROJECT_DIR/CLAUDE.md"
    "$CLAUDE_DIR/memory/MEMORY.md"
    "$CLAUDE_DIR/memory/status.md"
    "$CLAUDE_DIR/scripts/session-start.sh"
    "$SETTINGS"
)

HAS_PLACEHOLDERS=false
for file in "${PLACEHOLDER_FILES[@]}"; do
    if [ -f "$file" ] && grep -q '{{[A-Z_]*}}' "$file" 2>/dev/null; then
        BASENAME=$(basename "$file")
        warn "$BASENAME sadrži nezamenjene placeholder-e ({{...}})"
        HAS_PLACEHOLDERS=true
    fi
done

if [ "$HAS_PLACEHOLDERS" = false ]; then
    pass "Svi placeholder-i su zamenjeni"
fi

# --- 6. Agenti ---
echo ""
echo "--- Agenti ---"

AGENT_COUNT=$(find "$CLAUDE_DIR/agents" -name "*.md" ! -name "TEMPLATE.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 0 ]; then
    pass "$AGENT_COUNT agent(a) definisan(o)"
    for agent_file in "$CLAUDE_DIR/agents"/*.md; do
        [ "$(basename "$agent_file")" = "TEMPLATE.md" ] && continue
        AGENT_NAME=$(basename "$agent_file" .md)
        if grep -q '{{' "$agent_file" 2>/dev/null; then
            warn "Agent $AGENT_NAME ima nezamenjene placeholder-e"
        else
            pass "Agent $AGENT_NAME OK"
        fi
    done
else
    warn "Nema definisanih agenata (samo TEMPLATE.md)"
fi

# --- 7. Pipeline test ---
echo ""
echo "--- Pipeline ---"

PIPELINE_OUTPUT=$(bash "$CLAUDE_DIR/scripts/pipeline-advance.sh" status 2>&1)
if [ $? -eq 0 ]; then
    pass "pipeline-advance.sh status radi"
else
    fail "pipeline-advance.sh status GREŠKA: $PIPELINE_OUTPUT"
fi

# --- Rezultat ---
echo ""
echo "=============================="
echo "  PASS: $PASS | FAIL: $FAIL | WARN: $WARN"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Popravi FAIL stavke pre korišćenja APD pipeline-a."
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo ""
    echo "WARN stavke su preporuke — pipeline će raditi ali možda ne optimalno."
fi

exit 0
