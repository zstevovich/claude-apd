#!/bin/bash
# APD Session Start — učitava kontekst projekta na početku sesije

# PROMENITI na apsolutnu putanju projekta:
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

# Proveri da li su placeholder-i razrešeni u settings.json
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && grep -q '\[APSOLUTNA_PUTANJA\]' "$SETTINGS_FILE"; then
    echo ""
    echo "KRITIČNO: settings.json sadrži nerazrešene placeholder-e!" >&2
    echo "  Hook-ovi (guard-git, guard-scope, session-start) NE RADE." >&2
    echo "  Pokreni: bash .claude/scripts/setup.sh" >&2
    echo ""
fi

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
