#!/bin/bash
# APD Session Log Rotation — arhivira starije session entry-je
# Čuva poslednjih MAX_ENTRIES, starije premešta u session-log-archive.md

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MEMORY_DIR="$PROJECT_DIR/.claude/memory"
LOG_FILE="$MEMORY_DIR/session-log.md"
ARCHIVE_FILE="$MEMORY_DIR/session-log-archive.md"

MAX_ENTRIES="${1:-10}"

if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

ENTRY_COUNT=$(grep -c '^## [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$LOG_FILE" 2>/dev/null || echo 0)

if [ "$ENTRY_COUNT" -le "$MAX_ENTRIES" ]; then
    exit 0
fi

TO_ARCHIVE=$((ENTRY_COUNT - MAX_ENTRIES))

echo "Session log rotacija: $ENTRY_COUNT entry-ja, arhiviranje $TO_ARCHIVE starijih..." >&2

FIRST_ENTRY_LINE=$(grep -n '^## [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$LOG_FILE" | head -1 | cut -d: -f1)
HEADER=""

if [ -n "$FIRST_ENTRY_LINE" ] && [ "$FIRST_ENTRY_LINE" -gt 1 ]; then
    HEADER=$(head -n $((FIRST_ENTRY_LINE - 1)) "$LOG_FILE")
fi

KEEP_FROM_LINE=$(grep -n '^## [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$LOG_FILE" | tail -n "$MAX_ENTRIES" | head -1 | cut -d: -f1)

if [ -z "$KEEP_FROM_LINE" ]; then
    exit 0
fi

ARCHIVE_CONTENT=$(sed -n "${FIRST_ENTRY_LINE},$((KEEP_FROM_LINE - 1))p" "$LOG_FILE")
KEEP_CONTENT=$(sed -n "${KEEP_FROM_LINE},\$p" "$LOG_FILE")

if [ ! -f "$ARCHIVE_FILE" ]; then
    cat > "$ARCHIVE_FILE" << 'EOF'
# Session Log — Arhiva

> Arhivirani session log entry-ji. Rotacija automatska.

---

EOF
fi

echo "$ARCHIVE_CONTENT" >> "$ARCHIVE_FILE"

if [ -n "$HEADER" ]; then
    printf '%s\n%s\n' "$HEADER" "$KEEP_CONTENT" > "$LOG_FILE"
else
    echo "$KEEP_CONTENT" > "$LOG_FILE"
fi

echo "Rotirano: $TO_ARCHIVE entry-ja arhivirano, $MAX_ENTRIES zadržano." >&2
