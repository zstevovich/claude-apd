#!/bin/bash
# APD Setup — zamenjuje placeholder-e sa apsolutnom putanjom projekta

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$PROJECT_DIR/.claude"

echo "APD Setup"
echo "========="
echo "Projekat: $PROJECT_DIR"
echo ""

# Zameni [APSOLUTNA_PUTANJA] u settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    if grep -q '\[APSOLUTNA_PUTANJA\]' "$CLAUDE_DIR/settings.json"; then
        sed -i '' "s|\[APSOLUTNA_PUTANJA\]|$PROJECT_DIR|g" "$CLAUDE_DIR/settings.json"
        echo "✓ settings.json — putanja konfigurisana"
    else
        echo "· settings.json — već konfigurisano"
    fi
fi

# Zameni [APSOLUTNA_PUTANJA] u agent fajlovima
for f in "$CLAUDE_DIR/agents/"*.md; do
    [ -f "$f" ] || continue
    if grep -q '\[APSOLUTNA_PUTANJA\]' "$f"; then
        sed -i '' "s|\[APSOLUTNA_PUTANJA\]|$PROJECT_DIR|g" "$f"
        echo "✓ $(basename "$f") — putanja konfigurisana"
    fi
done

# Zameni [PROJECT_NAME] ako korisnik želi
echo ""
read -p "Naziv projekta (ili Enter za preskakanje): " PROJECT_NAME
if [ -n "$PROJECT_NAME" ]; then
    # Svi fajlovi koji sadrže [PROJECT_NAME]
    TARGET_FILES=(
        "$CLAUDE_DIR/settings.json"
        "$CLAUDE_DIR/scripts/session-start.sh"
        "$CLAUDE_DIR/memory/MEMORY.md"
        "$CLAUDE_DIR/agents/"*.md
        "$PROJECT_DIR/CLAUDE.md"
    )
    for f in "${TARGET_FILES[@]}"; do
        [ -f "$f" ] || continue
        if grep -q '\[PROJECT_NAME\]' "$f"; then
            sed -i '' "s|\[PROJECT_NAME\]|$PROJECT_NAME|g" "$f"
            echo "✓ $(basename "$f") — naziv projekta setovan"
        fi
    done
fi

echo ""
echo "Setup završen."
echo "Sledeći koraci:"
echo "  1. Prilagodi CLAUDE.md za svoj projekat"
echo "  2. Prilagodi verify-all.sh za svoj build/test sistem"
echo "  3. Kreiraj agente u .claude/agents/ po potrebi"
