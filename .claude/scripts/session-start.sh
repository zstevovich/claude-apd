#!/bin/bash
# APD Session Start — učitava kontekst projekta na početku sesije

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MEMORY_DIR=".claude/memory"
PIPELINE_DIR=".claude/.pipeline"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ===== CANARY — brzi health check =====
CANARY_FAIL=0
canary_fail() { echo "  ⚠ CANARY: $1"; ((CANARY_FAIL++)); }

# jq — bez njega guard-ovi ne rade
if ! command -v jq &>/dev/null; then
    canary_fail "jq NIJE instaliran — guard skripte neće raditi!"
fi

# Kritične skripte — postoje i executable
for script in guard-git.sh pipeline-advance.sh pipeline-gate.sh; do
    if [ ! -x "$SCRIPT_DIR/$script" ]; then
        canary_fail "$script nedostaje ili nije executable"
    fi
done

# settings.json — validan JSON
if [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    if ! jq empty "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
        canary_fail "settings.json NIJE validan JSON (merge conflict?)"
    fi
fi

# Stale pipeline — .done fajlovi stariji od 24h
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    OLDEST_FLAG=$(ls -t "$PIPELINE_DIR"/*.done 2>/dev/null | tail -1)
    if [ -n "$OLDEST_FLAG" ]; then
        FLAG_AGE=$(( $(date +%s) - $(stat -f %m "$OLDEST_FLAG" 2>/dev/null || stat -c %Y "$OLDEST_FLAG" 2>/dev/null || echo $(date +%s)) ))
        if [ "$FLAG_AGE" -gt 86400 ]; then
            canary_fail "Pipeline flags stariji od 24h — prethodna sesija crashovala? Pokreni: pipeline-advance.sh reset"
        fi
    fi
fi

if [ "$CANARY_FAIL" -gt 0 ]; then
    echo "╔═══════════════════════════════════════════╗"
    echo "║  ⚠ APD CANARY: $CANARY_FAIL problem(a) detektovan(o)    ║"
    echo "║  Pokreni: bash .claude/scripts/verify-apd.sh   ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""
fi
# ========================================

# Rotiraj session log (čuva poslednjih 10 entry-ja)
if [ -x "$SCRIPT_DIR/rotate-session-log.sh" ]; then
    bash "$SCRIPT_DIR/rotate-session-log.sh" 10 2>/dev/null
fi

# ===== PRILAGODI IME PROJEKTA =====
echo "=== {{PROJECT_NAME}} ==="
# ==================================
echo ""

# Status
if [ -f "$MEMORY_DIR/status.md" ]; then
  echo "--- Trenutni status ---"
  head -30 "$MEMORY_DIR/status.md"
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
    echo "  [idle] Nema aktivnog pipeline-a"
fi
echo ""

# Poslednja sesija
if [ -f "$MEMORY_DIR/session-log.md" ]; then
  echo "--- Poslednja sesija ---"
  tail -20 "$MEMORY_DIR/session-log.md"
fi
