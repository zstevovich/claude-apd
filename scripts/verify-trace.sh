#!/bin/bash
# APD Trace Verifier — checks @trace coverage against spec-card.md
#
# Usage:
#   verify-trace.sh                  # full colored report
#   verify-trace.sh --summary        # one-line output for session-log
#
# Exit codes:
#   0 — all acceptance criteria covered (or no spec-card.md)
#   1 — missing test coverage for one or more criteria

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0
source "$(dirname "$0")/lib/style.sh"

SPEC_CARD="$PIPELINE_DIR/spec-card.md"
SUMMARY_MODE=false
[ "${1:-}" = "--summary" ] && SUMMARY_MODE=true

# Temp files for data storage (avoids bash 4+ associative arrays)
SPEC_DATA=$(mktemp)
TEST_COUNT_FILE=$(mktemp)
CODE_COUNT_FILE=$(mktemp)
EXTRA_IDS_FILE=$(mktemp)
cleanup() { rm -f "$SPEC_DATA" "$TEST_COUNT_FILE" "$CODE_COUNT_FILE" "$EXTRA_IDS_FILE"; }
trap cleanup EXIT INT TERM

# --- If no spec-card.md, exit 0 (backward compatible) ---
if [ ! -f "$SPEC_CARD" ]; then
    exit 0
fi

# --- Parse R* IDs from spec-card.md ---
# Format: id|description — one per line
while IFS= read -r line; do
    id=$(echo "$line" | sed -nE 's/^[[:space:]]*-[[:space:]]+(R[0-9]+)[[:space:]]*:[[:space:]]*(.+)$/\1/p')
    desc=$(echo "$line" | sed -nE 's/^[[:space:]]*-[[:space:]]+(R[0-9]+)[[:space:]]*:[[:space:]]*(.+)$/\2/p')
    if [ -n "$id" ]; then
        echo "${id}|${desc}" >> "$SPEC_DATA"
    fi
done < "$SPEC_CARD"

TOTAL=$(wc -l < "$SPEC_DATA" | tr -d ' ')

if [ "$TOTAL" -eq 0 ]; then
    fail "spec-card.md exists but contains no R* acceptance criteria" >&2
    [ "$SUMMARY_MODE" = true ] && echo "TRACE:0/0:"
    exit 1
fi

# --- Build test file patterns based on stack ---
STACK="${CLAUDE_PLUGIN_OPTION_STACK:-}"

build_find_patterns() {
    case "$STACK" in
        nodejs)
            echo '-name *.test.ts -o -name *.spec.ts -o -name *.test.js -o -name *.spec.js -o -name *.test.tsx -o -name *.spec.tsx'
            ;;
        python)
            echo '-name test_*.py -o -name *_test.py'
            ;;
        php)
            echo '-name *Test.php'
            ;;
        dotnet)
            echo '-name *.Tests.cs -o -name *Test.cs'
            ;;
        go)
            echo '-name *_test.go'
            ;;
        java)
            echo '-name *Test.java -o -name *Spec.java'
            ;;
        *)
            echo '-name *.test.ts -o -name *.spec.ts -o -name *.test.js -o -name *.spec.js -o -name *.test.tsx -o -name *.spec.tsx -o -name test_*.py -o -name *_test.py -o -name *Test.php -o -name *.Tests.cs -o -name *Test.cs -o -name *_test.go -o -name *Test.java -o -name *Spec.java'
            ;;
    esac
}

PATTERNS=$(build_find_patterns)

# --- Discover test files ---
# Files matching test naming conventions
TEST_FILES=$(eval "find '$PROJECT_DIR' -type d \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f \( $PATTERNS \) -print" 2>/dev/null || true)

# Files inside test directories regardless of naming
TEST_DIR_FILES=$(find "$PROJECT_DIR" -type d \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f \( -path "*/__tests__/*" -o -path "*/tests/*" -o -path "*/test/*" -o -path "*/spec/*" \) -print 2>/dev/null || true)

# Combine and deduplicate
ALL_TEST_FILES=$(printf '%s\n' "$TEST_FILES" "$TEST_DIR_FILES" | sort -u | grep -v '^$' || true)

# --- Discover non-test code files (for informational trace counts) ---
ALL_CODE_FILES=$(find "$PROJECT_DIR" -type d \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.php" -o -name "*.cs" -o -name "*.go" -o -name "*.java" \) -print 2>/dev/null | sort -u | grep -v '^$' || true)

# --- Scan test files for @trace markers ---
# Output: one R* ID per line for each occurrence found
if [ -n "$ALL_TEST_FILES" ]; then
    echo "$ALL_TEST_FILES" | while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ ! -f "$file" ] && continue
        grep '@trace' "$file" 2>/dev/null | grep -oE 'R[0-9]+' || true
    done > "$TEST_COUNT_FILE"
fi

# --- Scan non-test code files for @trace markers (informational) ---
if [ -n "$ALL_CODE_FILES" ] && [ -n "$ALL_TEST_FILES" ]; then
    # Exclude test files from code files
    NON_TEST_CODE=$(printf '%s\n' "$ALL_CODE_FILES" | while IFS= read -r f; do
        if ! echo "$ALL_TEST_FILES" | grep -qxF "$f"; then
            echo "$f"
        fi
    done)
elif [ -n "$ALL_CODE_FILES" ]; then
    NON_TEST_CODE="$ALL_CODE_FILES"
else
    NON_TEST_CODE=""
fi

if [ -n "$NON_TEST_CODE" ]; then
    echo "$NON_TEST_CODE" | while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ ! -f "$file" ] && continue
        grep '@trace' "$file" 2>/dev/null | grep -oE 'R[0-9]+' || true
    done > "$CODE_COUNT_FILE"
fi

# --- Detect extra IDs (in tests but not in spec) ---
if [ -s "$TEST_COUNT_FILE" ]; then
    SPEC_IDS=$(cut -d'|' -f1 "$SPEC_DATA")
    sort -u "$TEST_COUNT_FILE" | while IFS= read -r rid; do
        if ! echo "$SPEC_IDS" | grep -qxF "$rid"; then
            echo "$rid"
        fi
    done > "$EXTRA_IDS_FILE"
fi

# --- Calculate coverage and generate output ---
COVERED=0
UNCOVERED_IDS=""

if [ "$SUMMARY_MODE" = false ]; then
    apd_header "Spec Traceability" >&2
fi

while IFS='|' read -r id desc; do
    tc=0; cc=0
    [ -s "$TEST_COUNT_FILE" ] && tc=$(grep -cxF "$id" "$TEST_COUNT_FILE" 2>/dev/null) || tc=0
    [ -s "$CODE_COUNT_FILE" ] && cc=$(grep -cxF "$id" "$CODE_COUNT_FILE" 2>/dev/null) || cc=0

    if [ "$tc" -gt 0 ]; then
        COVERED=$((COVERED + 1))
        if [ "$SUMMARY_MODE" = false ]; then
            suffix=""
            [ "$cc" -gt 0 ] && suffix=" code($cc)"
            suffix="${suffix} test($tc)"
            pass "${id}: ${desc}${suffix}" >&2
        fi
    else
        UNCOVERED_IDS="${UNCOVERED_IDS}${id},"
        if [ "$SUMMARY_MODE" = false ]; then
            fail "${id}: ${desc}  test missing" >&2
        fi
    fi
done < "$SPEC_DATA"

# Clean trailing comma
UNCOVERED_IDS="${UNCOVERED_IDS%,}"

# Extra markers warning
if [ "$SUMMARY_MODE" = false ] && [ -s "$EXTRA_IDS_FILE" ]; then
    echo "" >&2
    while IFS= read -r eid; do
        warn "${eid} found in tests but not in spec-card.md" >&2
    done < "$EXTRA_IDS_FILE"
fi

# Coverage summary
if [ "$SUMMARY_MODE" = false ]; then
    section "Coverage" >&2
    if [ "$COVERED" -eq "$TOTAL" ]; then
        printf "    %s%s/%s%s\n" "$G" "$COVERED" "$TOTAL" "$R" >&2
    else
        printf "    %s%s/%s%s\n" "$RED" "$COVERED" "$TOTAL" "$R" >&2
        # List uncovered
        for uid in $(echo "$UNCOVERED_IDS" | tr ',' ' '); do
            fail "${uid} missing test coverage" >&2
        done
    fi
fi

# Always emit summary on stdout (machine-readable, captured by pipeline-advance.sh)
echo "TRACE:${COVERED}/${TOTAL}:${UNCOVERED_IDS}"

# --- Exit code ---
if [ "$COVERED" -lt "$TOTAL" ]; then
    exit 1
fi
exit 0
