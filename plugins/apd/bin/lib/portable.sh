#!/bin/bash
# APD portability shims — no side effects, safe to source from anywhere
# (including the detached stall-watch daemon, which deliberately carries no deps).
#
# WHY THIS EXISTS
# The codebase reached for the usual BSD-first idiom in eight places:
#
#     mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
#
# It reads as "try BSD, fall back to GNU", and it is broken on GNU. `stat -f` on
# GNU coreutils means "report the FILESYSTEM", not "use this format": it ignores
# the unknown `%m`, prints a five-line filesystem report to STDOUT, and only
# then exits non-zero. Command substitution keeps the stdout of BOTH branches,
# so the variable ends up holding the report with the epoch glued on the end.
#
# Nothing errors. The value is simply never a number again, and every consumer
# fails quietly in whichever direction its guard happens to point:
#   * `[ "$LOCK_MTIME" -gt 0 ] 2>/dev/null` is false → LOCK_AGE stays 0 → a
#     stale pipeline lock is NEVER reclaimed on Linux; the next session waits
#     on a dead one forever.
#   * `date -d "@$blob"` fails → reconstruct-agents writes empty timestamps and
#     the recovery it exists to perform produces a zero-duration pair.
#
# Measured on ubuntu:24.04 — this is where 60 of the suite's 76 Linux failures
# came from, and the macOS suite was green for all of it, because on macOS the
# first branch simply works and the second is never reached.
#
# The date chains in the same style are FINE and were checked, not assumed:
# `date -r <epoch>`, `date -j -f`, `date -v-7d` all fail on the other platform
# without writing anything to stdout, so their fallbacks compose correctly.

# _file_mtime <path> — modification time as a plain epoch integer, or 0.
#
# GNU first (its failure on BSD is clean), then BSD, and the result is VALIDATED
# as an integer rather than trusted. The validation is what actually makes this
# safe: it holds whichever order the two branches run in, and it holds for a
# `stat` this code has never met.
_file_mtime() {
    local v=""
    v=$(stat -c %Y "$1" 2>/dev/null) || v=""
    case "$v" in ''|*[!0-9]*) v="" ;; esac
    if [ -z "$v" ]; then
        v=$(stat -f %m "$1" 2>/dev/null) || v=""
        case "$v" in ''|*[!0-9]*) v="" ;; esac
    fi
    [ -n "$v" ] || v=0
    printf '%s' "$v"
}

# _cc_transcript_dir — CC's transcript directory for $PROJECT_DIR.
#
# CC names it after the RESOLVED working directory, every non-alphanumeric
# character turned into '-'. Every reader used the path as APD resolved it, which
# is the same thing only when nothing on the way is a symlink: on macOS a project
# reached through /var/… (every mktemp directory) is filed under -private-var-…,
# and the reader looked in a directory that does not exist (measured 2026-10-03
# with a live CC 2.1.288 session). The given form is tried first, then the
# physical one. Prints the directory; exits 1 (printing the given-form path,
# for messages) when neither exists.
_cc_transcript_dir() {
    local _root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" _p _d
    for _p in "$PROJECT_DIR" "$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"; do
        [ -n "$_p" ] || continue
        _d="$_root/$(printf '%s' "$_p" | sed 's#[^A-Za-z0-9]#-#g')"
        if [ -d "$_d" ]; then printf '%s' "$_d"; return 0; fi
    done
    printf '%s' "$_root/$(printf '%s' "$PROJECT_DIR" | sed 's#[^A-Za-z0-9]#-#g')"
    return 1
}
