#!/bin/bash
# APD Session Log Rotation — archives older session entries
# Keeps the last MAX_ENTRIES, moves older ones to session-log-archive.md

source "$(dirname "$0")/lib/resolve-project.sh"
LOG_FILE="$MEMORY_DIR/session-log.md"
ARCHIVE_FILE="$MEMORY_DIR/session-log-archive.md"

MAX_ENTRIES="${1:-10}"

if [ ! -f "$LOG_FILE" ]; then
    exit 0
fi

ENTRY_COUNT=0
ENTRY_COUNT=$(grep -c '^## \[' "$LOG_FILE" 2>/dev/null) || ENTRY_COUNT=0

if [ "$ENTRY_COUNT" -le "$MAX_ENTRIES" ]; then
    exit 0
fi

TO_ARCHIVE=$((ENTRY_COUNT - MAX_ENTRIES))

echo "Session log rotation: $ENTRY_COUNT entries, archiving $TO_ARCHIVE older ones..." >&2

FIRST_ENTRY_LINE=$(grep -n '^## \[' "$LOG_FILE" | head -1 | cut -d: -f1)
HEADER=""

if [ -n "$FIRST_ENTRY_LINE" ] && [ "$FIRST_ENTRY_LINE" -gt 1 ]; then
    HEADER=$(head -n $((FIRST_ENTRY_LINE - 1)) "$LOG_FILE")
fi

KEEP_FROM_LINE=$(grep -n '^## \[' "$LOG_FILE" | tail -n "$MAX_ENTRIES" | head -1 | cut -d: -f1)

if [ -z "$KEEP_FROM_LINE" ]; then
    exit 0
fi

ARCHIVE_CONTENT=$(sed -n "${FIRST_ENTRY_LINE},$((KEEP_FROM_LINE - 1))p" "$LOG_FILE")
KEEP_CONTENT=$(sed -n "${KEEP_FROM_LINE},\$p" "$LOG_FILE")

if [ ! -f "$ARCHIVE_FILE" ]; then
    cat > "$ARCHIVE_FILE" << 'EOF'
# Session Log — Archive

> Archived session log entries. Rotation is automatic.

---

EOF
fi

# Generate meta-summary for archived entries
ARCHIVE_TASKS=$(echo "$ARCHIVE_CONTENT" | grep '^## \[' | wc -l | tr -d ' ')
ARCHIVE_PROBLEMS=$(echo "$ARCHIVE_CONTENT" | grep -i '^\*\*Problems:\*\*' | grep -cv 'No problems' 2>/dev/null || echo 0)
ARCHIVE_GUARDS=$(echo "$ARCHIVE_CONTENT" | grep -i '^\*\*Guardrail' | grep -cv 'N/A' 2>/dev/null || echo 0)
ARCHIVE_RULES=$(echo "$ARCHIVE_CONTENT" | grep -i '^\*\*New rule:\*\*' | grep -cv 'None' 2>/dev/null || echo 0)
ARCHIVE_DATE_FIRST=$(echo "$ARCHIVE_CONTENT" | grep -oE '^\#\# \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' | head -1 | tr -d '[]#' | tr -d ' ')
ARCHIVE_DATE_LAST=$(echo "$ARCHIVE_CONTENT" | grep -oE '^\#\# \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' | tail -1 | tr -d '[]#' | tr -d ' ')

META_SUMMARY="---
> **Rotation $(date +%Y-%m-%d):** $ARCHIVE_TASKS tasks archived ($ARCHIVE_DATE_FIRST -> $ARCHIVE_DATE_LAST). Problems: $ARCHIVE_PROBLEMS. Guard blocks: $ARCHIVE_GUARDS. New rules: $ARCHIVE_RULES.
---"

echo "$META_SUMMARY" >> "$ARCHIVE_FILE"
echo "" >> "$ARCHIVE_FILE"
echo "$ARCHIVE_CONTENT" >> "$ARCHIVE_FILE"

TMPFILE="$LOG_FILE.tmp"
if [ -n "$HEADER" ]; then
    printf '%s\n%s\n' "$HEADER" "$KEEP_CONTENT" > "$TMPFILE" && mv "$TMPFILE" "$LOG_FILE"
else
    echo "$KEEP_CONTENT" > "$TMPFILE" && mv "$TMPFILE" "$LOG_FILE"
fi

echo "Rotated: $TO_ARCHIVE entries archived, $MAX_ENTRIES kept." >&2
