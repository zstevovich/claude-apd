#!/bin/bash
# APD — Shared style library for unified CLI output
#
# Source after resolve-project.sh:
#   source "$(dirname "$0")/lib/resolve-project.sh"
#   source "$(dirname "$0")/lib/style.sh"
#
# Provides:
#   Colors    — V (violet), B (bold), G (green), Y (yellow), D (dim), RED, R (reset)
#   Markers   — MARK_DONE ■, MARK_TODO □, MARK_NEXT ◆, MARK_PASS ✓, MARK_FAIL ✗,
#               MARK_WARN !, MARK_FIX +, MARK_SKIP ○
#   Counters  — PASS_COUNT, FAIL_COUNT, WARN_COUNT (auto-incremented by helpers)
#   Functions — apd_header, apd_blocked, pass, fail, warn, ok, fix, skip, err,
#               section, format_duration, show_pipeline

# --- Colors (TTY-aware) ---
# Enable colors when: TTY detected, or Claude Code plugin hook, or terminal supports color
if [ -t 2 ] || [ -t 1 ] || [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [[ "${TERM:-}" == *color* ]]; then
    V=$'\033[38;5;135m'  # violet (brand)
    B=$'\033[1m'         # bold
    G=$'\033[32m'        # green
    Y=$'\033[33m'        # yellow
    D=$'\033[2m'         # dim
    RED=$'\033[31m'      # red
    R=$'\033[0m'         # reset
else
    V="" B="" G="" Y="" D="" RED="" R=""
fi

# --- Markers ---
MARK_DONE="${V}■${R}"
MARK_TODO="${V}□${R}"
MARK_NEXT="${V}${B}◆${R}"
MARK_PASS="${G}✓${R}"
MARK_FAIL="${RED}✗${R}"
MARK_WARN="${Y}!${R}"
MARK_FIX="${G}+${R}"
MARK_SKIP="${Y}○${R}"

# --- Counters ---
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# --- Helper functions ---

# apd_header "Title" ["+2m 15s"]
#   → \n  APD ■ Title
#   → \n  APD ■ Title  +2m 15s (dim)
apd_header() {
    local title="$1"
    local duration="${2:-}"
    echo ""
    if [ -n "$duration" ]; then
        printf "  %sAPD%s %s %s%s%s  %s%s%s\n" "$V" "$R" "$MARK_DONE" "$B" "$title" "$R" "$D" "$duration" "$R"
    else
        printf "  %sAPD%s %s %s%s%s\n" "$V" "$R" "$MARK_DONE" "$B" "$title" "$R"
    fi
}

# apd_blocked "Reason"
#   → \n  APD □ BLOCKED: Reason (red bold)
apd_blocked() {
    local reason="$1"
    echo ""
    printf "  %sAPD%s %s %s%sBLOCKED:%s %s\n" "$V" "$R" "$MARK_TODO" "$RED" "$B" "$R" "$reason"
}

# pass "msg" → ✓ msg (green) + increments PASS_COUNT
pass() {
    printf "  %s %s\n" "$MARK_PASS" "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# fail "msg" → ✗ msg (red) + increments FAIL_COUNT
fail() {
    printf "  %s %s\n" "$MARK_FAIL" "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# warn "msg" → ! msg (yellow) + increments WARN_COUNT
warn() {
    printf "  %s %s\n" "$MARK_WARN" "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

# ok "msg" → ■ msg (violet)
ok() {
    printf "  %s %s\n" "$MARK_DONE" "$1"
}

# fix "msg" → + msg (green)
fix() {
    printf "  %s %s\n" "$MARK_FIX" "$1"
}

# skip "msg" → ○ msg (skipped) (yellow, dim suffix)
skip() {
    printf "  %s %s %s(skipped)%s\n" "$MARK_SKIP" "$1" "$D" "$R"
}

# err "msg" → □ msg (violet, to stderr)
err() {
    printf "  %s %s\n" "$MARK_TODO" "$1" >&2
}

# section "Name" → \n  ── Name ── (dim separators)
section() {
    echo ""
    printf "  %s──%s %s %s──%s\n" "$D" "$R" "$1" "$D" "$R"
}

# format_duration $secs → "Xs" / "Xm Ys" / "Xh Ym"
format_duration() {
    local seconds=$1
    if [ "$seconds" -lt 60 ] 2>/dev/null; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ] 2>/dev/null; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $(( (seconds % 3600) / 60 ))m"
    fi
}

# show_pipeline [active_step]
# Displays pipeline progress bar using MARK_DONE/TODO/NEXT
# Requires $PIPELINE_DIR (from resolve-project.sh)
#   → ■ spec ── ■ builder ── □ reviewer ── □ verifier → commit
show_pipeline() {
    local active="${1:-}"
    local steps=("spec" "builder" "reviewer" "verifier")

    echo ""
    local bar="  "
    for i in "${!steps[@]}"; do
        local s="${steps[$i]}"
        if [ -f "$PIPELINE_DIR/$s.done" ]; then
            bar="${bar}${MARK_DONE} ${s}"
        elif [ "$s" = "$active" ]; then
            bar="${bar}${MARK_NEXT} ${s}"
        else
            bar="${bar}${MARK_TODO} ${s}"
        fi
        if [ "$i" -lt 3 ]; then
            bar="${bar} ${D}──${R} "
        fi
    done
    bar="${bar} ${D}→${R} commit"
    echo "$bar"
}
