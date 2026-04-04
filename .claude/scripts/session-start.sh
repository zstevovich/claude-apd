#!/bin/bash
# APD Session Start — učitava kontekst projekta na početku sesije

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MEMORY_DIR=".claude/memory"
PIPELINE_DIR=".claude/.pipeline"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
