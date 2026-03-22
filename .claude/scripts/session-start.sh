#!/bin/bash
# APD Session Start — učitava kontekst projekta na početku sesije

# PROMENITI na apsolutnu putanju projekta:
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MEMORY_DIR=".claude/memory"

echo "=== [PROJECT_NAME] ==="
echo ""

# Trenutni status
if [ -f "$MEMORY_DIR/status.md" ]; then
    echo "--- Trenutni status ---"
    head -30 "$MEMORY_DIR/status.md"
    echo ""
fi

# Poslednja sesija
if [ -f "$MEMORY_DIR/session-log.md" ]; then
    echo "--- Poslednja sesija ---"
    tail -20 "$MEMORY_DIR/session-log.md"
fi
