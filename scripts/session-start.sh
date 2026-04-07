#!/bin/bash
# APD Session Start — loads project context at the beginning of a session

source "$(dirname "$0")/lib/resolve-project.sh"
cd "$PROJECT_DIR" || exit 0

# ===== VERSION CHECK =====
APD_MIN_VERSION="2.1.89"
APD_FUNCTIONAL_VERSION="2.1.32"

# Read min version from plugin if available
if [ -f "$APD_PLUGIN_ROOT/.apd-version" ]; then
    _PLUGIN_MIN=$(grep '^MIN_CC_VERSION=' "$APD_PLUGIN_ROOT/.apd-version" 2>/dev/null | cut -d= -f2-)
    [ -n "$_PLUGIN_MIN" ] && APD_MIN_VERSION="$_PLUGIN_MIN"
    _PLUGIN_FUNC=$(grep '^FUNC_CC_VERSION=' "$APD_PLUGIN_ROOT/.apd-version" 2>/dev/null | cut -d= -f2-)
    [ -n "$_PLUGIN_FUNC" ] && APD_FUNCTIONAL_VERSION="$_PLUGIN_FUNC"
fi

if command -v claude &>/dev/null; then
    CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$CC_VERSION" ]; then
        # Compare versions: convert to numeric value (major*10000 + minor*100 + patch)
        ver_to_num() {
            echo "$1" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }'
        }
        CC_NUM=$(ver_to_num "$CC_VERSION")
        MIN_NUM=$(ver_to_num "$APD_MIN_VERSION")
        FUNC_NUM=$(ver_to_num "$APD_FUNCTIONAL_VERSION")

        if [ "$CC_NUM" -lt "$FUNC_NUM" ] 2>/dev/null; then
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║  ⛔ APD: Claude Code $CC_VERSION is TOO OLD                 ║"
            echo "║  Minimum for APD: v$APD_FUNCTIONAL_VERSION (agents + pipeline)         ║"
            echo "║  Update: npm install -g @anthropic-ai/claude-code    ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo ""
        elif [ "$CC_NUM" -lt "$MIN_NUM" ] 2>/dev/null; then
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║  ⚠ APD: Claude Code $CC_VERSION — missing features         ║"
            echo "║  Recommended: v$APD_MIN_VERSION+ for full APD feature set   ║"
            echo "║  Missing: conditional hooks, PostCompact,            ║"
            echo "║    PermissionDenied, effort frontmatter              ║"
            echo "║  Update: npm install -g @anthropic-ai/claude-code    ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo ""
        fi
    fi
fi
# =========================

# ===== SELF-HEALING — detect and fix problems =====
HEALED=0
BLOCKED=0

heal()  { echo "  ✓ HEALED: $1"; HEALED=$((HEALED + 1)); }
block() { echo "  ✗ BLOCKED: $1"; BLOCKED=$((BLOCKED + 1)); }

# 1. jq — guards don't work without it (cannot be auto-fixed)
if ! command -v jq &>/dev/null; then
    block "jq is NOT installed — guard scripts will not work!"
    echo "    -> Install: brew install jq (macOS) / apt install jq (Linux)"
fi

# 2. Scripts — if they exist but are not executable, fix automatically
for script in guard-git.sh guard-scope.sh guard-bash-scope.sh guard-secrets.sh guard-lockfile.sh guard-permission-denied.sh guard-orchestrator.sh track-agent.sh pipeline-advance.sh pipeline-gate.sh pipeline-post-commit.sh verify-all.sh session-start.sh rotate-session-log.sh verify-apd.sh verify-contracts.sh; do
    SCRIPT_PATH="$SCRIPT_DIR/$script"
    if [ -f "$SCRIPT_PATH" ] && [ ! -x "$SCRIPT_PATH" ]; then
        chmod +x "$SCRIPT_PATH" 2>/dev/null
        if [ -x "$SCRIPT_PATH" ]; then
            heal "$script was not executable — fixed (chmod +x)"
        else
            block "$script is not executable and cannot be fixed (permissions?)"
        fi
    elif [ ! -f "$SCRIPT_PATH" ]; then
        # Only critical scripts are blockers
        case "$script" in
            guard-git.sh|pipeline-advance.sh|pipeline-gate.sh)
                block "$script is MISSING — pipeline will not work"
                ;;
        esac
    fi
done

# 3. settings.json — detect merge conflict markers
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$SETTINGS_FILE" 2>/dev/null; then
        CONFLICT_LINE=$(grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$SETTINGS_FILE" | head -1 | cut -d: -f1)
        block "settings.json has a merge conflict (line $CONFLICT_LINE) — resolve manually"
    elif ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        block "settings.json is NOT valid JSON — check syntax"
    fi
fi

# 4. Stale pipeline — flags older than 24h
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    OLDEST_FLAG=$(ls -t "$PIPELINE_DIR"/*.done 2>/dev/null | tail -1)
    if [ -n "$OLDEST_FLAG" ]; then
        MTIME=$(stat -f %m "$OLDEST_FLAG" 2>/dev/null || stat -c %Y "$OLDEST_FLAG" 2>/dev/null || echo "0")
        if [ -n "$MTIME" ] && [ "$MTIME" -gt 0 ] 2>/dev/null; then
            FLAG_AGE=$(( $(date +%s) - MTIME ))
        else
            FLAG_AGE=0
        fi
        if [ "$FLAG_AGE" -gt 86400 ]; then
            # Collect context before reset
            STALE_TASK="[unknown]"
            STALE_STEP="spec"
            if [ -f "$PIPELINE_DIR/spec.done" ]; then
                STALE_TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            fi
            for step in verifier reviewer builder spec; do
                if [ -f "$PIPELINE_DIR/$step.done" ]; then
                    STALE_STEP="$step"
                    break
                fi
            done

            STALE_HOURS=$((FLAG_AGE / 3600))
            heal "Stale pipeline detected (${STALE_HOURS}h old)"
            echo "    -> Task: $STALE_TASK (last step: $STALE_STEP)"
            echo "    -> Auto-resetting..."
            bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1
            echo "    -> Pipeline reset. Ready for new task."
        fi
    fi
fi

# 5. Incomplete pipeline — show where it stopped and what's next
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    # Pipeline exists but is not stale — show context
    INCOMPLETE=false
    NEXT_STEP=""
    for step in spec builder reviewer verifier; do
        if [ ! -f "$PIPELINE_DIR/$step.done" ]; then
            INCOMPLETE=true
            NEXT_STEP="$step"
            break
        fi
    done

    if [ "$INCOMPLETE" = true ] && [ -n "$NEXT_STEP" ]; then
        CURRENT_TASK="[unknown]"
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            CURRENT_TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
        fi
        echo "  -> Pipeline in progress: $CURRENT_TASK — next step: $NEXT_STEP"
    fi
fi

# Show summary
if [ "$HEALED" -gt 0 ] || [ "$BLOCKED" -gt 0 ]; then
    echo ""
    if [ "$BLOCKED" -gt 0 ]; then
        echo "╔═══════════════════════════════════════════════════╗"
        printf "║  ⚠ APD: %d fixed, %d require attention                ║\n" "$HEALED" "$BLOCKED"
        echo "║  Run: bash .claude/scripts/verify-apd.sh          ║"
        echo "╚═══════════════════════════════════════════════════╝"
    else
        echo "╔═══════════════════════════════════════════════════╗"
        printf "║  ✓ APD: %d problem(s) automatically fixed           ║\n" "$HEALED"
        echo "╚═══════════════════════════════════════════════════╝"
    fi
    echo ""
fi
# ========================================

# Rotate session log (keeps last 10 entries)
if [ -x "$SCRIPT_DIR/rotate-session-log.sh" ]; then
    bash "$SCRIPT_DIR/rotate-session-log.sh" 10 2>/dev/null
fi

# ===== DYNAMIC PROJECT NAME =====
# Priority: userConfig env var > .apd-config > CLAUDE.md heading > directory name
PROJ_NAME="${CLAUDE_PLUGIN_OPTION_PROJECT_NAME:-}"
APD_CONFIG="$CLAUDE_DIR/.apd-config"
if [ -z "$PROJ_NAME" ] && [ -f "$APD_CONFIG" ]; then
    PROJ_NAME=$(grep '^PROJECT_NAME=' "$APD_CONFIG" 2>/dev/null | cut -d= -f2-)
fi
if [ -z "$PROJ_NAME" ] && [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
    PROJ_NAME=$(head -5 "$PROJECT_DIR/CLAUDE.md" | grep '^# ' | head -1 | sed 's/^# //')
fi
PROJ_NAME="${PROJ_NAME:-$(basename "$PROJECT_DIR")}"
echo "=== $PROJ_NAME ==="
# ==================================
echo ""

# Status
if [ -f "$MEMORY_DIR/status.md" ]; then
  echo "--- Current status ---"
  head -50 "$MEMORY_DIR/status.md"
  echo ""
fi

# Pipeline
echo "--- Pipeline ---"
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null; then
    TASK="[idle]"
    if [ -f "$PIPELINE_DIR/spec.done" ]; then
        TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
    fi
    echo "Task: $TASK"
    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            echo "  [DONE] $step"
        else
            echo "  [----] $step"
        fi
    done
else
    echo "  [idle] No active pipeline"
fi
echo ""

# Last session
if [ -f "$MEMORY_DIR/session-log.md" ]; then
  echo "--- Last session ---"
  tail -20 "$MEMORY_DIR/session-log.md"
fi
