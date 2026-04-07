#!/bin/bash
# APD Verify — complete functional verification of APD installation
# Run after /apd-init or manual setup to confirm everything works
#
# Difference from test-hooks.sh:
#   test-hooks.sh  -> static check (files, JSON, placeholders)
#   verify-apd.sh  -> functional tests (guards block, pipeline works end-to-end)

source "$(dirname "$0")/lib/resolve-project.sh"

PASS=0
FAIL=0
WARN=0
SECTION=""

# Summary data — collected during checks
SUM_PROJECT=""
SUM_AGENTS=""
SUM_AGENT_NAMES=""
SUM_SCRIPTS_OK=0
SUM_SCRIPTS_TOTAL=0
SUM_GUARDS=""
SUM_PIPELINE="unknown"
SUM_VERIFY_ALL="not configured"
SUM_MEMORY=0
SUM_GITIGNORE=""
SUM_ATTRIBUTION=""

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ! $1"; WARN=$((WARN + 1)); }
section() { echo ""; echo "[$1]"; SECTION="$1"; }

echo "╔══════════════════════════════════════╗"
echo "║   APD — Complete Verification        ║"
echo "╚══════════════════════════════════════╝"

# ============================================================
# 1. PREREQUISITES — static check
# ============================================================
section "1. Prerequisites"

# Plugin installation
if [ -d "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/guard-git.sh" ]; then
    pass "APD plugin installed ($SCRIPT_DIR)"
else
    fail "APD plugin is NOT installed — SCRIPT_DIR=$SCRIPT_DIR does not contain guard-git.sh"
    echo "  Aborting — plugin must be installed."
    exit 1
fi

# .apd-config
APD_CONFIG="$CLAUDE_DIR/.apd-config"
if [ -f "$APD_CONFIG" ]; then
    if grep -q '^PROJECT_NAME=' "$APD_CONFIG" 2>/dev/null; then
        pass ".apd-config exists and has PROJECT_NAME"
        SUM_PROJECT=$(grep '^PROJECT_NAME=' "$APD_CONFIG" 2>/dev/null | cut -d= -f2-)
    else
        fail ".apd-config exists but has no PROJECT_NAME"
    fi
else
    warn ".apd-config DOES NOT EXIST — created during /apd-init"
fi

# .apd-version
if [ -f "$APD_PLUGIN_ROOT/.apd-version" ]; then
    pass ".apd-version exists"
else
    warn ".apd-version DOES NOT EXIST in plugin root"
fi

# Claude Code version
APD_MIN_VERSION="2.1.89"
APD_FUNCTIONAL_VERSION="2.1.32"
if command -v claude &>/dev/null; then
    CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$CC_VERSION" ]; then
        ver_to_num() { echo "$1" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }'; }
        CC_NUM=$(ver_to_num "$CC_VERSION")
        MIN_NUM=$(ver_to_num "$APD_MIN_VERSION")
        FUNC_NUM=$(ver_to_num "$APD_FUNCTIONAL_VERSION")

        if [ "$CC_NUM" -lt "$FUNC_NUM" ] 2>/dev/null; then
            fail "Claude Code $CC_VERSION — TOO OLD for APD (minimum: v$APD_FUNCTIONAL_VERSION)"
        elif [ "$CC_NUM" -lt "$MIN_NUM" ] 2>/dev/null; then
            warn "Claude Code $CC_VERSION — recommended v$APD_MIN_VERSION+ for full feature set"
        else
            pass "Claude Code $CC_VERSION (>= $APD_MIN_VERSION)"
        fi
    else
        warn "Claude Code installed but version cannot be read"
    fi
else
    warn "Claude Code CLI is not in PATH — cannot check version"
fi

# jq
if command -v jq &>/dev/null; then
    pass "jq installed"
else
    fail "jq is NOT installed — guard scripts will not work"
    echo ""
    echo "  Install: brew install jq (macOS) / apt install jq (Linux)"
    echo "  Aborting — no point continuing without jq."
    exit 1
fi

# git
if command -v git &>/dev/null; then
    pass "git installed"
else
    fail "git is NOT installed"
    exit 1
fi

# git repo
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    pass "Git repository initialized"
else
    fail "Directory is not a git repo — initialize with: git init"
fi

# ============================================================
# 2. STRUCTURE — files and directories
# ============================================================
section "2. Structure"

for dir in rules memory agents; do
    if [ -d "$CLAUDE_DIR/$dir" ]; then
        pass ".claude/$dir/"
    else
        fail ".claude/$dir/ DOES NOT EXIST"
    fi
done

# .claude/scripts/ (project-level, for verify-all.sh)
if [ -d "$CLAUDE_DIR/scripts" ]; then
    pass ".claude/scripts/"
else
    fail ".claude/scripts/ DOES NOT EXIST"
fi

# CLAUDE.md
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    pass "CLAUDE.md exists"
    # Project name: .apd-config takes priority, CLAUDE.md heading as fallback
    if [ -z "$SUM_PROJECT" ]; then
        SUM_PROJECT=$(head -5 "$PROJECT_DIR/CLAUDE.md" | grep '^# ' | head -1 | sed 's/^# //')
        [ -z "$SUM_PROJECT" ] && SUM_PROJECT="(unknown)"
    fi
else
    fail "CLAUDE.md DOES NOT EXIST — created during /apd-init"
    [ -z "$SUM_PROJECT" ] && SUM_PROJECT="(no CLAUDE.md)"
fi

# Plugin scripts — exist and executable at $SCRIPT_DIR
PLUGIN_SCRIPTS=(
    guard-git.sh guard-scope.sh guard-bash-scope.sh
    guard-secrets.sh guard-lockfile.sh guard-permission-denied.sh
    pipeline-advance.sh pipeline-gate.sh pipeline-post-commit.sh
    rotate-session-log.sh session-start.sh
)

SCRIPTS_OK=true
SUM_SCRIPTS_TOTAL=$(( ${#PLUGIN_SCRIPTS[@]} + 1 ))  # +1 for verify-all.sh
SUM_SCRIPTS_OK=0
for script in "${PLUGIN_SCRIPTS[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$script" ]; then
        fail "$script DOES NOT EXIST (plugin: $SCRIPT_DIR)"
        SCRIPTS_OK=false
    elif [ ! -x "$SCRIPT_DIR/$script" ]; then
        fail "$script is NOT executable — run: chmod +x $SCRIPT_DIR/*.sh"
        SCRIPTS_OK=false
    else
        ((SUM_SCRIPTS_OK++))
    fi
done

# verify-all.sh — the only script in the project
if [ ! -f "$CLAUDE_DIR/scripts/verify-all.sh" ]; then
    fail "verify-all.sh DOES NOT EXIST (project: .claude/scripts/)"
    SCRIPTS_OK=false
elif [ ! -x "$CLAUDE_DIR/scripts/verify-all.sh" ]; then
    fail "verify-all.sh is NOT executable — run: chmod +x .claude/scripts/verify-all.sh"
    SCRIPTS_OK=false
else
    ((SUM_SCRIPTS_OK++))
fi

if [ "$SCRIPTS_OK" = true ]; then
    pass "All $SUM_SCRIPTS_TOTAL scripts exist and are executable"
fi

# Memory files
for file in MEMORY.md status.md session-log.md pipeline-skip-log.md; do
    if [ -f "$CLAUDE_DIR/memory/$file" ]; then
        pass "memory/$file"
        ((SUM_MEMORY++))
    else
        fail "memory/$file DOES NOT EXIST"
    fi
done

# ============================================================
# 3. SETTINGS.JSON — hook configuration (plugin + project)
# ============================================================
section "3. Settings"

# --- 3a. Plugin hooks/hooks.json ---
PLUGIN_SETTINGS="$APD_PLUGIN_ROOT/hooks/hooks.json"
if [ ! -f "$PLUGIN_SETTINGS" ]; then
    fail "Plugin hooks/hooks.json DOES NOT EXIST"
else
    if ! jq empty "$PLUGIN_SETTINGS" 2>/dev/null; then
        fail "Plugin hooks/hooks.json is NOT valid JSON"
    else
        pass "Plugin hooks/hooks.json valid JSON"

        # SessionStart hook
        if jq -e '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_SETTINGS" &>/dev/null; then
            CMD=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PLUGIN_SETTINGS")
            if echo "$CMD" | grep -q 'session-start.sh'; then
                pass "Plugin: SessionStart -> session-start.sh"
            else
                warn "Plugin: SessionStart hook exists but does not call session-start.sh"
            fi
        else
            warn "Plugin: SessionStart hook is not configured"
        fi

        # PreToolUse Bash -> guard-git
        if jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$PLUGIN_SETTINGS" 2>/dev/null | grep -q 'guard-git'; then
            pass "Plugin: PreToolUse(Bash) -> guard-git.sh"
        else
            fail "Plugin: guard-git.sh is NOT registered as PreToolUse hook for Bash"
        fi

        # PostToolUse Bash -> pipeline-post-commit
        if jq -e '.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[].command' "$PLUGIN_SETTINGS" 2>/dev/null | grep -q 'pipeline-post-commit'; then
            pass "Plugin: PostToolUse(Bash) -> pipeline-post-commit.sh"
        else
            fail "Plugin: pipeline-post-commit.sh is NOT registered — pipeline will not reset after commit"
        fi

        # PostCompact hook
        if jq -e '.hooks.PostCompact[0].hooks[0].command' "$PLUGIN_SETTINGS" &>/dev/null; then
            pass "Plugin: PostCompact hook configured"
        else
            warn "Plugin: PostCompact hook is not configured — context will not be reinjected after compaction"
        fi

        # PermissionDenied hook
        if jq -e '.hooks.PermissionDenied[0].hooks[0].command' "$PLUGIN_SETTINGS" &>/dev/null; then
            pass "Plugin: PermissionDenied hook configured"
        else
            warn "Plugin: PermissionDenied hook is not configured"
        fi
    fi
fi

# --- 3b. Project settings.json ---
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
    fail "Project settings.json DOES NOT EXIST"
else
    if ! jq empty "$SETTINGS" 2>/dev/null; then
        fail "Project settings.json is NOT valid JSON"
    else
        pass "Project settings.json valid JSON"

        # Notification hook
        if jq -e '.hooks.Notification[0].hooks[0].command' "$SETTINGS" &>/dev/null; then
            pass "Project: Notification hook configured"
        else
            warn "Project: Notification hook is not configured"
        fi

        # Attribution empty
        COMMIT_ATTR=$(jq -r '.attribution.commit // "N/A"' "$SETTINGS" 2>/dev/null)
        PR_ATTR=$(jq -r '.attribution.pr // "N/A"' "$SETTINGS" 2>/dev/null)
        if [ "$COMMIT_ATTR" = "" ] && [ "$PR_ATTR" = "" ]; then
            pass "Attribution empty (no AI signatures)"
            SUM_ATTRIBUTION="empty (OK)"
        elif [ "$COMMIT_ATTR" = "N/A" ]; then
            warn "Attribution section does not exist in settings.json"
            SUM_ATTRIBUTION="not defined"
        else
            warn "Attribution is not empty — AI signature may end up in commits"
            SUM_ATTRIBUTION="ACTIVE (check!)"
        fi
    fi
fi

# ============================================================
# 4. PLACEHOLDER CHECK — nothing must remain {{...}}
# ============================================================
section "4. Placeholders"

PLACEHOLDER_FILES=(
    "$PROJECT_DIR/CLAUDE.md"
    "$CLAUDE_DIR/memory/MEMORY.md"
    "$CLAUDE_DIR/memory/status.md"
)

ALL_CLEAN=true
for file in "${PLACEHOLDER_FILES[@]}"; do
    if [ -f "$file" ] && grep -q '{{[A-Z_]*}}' "$file" 2>/dev/null; then
        BASENAME=$(basename "$file")
        PLACEHOLDERS=$(grep -oE '\{\{[A-Z_]+\}\}' "$file" 2>/dev/null | sort -u | tr '\n' ' ')
        fail "$BASENAME -> $PLACEHOLDERS"
        ALL_CLEAN=false
    fi
done

if [ "$ALL_CLEAN" = true ]; then
    pass "All placeholders replaced"
fi

# .apd-config and .apd-version existence
if [ -f "$CLAUDE_DIR/.apd-config" ]; then
    pass ".apd-config exists"
else
    fail ".apd-config DOES NOT EXIST — created during /apd-init"
fi

if [ -f "$APD_PLUGIN_ROOT/.apd-version" ]; then
    pass ".apd-version exists"
else
    warn ".apd-version DOES NOT EXIST in plugin root"
fi

# ============================================================
# 5. CLAUDE.md — required sections
# ============================================================
section "5. CLAUDE.md content"

if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    REQUIRED_SECTIONS=("## Stack" "## APD" "### Pipeline" "### Guardrail" "### Human gate" "### Session memory" "## Anti-patterns")
    for sec in "${REQUIRED_SECTIONS[@]}"; do
        if grep -q "$sec" "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
            pass "Section: $sec"
        else
            fail "Missing section: $sec"
        fi
    done

    # Memory reference
    if grep -q '@.claude/memory/' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
        pass "Memory reference (@.claude/memory/)"
    else
        warn "CLAUDE.md does not reference memory files"
    fi
fi

# ============================================================
# 6. AGENTS — frontmatter validation
# ============================================================
section "6. Agents"

AGENT_COUNT=0
for agent_file in "$CLAUDE_DIR/agents"/*.md; do
    [ "$(basename "$agent_file")" = "TEMPLATE.md" ] && continue
    [ ! -f "$agent_file" ] && continue
    AGENT_NAME=$(basename "$agent_file" .md)
    ((AGENT_COUNT++))

    # Placeholder check
    if grep -q '{{' "$agent_file" 2>/dev/null; then
        fail "Agent $AGENT_NAME — unreplaced placeholders"
        continue
    fi

    # Frontmatter exists
    if ! head -1 "$agent_file" | grep -q '^---'; then
        fail "Agent $AGENT_NAME — no frontmatter (---)"
        continue
    fi

    # model defined
    if grep -q '^model:' "$agent_file" 2>/dev/null; then
        MODEL=$(grep '^model:' "$agent_file" | head -1 | awk '{print $2}')
        pass "Agent $AGENT_NAME — model: $MODEL"
    else
        fail "Agent $AGENT_NAME — model is NOT defined"
    fi

    # guard-scope hook — references ${CLAUDE_PLUGIN_ROOT}
    if grep -q 'guard-scope.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-scope.sh registered"
    else
        warn "Agent $AGENT_NAME — guard-scope.sh is NOT registered (agent has no file scope protection)"
    fi

    # guard-git hook — references ${CLAUDE_PLUGIN_ROOT}
    if grep -q 'guard-git.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-git.sh registered"
    else
        fail "Agent $AGENT_NAME — guard-git.sh is NOT registered (agent can commit!)"
    fi

    # guard-secrets hook
    if grep -q 'guard-secrets.sh' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — guard-secrets.sh registered"
    else
        warn "Agent $AGENT_NAME — guard-secrets.sh is NOT registered"
    fi

    # Hook paths use ${CLAUDE_PLUGIN_ROOT} (not {{PROJECT_PATH}})
    if grep -q '${CLAUDE_PLUGIN_ROOT}' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — hook paths use \${CLAUDE_PLUGIN_ROOT}"
    elif grep -q '{{PROJECT_PATH}}' "$agent_file" 2>/dev/null; then
        fail "Agent $AGENT_NAME — hook paths use {{PROJECT_PATH}} instead of \${CLAUDE_PLUGIN_ROOT}"
    else
        warn "Agent $AGENT_NAME — hook paths use neither \${CLAUDE_PLUGIN_ROOT} nor {{PROJECT_PATH}}"
    fi

    # FORBIDDEN section
    if grep -qi 'FORBIDDEN\|NEVER.*commit\|ZABRANJENO\|NIKADA.*commit' "$agent_file" 2>/dev/null; then
        pass "Agent $AGENT_NAME — commit prohibition documented"
    else
        warn "Agent $AGENT_NAME — no explicit commit prohibition"
    fi
done

if [ "$AGENT_COUNT" -eq 0 ]; then
    warn "No agents defined (only TEMPLATE.md)"
    SUM_AGENTS="0"
    SUM_AGENT_NAMES="none"
else
    pass "$AGENT_COUNT agent(s) total"
    SUM_AGENTS="$AGENT_COUNT"
    SUM_AGENT_NAMES=$(find "$CLAUDE_DIR/agents" -name "*.md" ! -name "TEMPLATE.md" -exec basename {} .md \; 2>/dev/null | sort | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
fi

# ============================================================
# 7. GUARD FUNCTIONAL TESTS
# ============================================================
section "7. Guard tests (functional)"

# Collect guard summary
GUARD_LIST=()

# guard-git: blocks git commit without prefix
RESULT=$(echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blocks: git commit without APD_ORCHESTRATOR_COMMIT=1"
    GUARD_LIST+=("git")
else
    fail "guard-git DOES NOT BLOCK git commit without prefix (exit: $EXIT_CODE)"
fi

# guard-git: allows with prefix (but pipeline gate blocks — that's OK)
RESULT=$(echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git commit -m test"}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
# exit 0 = allowed, exit 2 = pipeline gate blocked (both are valid responses)
if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git recognizes APD_ORCHESTRATOR_COMMIT=1 prefix"
else
    fail "guard-git does not recognize APD_ORCHESTRATOR_COMMIT=1 prefix (exit: $EXIT_CODE)"
fi

# guard-git: blocks git add .
RESULT=$(echo '{"tool_input":{"command":"git add ."}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blocks: git add ."
else
    fail "guard-git DOES NOT BLOCK git add . (exit: $EXIT_CODE)"
fi

# guard-git: blocks --no-verify
RESULT=$(echo '{"tool_input":{"command":"git commit --no-verify -m test"}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blocks: --no-verify"
else
    fail "guard-git DOES NOT BLOCK --no-verify (exit: $EXIT_CODE)"
fi

# guard-git: blocks force push
RESULT=$(echo '{"tool_input":{"command":"git push --force"}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blocks: git push --force"
else
    fail "guard-git DOES NOT BLOCK git push --force (exit: $EXIT_CODE)"
fi

# guard-git: blocks destructive ops
RESULT=$(echo '{"tool_input":{"command":"git reset --hard HEAD"}}' | bash "$SCRIPT_DIR/guard-git.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-git blocks: git reset --hard"
else
    fail "guard-git DOES NOT BLOCK git reset --hard (exit: $EXIT_CODE)"
fi

# guard-scope: blocks outside scope
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/outside/file.ts\"}}" | bash "$SCRIPT_DIR/guard-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-scope blocks: file outside allowed scope"
    GUARD_LIST+=("scope")
else
    fail "guard-scope DOES NOT BLOCK file outside scope (exit: $EXIT_CODE)"
fi

# guard-scope: allows inside scope
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/src/test.ts\"}}" | bash "$SCRIPT_DIR/guard-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    pass "guard-scope allows: file inside scope"
else
    fail "guard-scope BLOCKS file that IS inside scope (exit: $EXIT_CODE)"
fi

# guard-bash-scope: blocks write outside scope
RESULT=$(echo '{"tool_input":{"command":"echo test > /tmp/outside.txt"}}' | bash "$SCRIPT_DIR/guard-bash-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-bash-scope blocks: bash write outside scope"
    GUARD_LIST+=("bash-scope")
else
    fail "guard-bash-scope DOES NOT BLOCK bash write outside scope (exit: $EXIT_CODE)"
fi

# guard-bash-scope: blocks runtime write (node -e writeFileSync)
RESULT=$(echo '{"tool_input":{"command":"node -e \"require('"'"'fs'"'"').writeFileSync('"'"'/tmp/x.js'"'"', '"'"'data'"'"')\""}}' | bash "$SCRIPT_DIR/guard-bash-scope.sh" src/ 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-bash-scope blocks: runtime write (node)"
else
    fail "guard-bash-scope DOES NOT BLOCK runtime write node -e (exit: $EXIT_CODE)"
fi

# guard-lockfile: blocks lock file
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/package-lock.json\"}}" | bash "$SCRIPT_DIR/guard-lockfile.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-lockfile blocks: package-lock.json"
    GUARD_LIST+=("lockfile")
else
    fail "guard-lockfile DOES NOT BLOCK package-lock.json (exit: $EXIT_CODE)"
fi

# guard-secrets: blocks sensitive file
RESULT=$(echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/.env.production\"}}" | bash "$SCRIPT_DIR/guard-secrets.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "guard-secrets blocks: .env.production"
    GUARD_LIST+=("secrets")
else
    fail "guard-secrets DOES NOT BLOCK .env.production (exit: $EXIT_CODE)"
fi

SUM_GUARDS=$(printf '%s, ' "${GUARD_LIST[@]}" | sed 's/, $//')

# ============================================================
# 8. PIPELINE END-TO-END TEST
# ============================================================
section "8. Pipeline end-to-end test"

# Restore function for safe cleanup on interrupt
restore_pipeline_state() {
    if [ "$HAD_EXISTING_PIPELINE" = true ] && [ -d /tmp/apd-verify-backup ]; then
        mkdir -p "$PIPELINE_DIR"
        cp /tmp/apd-verify-backup/*.done "$PIPELINE_DIR/" 2>/dev/null
        rm -rf /tmp/apd-verify-backup
    fi
    if [ -n "${SESSION_LOG_BACKUP:-}" ] && [ -f "${SESSION_LOG_BACKUP:-}" ]; then
        cp "$SESSION_LOG_BACKUP" "$CLAUDE_DIR/memory/session-log.md"
        rm -f "$SESSION_LOG_BACKUP"
    fi
}
trap restore_pipeline_state EXIT INT TERM

# Save current pipeline state
HAD_EXISTING_PIPELINE=false
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    HAD_EXISTING_PIPELINE=true
    mkdir -p /tmp/apd-verify-backup
    cp "$PIPELINE_DIR"/*.done /tmp/apd-verify-backup/ 2>/dev/null
fi

# Save session-log and temporarily remove [fill in] entries
# (spec gate blocks if previous entry has [fill in])
SESSION_LOG_BACKUP=""
if [ -f "$CLAUDE_DIR/memory/session-log.md" ]; then
    SESSION_LOG_BACKUP=$(mktemp)
    cp "$CLAUDE_DIR/memory/session-log.md" "$SESSION_LOG_BACKUP"
    # Remove last entry if it has [fill in] placeholders
    LAST_LINE=$(grep -n '^## \[' "$CLAUDE_DIR/memory/session-log.md" | tail -1 | cut -d: -f1)
    if [ -n "$LAST_LINE" ]; then
        TAIL_CONTENT=$(tail -n +"$LAST_LINE" "$CLAUDE_DIR/memory/session-log.md")
        if echo "$TAIL_CONTENT" | grep -q '\[fill in' 2>/dev/null; then
            head -n $((LAST_LINE - 1)) "$CLAUDE_DIR/memory/session-log.md" > "$CLAUDE_DIR/memory/session-log.md.tmp"
            mv "$CLAUDE_DIR/memory/session-log.md.tmp" "$CLAUDE_DIR/memory/session-log.md"
        fi
    fi
fi

# Clean start
bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1

# pipeline-gate: must block when no steps exist
RESULT=$(bash "$SCRIPT_DIR/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blocks: empty pipeline"
else
    fail "pipeline-gate DOES NOT BLOCK empty pipeline (exit: $EXIT_CODE)"
fi

# Spec
RESULT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" spec "APD-VERIFY-TEST" 2>&1)
if echo "$RESULT" | grep -q "Pipeline started"; then
    pass "pipeline-advance: spec"
else
    fail "pipeline-advance spec ERROR: $RESULT"
fi

# Builder after spec (should pass because spec exists)
RESULT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" builder 2>&1)
if echo "$RESULT" | grep -q "builder completed"; then
    pass "pipeline-advance: builder"
else
    fail "pipeline-advance builder ERROR: $RESULT"
fi

# pipeline-gate: must block (missing reviewer + verifier)
RESULT=$(bash "$SCRIPT_DIR/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blocks: missing reviewer + verifier"
else
    fail "pipeline-gate DOES NOT BLOCK when steps are missing (exit: $EXIT_CODE)"
fi

# Reviewer
RESULT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" reviewer 2>&1)
if echo "$RESULT" | grep -q "reviewer completed"; then
    pass "pipeline-advance: reviewer"
else
    fail "pipeline-advance reviewer ERROR: $RESULT"
fi

# Verifier
RESULT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" verifier 2>&1)
if echo "$RESULT" | grep -q "COMMIT ALLOWED"; then
    pass "pipeline-advance: verifier -> COMMIT ALLOWED"
else
    fail "pipeline-advance verifier ERROR: $RESULT"
fi

# pipeline-gate: must pass (all 4 steps completed)
RESULT=$(bash "$SCRIPT_DIR/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    pass "pipeline-gate passes: all 4 steps completed"
else
    fail "pipeline-gate DOES NOT PASS when all steps are done (exit: $EXIT_CODE)"
fi

# Rollback test
RESULT=$(bash "$SCRIPT_DIR/pipeline-advance.sh" rollback 2>&1)
if echo "$RESULT" | grep -q "Rollback: verifier removed"; then
    pass "pipeline-advance: rollback (verifier -> reviewer)"
else
    fail "pipeline-advance rollback ERROR: $RESULT"
fi

# pipeline-gate: must block after rollback
RESULT=$(bash "$SCRIPT_DIR/pipeline-gate.sh" 2>&1)
EXIT_CODE=$?
if [ $EXIT_CODE -eq 2 ]; then
    pass "pipeline-gate blocks after rollback"
    SUM_PIPELINE="functional (E2E + rollback)"
else
    fail "pipeline-gate DOES NOT BLOCK after rollback (exit: $EXIT_CODE)"
    SUM_PIPELINE="has errors"
fi

# Cleanup
bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1

# Remove test entry from session-log
if [ -f "$CLAUDE_DIR/memory/session-log.md" ]; then
    # Remove last entry if it's APD-VERIFY-TEST
    if grep -q "APD-VERIFY-TEST" "$CLAUDE_DIR/memory/session-log.md" 2>/dev/null; then
        # Find the line where the test entry starts and delete to end
        FIRST_TEST_LINE=$(grep -n "APD-VERIFY-TEST" "$CLAUDE_DIR/memory/session-log.md" | head -1 | cut -d: -f1)
        if [ -n "$FIRST_TEST_LINE" ]; then
            # Entry starts 1 line before (## [date]) and we add 1 for the blank line above
            START=$((FIRST_TEST_LINE - 2))
            [ "$START" -lt 1 ] && START=1
            head -n "$START" "$CLAUDE_DIR/memory/session-log.md" > "$CLAUDE_DIR/memory/session-log.md.tmp"
            mv "$CLAUDE_DIR/memory/session-log.md.tmp" "$CLAUDE_DIR/memory/session-log.md"
        fi
    fi
fi

# Restore previous pipeline state
if [ "$HAD_EXISTING_PIPELINE" = true ]; then
    mkdir -p "$PIPELINE_DIR"
    cp /tmp/apd-verify-backup/*.done "$PIPELINE_DIR/" 2>/dev/null
    rm -rf /tmp/apd-verify-backup
fi

# Restore session-log from backup
if [ -n "$SESSION_LOG_BACKUP" ] && [ -f "$SESSION_LOG_BACKUP" ]; then
    cp "$SESSION_LOG_BACKUP" "$CLAUDE_DIR/memory/session-log.md"
    rm -f "$SESSION_LOG_BACKUP"
fi

# ============================================================
# 9. VERIFY-ALL.SH — configured or not
# ============================================================
section "9. verify-all.sh configuration"

if [ -f "$CLAUDE_DIR/scripts/verify-all.sh" ]; then
    # Check if at least one section is uncommented
    UNCOMMENTED_CHECKS=$(grep -cE '^\s*(if.*CHANGED_FILES|dotnet |npm |python |go |php )' "$CLAUDE_DIR/scripts/verify-all.sh" 2>/dev/null || echo 0)
    if [ "$UNCOMMENTED_CHECKS" -gt 0 ]; then
        pass "verify-all.sh has active build/test checks ($UNCOMMENTED_CHECKS)"
        SUM_VERIFY_ALL="active ($UNCOMMENTED_CHECKS checks)"
    else
        warn "verify-all.sh is fully commented out — verification is not active"
        echo "       Uncomment the relevant sections for your stack."
        SUM_VERIFY_ALL="commented out"
    fi
fi

# ============================================================
# 10. .GITIGNORE — protection
# ============================================================
section "10. Gitignore"

GIT_IGNORE_ITEMS=()
if [ -f "$PROJECT_DIR/.gitignore" ]; then
    if grep -q '\.claude/settings\.local\.json' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        pass ".gitignore: settings.local.json"
        GIT_IGNORE_ITEMS+=("local.json")
    else
        warn ".gitignore does not contain .claude/settings.local.json"
    fi

    if grep -q '\.claude/\.pipeline' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        pass ".gitignore: .claude/.pipeline/"
        GIT_IGNORE_ITEMS+=(".pipeline/")
    else
        fail ".gitignore does not contain .claude/.pipeline/ — pipeline flags may end up in the repo"
    fi
else
    fail ".gitignore DOES NOT EXIST"
fi
SUM_GITIGNORE=$(printf '%s, ' "${GIT_IGNORE_ITEMS[@]}" | sed 's/, $//')
[ -z "$SUM_GITIGNORE" ] && SUM_GITIGNORE="incomplete"

# ============================================================
# SUMMARY TABLE
# ============================================================

# Fallback for SUM_PROJECT
[ -z "$SUM_PROJECT" ] && SUM_PROJECT="(unknown)"

# Shorten agent names if list is too long
AGENT_DISPLAY="$SUM_AGENT_NAMES"
if [ ${#AGENT_DISPLAY} -gt 40 ]; then
    AGENT_DISPLAY="${AGENT_DISPLAY:0:37}..."
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║              APD — Setup Summary                     ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  %-15s │ %-36s ║\n" "Project"        "$SUM_PROJECT"
printf "║  %-15s │ %-36s ║\n" "Agents"         "$SUM_AGENTS ($AGENT_DISPLAY)"
printf "║  %-15s │ %-36s ║\n" "Scripts"        "$SUM_SCRIPTS_OK/$SUM_SCRIPTS_TOTAL"
printf "║  %-15s │ %-36s ║\n" "Guards"         "$SUM_GUARDS"
printf "║  %-15s │ %-36s ║\n" "Pipeline"       "$SUM_PIPELINE"
printf "║  %-15s │ %-36s ║\n" "verify-all.sh"  "$SUM_VERIFY_ALL"
printf "║  %-15s │ %-36s ║\n" "Memory files"   "$SUM_MEMORY/4"
printf "║  %-15s │ %-36s ║\n" "Gitignore"      "$SUM_GITIGNORE"
printf "║  %-15s │ %-36s ║\n" "Attribution"    "$SUM_ATTRIBUTION"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  PASS: %-3s │ FAIL: %-3s │ WARN: %-3s               ║\n" "$PASS" "$FAIL" "$WARN"
echo "╚══════════════════════════════════════════════════════╝"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "APD IS NOT READY — fix FAIL items."
    echo ""
    echo "Common cause: placeholders are not replaced."
    echo "Run /apd-init or manually replace {{...}} values."
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    echo ""
    echo "APD IS FUNCTIONAL — WARN items are recommendations for improvement."
fi

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo ""
    echo "APD IS FULLY CONFIGURED. Ready to go."
fi

exit 0
