#!/bin/bash
# APD Test Hooks — verifies that hooks and scripts are correctly configured
# Run after /apd-init or manual setup

source "$(dirname "$0")/lib/resolve-project.sh"

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

echo "=== APD Hook Verification ==="
echo ""

# --- 1. Dependencies ---
echo "--- Dependencies ---"

if command -v jq &>/dev/null; then
    pass "jq is installed ($(jq --version 2>&1))"
else
    fail "jq is NOT installed — guard-git, guard-scope, guard-secrets will not work"
fi

if command -v git &>/dev/null; then
    pass "git is installed"
else
    fail "git is NOT installed"
fi

# --- 2. Directories ---
echo ""
echo "--- Structure ---"

if [ -d "$CLAUDE_DIR" ]; then
    pass ".claude/ directory exists"
else
    fail ".claude/ directory DOES NOT EXIST"
fi

for dir in scripts rules memory agents; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
        pass ".claude/$dir/ exists"
    else
        fail ".claude/$dir/ DOES NOT EXIST"
    fi
done

# --- 3. Scripts ---
echo ""
echo "--- Scripts ---"

PLUGIN_SCRIPTS=(
    guard-git.sh
    guard-scope.sh
    guard-bash-scope.sh
    guard-secrets.sh
    guard-lockfile.sh
    guard-permission-denied.sh
    pipeline-advance.sh
    pipeline-gate.sh
    pipeline-post-commit.sh
    rotate-session-log.sh
    session-start.sh
)

for script in "${PLUGIN_SCRIPTS[@]}"; do
    SCRIPT_PATH="$SCRIPT_DIR/$script"
    if [ ! -f "$SCRIPT_PATH" ]; then
        fail "$script DOES NOT EXIST (plugin: $SCRIPT_DIR)"
    elif [ ! -x "$SCRIPT_PATH" ]; then
        warn "$script exists but is NOT executable (chmod +x)"
    else
        pass "$script OK"
    fi
done

# Project script — verify-all.sh lives in the project
PROJECT_VERIFY="$CLAUDE_DIR/scripts/verify-all.sh"
if [ ! -f "$PROJECT_VERIFY" ]; then
    warn "verify-all.sh DOES NOT EXIST in the project (.claude/scripts/) — create with /apd-init"
elif [ ! -x "$PROJECT_VERIFY" ]; then
    warn "verify-all.sh exists but is NOT executable (chmod +x)"
else
    pass "verify-all.sh OK (project)"
fi

# --- 4. Settings.json ---
echo ""
echo "--- Settings ---"

SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
    fail "settings.json DOES NOT EXIST"
else
    if ! jq empty "$SETTINGS" 2>/dev/null; then
        fail "settings.json is NOT valid JSON"
    else
        pass "settings.json is valid JSON"

        # Check if hooks exist
        HOOK_COUNT=$(jq '[.hooks.PreToolUse[]?.hooks[]? // empty] | length' "$SETTINGS" 2>/dev/null || echo 0)
        if [ "$HOOK_COUNT" -gt 0 ]; then
            pass "PreToolUse hooks configured ($HOOK_COUNT)"
        else
            warn "No PreToolUse hooks in settings.json"
        fi

        SESSION_HOOK=$(jq '.hooks.SessionStart // empty' "$SETTINGS" 2>/dev/null)
        if [ -n "$SESSION_HOOK" ] && [ "$SESSION_HOOK" != "null" ]; then
            pass "SessionStart hook configured"
        else
            warn "SessionStart hook is not configured"
        fi

        POST_HOOK=$(jq '.hooks.PostToolUse // empty' "$SETTINGS" 2>/dev/null)
        if [ -n "$POST_HOOK" ] && [ "$POST_HOOK" != "null" ]; then
            pass "PostToolUse hook configured"
        else
            warn "PostToolUse hook is not configured — pipeline will not reset after commit"
        fi
    fi
fi

# --- 5. Placeholder check ---
echo ""
echo "--- Placeholders ---"

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
        warn "$BASENAME contains unreplaced placeholders ({{...}})"
        HAS_PLACEHOLDERS=true
    fi
done

if [ "$HAS_PLACEHOLDERS" = false ]; then
    pass "All placeholders are replaced"
fi

# --- 6. Agents ---
echo ""
echo "--- Agents ---"

AGENT_COUNT=$(find "$CLAUDE_DIR/agents" -name "*.md" ! -name "TEMPLATE.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 0 ]; then
    pass "$AGENT_COUNT agent(s) defined"
    for agent_file in "$CLAUDE_DIR/agents"/*.md; do
        [ "$(basename "$agent_file")" = "TEMPLATE.md" ] && continue
        AGENT_NAME=$(basename "$agent_file" .md)
        if grep -q '{{' "$agent_file" 2>/dev/null; then
            warn "Agent $AGENT_NAME has unreplaced placeholders"
        else
            pass "Agent $AGENT_NAME OK"
        fi
    done
else
    warn "No agents defined (only TEMPLATE.md)"
fi

# --- 7. Pipeline test ---
echo ""
echo "--- Pipeline ---"

PIPELINE_OUTPUT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" status 2>&1)
if [ $? -eq 0 ]; then
    pass "pipeline-advance.sh status works"
else
    fail "pipeline-advance.sh status ERROR: $PIPELINE_OUTPUT"
fi

# --- Result ---
echo ""
echo "=============================="
echo "  PASS: $PASS | FAIL: $FAIL | WARN: $WARN"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Fix FAIL items before using the APD pipeline."
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo ""
    echo "WARN items are recommendations — pipeline will work but may not be optimal."
fi

exit 0
