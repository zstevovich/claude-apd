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
